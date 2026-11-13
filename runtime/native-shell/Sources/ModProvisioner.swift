import Foundation
import CryptoKit

// Launcher mod auto-provisioning (closes the README "fresh-install gap").
//
// On every shell start, before the launcher UI appears, the instance `mods/` directory is brought to a
// playable state without the user copying jars by hand:
//
//   * VRMC provider (LGPL-3.0, ships inside the app at <app>/vrmc/vrmc-provider.jar):
//       - missing                          -> installed from the bundle
//       - identical to the bundled jar     -> up to date
//       - unchanged since we last installed it, bundle is newer -> upgraded atomically
//       - anything else (a developer push via scripts/push_provider_jar.sh) -> left alone ("user-managed")
//     Documents/vrmc-provider-reset.flag forces the bundled jar back in (and is consumed).
//   * Vivecraft (LGPL-3.0, NOT redistributed): the user drops the official jar into the app's Documents
//     (Files app / AirDrop lands it in Documents or Documents/Inbox). A candidate is imported into
//     `mods/` only when its sha256 equals the pinned hash; mismatches are reported and left in place.
//   * Duplicate provider / Vivecraft jars in `mods/` (Fabric aborts on duplicate mod ids) are reported.
//
// Pure Foundation + CryptoKit so the policy is unit-tested on the macOS host
// (runtime/native-shell/tests/run_tests.sh). Nothing here touches the network.

struct ModProvisioningManifest: Equatable {
    /// Canonical file name Vivecraft is installed under in `mods/`.
    var vivecraftFileName: String
    /// Pinned lower-case hex sha256 of the official Vivecraft jar; empty disables import.
    var vivecraftSha256: String

    /// Mirrors versions.env (VIVECRAFT_VERSION / VIVECRAFT_JAR_SHA256). scripts/check_provisioning_pins.sh
    /// fails the release check if these drift.
    static let builtIn = ModProvisioningManifest(
        vivecraftFileName: "vivecraft-26.2-1.3.15-fabric.jar",
        vivecraftSha256: "e63aeed1a6b36a55fc38c7633acbbac2cdf8b46f546382c6a2cd9348440b58bb")

    /// Loads `provisioning.json` written by scripts/stage_native_app.sh; any missing/invalid field falls
    /// back to the built-in value so a malformed manifest can never disable provisioning silently.
    static func load(from url: URL?) -> ModProvisioningManifest {
        var manifest = builtIn
        guard let url, let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return manifest
        }
        if let name = object["vivecraftFileName"] as? String, isSafeJarName(name) {
            manifest.vivecraftFileName = name
        }
        if let hash = object["vivecraftSha256"] as? String, isHexSha256(hash.lowercased()) {
            manifest.vivecraftSha256 = hash.lowercased()
        }
        return manifest
    }

    static func isHexSha256(_ value: String) -> Bool {
        return value.count == 64 && value.allSatisfy { $0.isHexDigit }
    }

    static func isSafeJarName(_ name: String) -> Bool {
        return name.hasSuffix(".jar") && !name.contains("/") && !name.hasPrefix(".") && name.count <= 128
    }
}

enum ProviderProvisionOutcome: Equatable {
    case installed(sha256: String)
    case upgraded(from: String, to: String)
    case reset(sha256: String)
    case upToDate(sha256: String)
    case userManaged(sha256: String)
    case noBundle(installedSha256: String?)
    case failed(String)
}

enum VivecraftProvisionOutcome: Equatable {
    case verified(fileName: String)
    case unverified(fileName: String, sha256: String)
    case imported(from: String)
    case rejected(fileName: String, sha256: String)
    case missing
    case noPin
    case failed(String)
}

struct ModProvisionReport: Equatable {
    var provider: ProviderProvisionOutcome
    var vivecraft: VivecraftProvisionOutcome
    var warnings: [String]

    var providerPresent: Bool {
        switch provider {
        case .installed, .upgraded, .reset, .upToDate, .userManaged: return true
        case .noBundle(let installed): return installed != nil
        case .failed: return false
        }
    }

    var vivecraftPresent: Bool {
        switch vivecraft {
        case .verified, .unverified, .imported: return true
        case .rejected, .missing, .noPin, .failed: return false
        }
    }

    /// True when both required mods are in place; the launcher still lets the user play otherwise.
    var ready: Bool { return providerPresent && vivecraftPresent }

    var providerLine: String {
        switch provider {
        case .installed(let h): return "provider: installed from app bundle (\(short(h)))"
        case .upgraded(let from, let to): return "provider: upgraded \(short(from)) -> \(short(to))"
        case .reset(let h): return "provider: reset to bundled jar (\(short(h)))"
        case .upToDate(let h): return "provider: up to date (\(short(h)))"
        case .userManaged(let h): return "provider: user-managed jar kept (\(short(h)); bundle differs)"
        case .noBundle(let h):
            return h.map { "provider: present (\(short($0))); app has no bundled jar" }
                ?? "provider: MISSING and the app has no bundled jar"
        case .failed(let why): return "provider: FAILED (\(why))"
        }
    }

    var vivecraftLine: String {
        switch vivecraft {
        case .verified(let name): return "vivecraft: \(name) verified"
        case .unverified(let name, let h):
            return "vivecraft: \(name) present but sha256 \(short(h)) does not match the pin"
        case .imported(let from): return "vivecraft: imported \(from) (sha256 verified)"
        case .rejected(let name, let h):
            return "vivecraft: \(name) REJECTED (sha256 \(short(h)) does not match the pin); left in Documents"
        case .missing:
            return "vivecraft: MISSING; put the official jar in the VRMC folder (Files app) and relaunch"
        case .noPin: return "vivecraft: import disabled (no pinned sha256)"
        case .failed(let why): return "vivecraft: FAILED (\(why))"
        }
    }

    var lines: [String] { return [providerLine, vivecraftLine] + warnings.map { "warning: \($0)" } }

    private func short(_ hash: String) -> String { return String(hash.prefix(12)) }
}

struct ModProvisioner {
    static let providerFileName = "vrmc-provider.jar"
    static let stateFileName = "vrmc-provisioning.json"
    static let resetFlagName = "vrmc-provider-reset.flag"

    var documentsDir: URL
    var modsDir: URL
    /// The provider jar shipped inside the app, if the app was staged with one.
    var bundledProvider: URL?
    var manifest: ModProvisioningManifest
    var log: (String) -> Void = { _ in }
    var fileManager: FileManager = .default

    var stateURL: URL { return documentsDir.appendingPathComponent(Self.stateFileName) }
    var resetFlagURL: URL { return documentsDir.appendingPathComponent(Self.resetFlagName) }
    /// Where a user-supplied Vivecraft jar can arrive: Files-app drops land in Documents, AirDrop /
    /// "Open in" lands in Documents/Inbox.
    var importDirs: [URL] { return [documentsDir, documentsDir.appendingPathComponent("Inbox")] }

    static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func run() -> ModProvisionReport {
        do {
            try fileManager.createDirectory(at: modsDir, withIntermediateDirectories: true)
        } catch {
            let why = "cannot create \(modsDir.path): \(error.localizedDescription)"
            return ModProvisionReport(provider: .failed(why), vivecraft: .failed(why), warnings: [])
        }
        let provider = provisionProvider()
        let vivecraft = provisionVivecraft()
        let report = ModProvisionReport(provider: provider, vivecraft: vivecraft, warnings: duplicateWarnings())
        for line in report.lines { log("provisioning: \(line)") }
        log("provisioning: ready=\(report.ready)")
        return report
    }

    // MARK: provider

    func provisionProvider() -> ProviderProvisionOutcome {
        let target = modsDir.appendingPathComponent(Self.providerFileName)
        let installedHash = fileManager.fileExists(atPath: target.path) ? Self.sha256(of: target) : nil
        let resetRequested = fileManager.fileExists(atPath: resetFlagURL.path)
        if resetRequested { try? fileManager.removeItem(at: resetFlagURL) }

        guard let bundled = bundledProvider, fileManager.fileExists(atPath: bundled.path) else {
            if resetRequested { log("provisioning: reset requested but the app has no bundled provider jar") }
            return .noBundle(installedSha256: installedHash)
        }
        guard let bundledHash = Self.sha256(of: bundled) else {
            return .failed("cannot read bundled jar \(bundled.lastPathComponent)")
        }

        let lastProvisioned = readState()["providerSha256"] as? String
        let outcome: ProviderProvisionOutcome
        if let installed = installedHash {
            if installed == bundledHash {
                outcome = .upToDate(sha256: installed)
            } else if resetRequested {
                outcome = .reset(sha256: bundledHash)
            } else if installed == lastProvisioned {
                outcome = .upgraded(from: installed, to: bundledHash)
            } else {
                // A jar we did not put there (developer push / manual copy). Never overwrite it.
                return .userManaged(sha256: installed)
            }
        } else {
            outcome = .installed(sha256: bundledHash)
        }
        if case .upToDate = outcome {
            // Adopt an identical jar (e.g. a manual copy of the bundled one) so later upgrades apply.
            if lastProvisioned != bundledHash { writeState(providerSha256: bundledHash) }
            return outcome
        }
        do {
            try installAtomically(from: bundled, to: target, expectedSha256: bundledHash)
        } catch {
            return .failed("install: \(error.localizedDescription)")
        }
        writeState(providerSha256: bundledHash)
        return outcome
    }

    // MARK: vivecraft

    func provisionVivecraft() -> VivecraftProvisionOutcome {
        let pin = manifest.vivecraftSha256.lowercased()
        let installed = jarNames(in: modsDir).filter(isVivecraftName)
        if !installed.isEmpty {
            var firstUnverified: (String, String)?
            for name in installed {
                guard let hash = Self.sha256(of: modsDir.appendingPathComponent(name)) else { continue }
                if !pin.isEmpty && hash == pin { return .verified(fileName: name) }
                if firstUnverified == nil { firstUnverified = (name, hash) }
            }
            if let (name, hash) = firstUnverified { return .unverified(fileName: name, sha256: hash) }
            return .failed("cannot read \(installed[0])")
        }
        guard ModProvisioningManifest.isHexSha256(pin) else { return .noPin }

        var rejected: (String, String)?
        for dir in importDirs {
            for name in jarNames(in: dir) where isVivecraftName(name) {
                let source = dir.appendingPathComponent(name)
                guard let hash = Self.sha256(of: source) else { continue }
                guard hash == pin else {
                    if rejected == nil { rejected = (name, hash) }
                    continue
                }
                let target = modsDir.appendingPathComponent(manifest.vivecraftFileName)
                do {
                    try installAtomically(from: source, to: target, expectedSha256: pin)
                    try? fileManager.removeItem(at: source)
                } catch {
                    return .failed("import \(name): \(error.localizedDescription)")
                }
                return .imported(from: name)
            }
        }
        if let (name, hash) = rejected { return .rejected(fileName: name, sha256: hash) }
        return .missing
    }

    // MARK: checks

    /// Fabric refuses to start with two jars carrying the same mod id; name both so the user can fix it.
    func duplicateWarnings() -> [String] {
        let names = jarNames(in: modsDir)
        var warnings: [String] = []
        let providers = names.filter { $0.lowercased().hasPrefix("vrmc-provider") }
        if providers.count > 1 {
            warnings.append("multiple provider jars in mods/ (\(providers.joined(separator: ", "))); keep only \(Self.providerFileName)")
        }
        let vivecrafts = names.filter(isVivecraftName)
        if vivecrafts.count > 1 {
            warnings.append("multiple Vivecraft jars in mods/ (\(vivecrafts.joined(separator: ", "))); keep only one")
        }
        return warnings
    }

    // MARK: helpers

    private func isVivecraftName(_ name: String) -> Bool {
        return name.lowercased().hasPrefix("vivecraft")
    }

    private func jarNames(in dir: URL) -> [String] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { $0.lowercased().hasSuffix(".jar") && !$0.hasPrefix(".") }.sorted()
    }

    /// Copy to a hidden temp file next to the target, verify, then swap in. Fabric only loads `*.jar`,
    /// so a crash mid-copy never leaves a half-written jar it would try to load.
    private func installAtomically(from source: URL, to target: URL, expectedSha256: String) throws {
        let temp = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).partial")
        try? fileManager.removeItem(at: temp)
        try fileManager.copyItem(at: source, to: temp)
        guard Self.sha256(of: temp) == expectedSha256 else {
            try? fileManager.removeItem(at: temp)
            throw NSError(domain: "dev.vrmc.provisioning", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "copied jar failed sha256 verification"])
        }
        if fileManager.fileExists(atPath: target.path) {
            _ = try fileManager.replaceItemAt(target, withItemAt: temp)
        } else {
            try fileManager.moveItem(at: temp, to: target)
        }
    }

    private func readState() -> [String: Any] {
        guard let data = try? Data(contentsOf: stateURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private func writeState(providerSha256: String) {
        let state: [String: Any] = [
            "providerSha256": providerSha256,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) else { return }
        do {
            try data.write(to: stateURL, options: .atomic)
        } catch {
            log("provisioning: state write FAILED: \(error.localizedDescription)")
        }
    }
}
