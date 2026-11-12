import Foundation
import UIKit
import Observation
import CryptoKit
import ObjectiveC

/// Thin, failure-tolerant access to the Amethyst launcher that lives in the app binary.
///
/// The shell framework has no link-time dependency on the launcher: everything goes through the
/// Objective-C runtime / dlsym and degrades to "not available" when a symbol is missing, so a
/// launcher change can never stop the shell from loading.
@MainActor
enum LauncherBridge {
    private static var cachedController: UIViewController?

    /// The one launcher view controller of this process. It is created once and reused so the
    /// Launcher tab and the Play button talk to the same instance.
    static func launcherController() -> UIViewController {
        if let cachedController {
            // SwiftUI may rebuild the representable; detach the single instance from its old parent.
            if cachedController.parent != nil {
                cachedController.willMove(toParent: nil)
                cachedController.view.removeFromSuperview()
                cachedController.removeFromParent()
            }
            return cachedController
        }
        let controller: UIViewController
        if let cls = NSClassFromString("LauncherSplitViewController") as? UIViewController.Type {
            controller = cls.init()
            shellLog("launcher host created")
        } else {
            controller = UIViewController()
            controller.view.backgroundColor = .clear
            shellLog("launcher host: LauncherSplitViewController not found (running outside the app?)")
        }
        cachedController = controller
        return controller
    }

    /// True when the real launcher is present (false in the standalone preview host).
    static var launcherAvailable: Bool {
        NSClassFromString("LauncherSplitViewController") != nil
    }

    /// JIT state as the launcher itself checks it before starting the game; nil when unknown.
    static func jitEnabled() -> Bool? {
        typealias IsJITEnabled = @convention(c) (Bool) -> Bool
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "isJITEnabled") else { return nil }
        return unsafeBitCast(symbol, to: IsJITEnabled.self)(false)
    }

    private static func find(_ className: String, in root: UIViewController?) -> UIViewController? {
        guard let root, let cls = NSClassFromString(className) else { return nil }
        if root.isKind(of: cls) { return root }
        for child in root.children {
            if let hit = find(className, in: child) { return hit }
        }
        return nil
    }

    private static func playButton() -> (owner: UIViewController, button: UIButton)? {
        guard let navigation = find("LauncherNavigationController", in: cachedController),
              navigation.responds(to: NSSelectorFromString("buttonInstall")),
              let button = navigation.value(forKey: "buttonInstall") as? UIButton else { return nil }
        return (navigation, button)
    }

    /// Title of the launcher's own Play/Install button ("Play", "Install", …), nil when not loaded.
    static func playButtonTitle() -> String? {
        playButton()?.button.currentTitle
    }

    /// Press the launcher's own Play button, exactly as a tap would (same enabled state, same
    /// install/JIT/download flow). Returns false when the launcher is not on screen yet or busy.
    @discardableResult
    static func pressPlay() -> Bool {
        guard let (owner, button) = playButton() else {
            shellLog("launcher play: button not available yet")
            return false
        }
        guard button.isEnabled, owner.viewIfLoaded?.window != nil else {
            shellLog("launcher play: button disabled or launcher not on screen (enabled=\(button.isEnabled))")
            return false
        }
        let action = "performInstallOrShowDetails:"
        for event in [UIControl.Event.primaryActionTriggered, .touchUpInside] {
            if button.actions(forTarget: owner, forControlEvent: event)?.contains(action) == true {
                button.sendActions(for: event)
                shellLog("launcher play: pressed (control event \(event.rawValue))")
                return true
            }
        }
        let selector = NSSelectorFromString(action)
        if owner.responds(to: selector) {
            owner.perform(selector, with: button)
            shellLog("launcher play: invoked \(action) directly")
            return true
        }
        shellLog("launcher play: no play action found on the launcher")
        return false
    }

    /// The launcher's "Welcome to VRMC" alert stores its dismissal under a preference key that was
    /// never registered, so the alert came back on every launch (device log 2026-11-07: "Getter could
    /// not find preference vrmc.first_run_done"). First-run guidance now lives in the Play tab, so
    /// the alert method is replaced with a no-op. No-op when the method does not exist.
    nonisolated static func suppressLegacyWelcome() {
        guard let cls = NSClassFromString("LauncherMenuViewController"),
              let method = class_getInstanceMethod(cls, NSSelectorFromString("showVRMCWelcomeIfNeeded")) else {
            shellLog("legacy welcome alert: not present")
            return
        }
        let replacement: @convention(block) (AnyObject) -> Void = { _ in }
        method_setImplementation(method, imp_implementationWithBlock(replacement))
        shellLog("legacy welcome alert suppressed (first-run guidance is in the Play tab)")
    }
}

/// What the automatic setup knows about one requirement.
enum SetupStatus: Equatable {
    case checking
    case ready(String)
    case attention(String)
    case missing(String)

    var isReady: Bool { if case .ready = self { return true } else { return false } }
    var detail: String {
        switch self {
        case .checking: return "Checking…"
        case .ready(let text), .attention(let text), .missing(let text): return text
        }
    }
}

/// Automatic setup: installs what VRMC can install by itself and reports the rest precisely.
///
///  - VRMC mod (the LGPL provider): bundled in this framework and copied into the instance's mods
///    folder at every launch when missing or different. `Documents/vrmc-dev-provider.flag` keeps a
///    developer-pushed jar instead.
///  - Vivecraft: not redistributed. One tap downloads the pinned build from Modrinth and verifies
///    its SHA-256 before it is installed; a jar can also be imported from Files.
///  - Fabric profile, account and JIT are owned by the launcher/StikDebug; they are detected and
///    explained, not changed.
@MainActor
@Observable
final class SetupManager {
    static let shared = SetupManager()

    nonisolated static let vivecraftVersion = "26.2-1.3.15"
    nonisolated static let vivecraftFileName = "vivecraft-26.2-1.3.15-fabric.jar"
    nonisolated static let vivecraftSHA256 = "e63aeed1a6b36a55fc38c7633acbbac2cdf8b46f546382c6a2cd9348440b58bb"
    nonisolated static let vivecraftBytes = 6_685_183
    /// Modrinth CDN file of the pinned build (project "vivecraft", version 26.2-1.3.15-fabric).
    nonisolated static let vivecraftURL = URL(string:
        "https://cdn.modrinth.com/data/wGoQDPN5/versions/VrqKDtZn/vivecraft-26.2-1.3.15-fabric.jar")!
    nonisolated static let minecraftVersion = "26.2"

    private(set) var provider: SetupStatus = .checking
    private(set) var vivecraft: SetupStatus = .checking
    private(set) var fabric: SetupStatus = .checking
    private(set) var account: SetupStatus = .checking
    private(set) var jit: SetupStatus = .checking
    private(set) var downloading = false
    private(set) var downloadProgress: Double = 0
    private(set) var lastActionMessage = ""

    @ObservationIgnored private var providerStartupResult: SetupStatus?

    /// Play is gated only on what automatic setup owns and can verify itself (the bundled VRMC mod
    /// and the Vivecraft jar). The launcher owns the Fabric profile, the account and JIT, and its own
    /// Play button already reflects those, so an unreadable/stale launcher file can never dead-end
    /// our Play button while the game is in fact launchable.
    var readyToPlay: Bool {
        provider.isReady && vivecraftUsable
    }

    /// Vivecraft counts as usable when a jar is installed, also an untested build (shown as a note).
    var vivecraftUsable: Bool {
        switch vivecraft {
        case .ready, .attention: return true
        default: return false
        }
    }

    private init() {}

    // MARK: Paths

    nonisolated static func gameDirectory() -> URL {
        shellDocumentsURL().appendingPathComponent("instances/default")
    }

    nonisolated static func modsDirectory() -> URL {
        gameDirectory().appendingPathComponent("mods")
    }

    nonisolated static func bundledProviderURL() -> URL? {
        Bundle(for: ShellCoordinator.self).url(forResource: "vrmc-provider", withExtension: "jar")
    }

    nonisolated static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: VRMC mod (provider)

    /// Runs before the SwiftUI app starts (no UI yet): file work only.
    nonisolated func installBundledProviderAtStartup() {
        let status = Self.installBundledProvider()
        Task { @MainActor in
            self.providerStartupResult = status
            self.provider = status
        }
    }

    nonisolated private static func installBundledProvider() -> SetupStatus {
        let fm = FileManager.default
        let installed = modsDirectory().appendingPathComponent("vrmc-provider.jar")
        let installedHash = sha256(of: installed)
        if shellDocumentFlag("vrmc-dev-provider.flag"), let installedHash {
            shellLog("setup: developer provider kept (vrmc-dev-provider.flag) sha256=\(installedHash.prefix(12))")
            return .ready("Developer build \(installedHash.prefix(8))")
        }
        guard let bundled = bundledProviderURL(), let bundledHash = sha256(of: bundled) else {
            if let installedHash {
                shellLog("setup: no bundled provider; keeping installed jar sha256=\(installedHash.prefix(12))")
                return .ready("Installed \(installedHash.prefix(8))")
            }
            shellLog("setup: provider jar missing and none bundled")
            return .missing("The VRMC mod is not installed and this build does not include it.")
        }
        if installedHash == bundledHash {
            return .ready("Installed \(bundledHash.prefix(8))")
        }
        do {
            try fm.createDirectory(at: modsDirectory(), withIntermediateDirectories: true)
            let staging = modsDirectory().appendingPathComponent(".vrmc-provider.jar.tmp")
            try? fm.removeItem(at: staging)
            try fm.copyItem(at: bundled, to: staging)
            if fm.fileExists(atPath: installed.path) {
                _ = try fm.replaceItemAt(installed, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: installed)
            }
            guard sha256(of: installed) == bundledHash else {
                shellLog("setup: provider install verification FAILED")
                return .missing("The VRMC mod could not be verified after installing.")
            }
            shellLog("setup: provider \(installedHash == nil ? "installed" : "updated") sha256=\(bundledHash.prefix(12)) (was \(installedHash?.prefix(12) ?? "missing"))")
            return .ready("\(installedHash == nil ? "Installed" : "Updated to") \(bundledHash.prefix(8))")
        } catch {
            shellLog("setup: provider install FAILED: \(error)")
            return .missing("The VRMC mod could not be installed: \(error.localizedDescription)")
        }
    }

    func reinstallProvider() {
        let installed = Self.modsDirectory().appendingPathComponent("vrmc-provider.jar")
        try? FileManager.default.removeItem(at: installed)
        try? FileManager.default.removeItem(at: shellDocumentsURL().appendingPathComponent("vrmc-dev-provider.flag"))
        provider = Self.installBundledProvider()
        lastActionMessage = provider.isReady ? "VRMC mod reinstalled." : provider.detail
    }

    // MARK: Refresh

    /// Re-evaluate every requirement from disk (cheap; called on appear and every few seconds).
    func refresh() {
        if !downloading {
            let state = Self.inspectVivecraft()
            if vivecraft != state { vivecraft = state }
        }
        let providerState = Self.inspectProvider(fallback: providerStartupResult)
        if provider != providerState { provider = providerState }
        let fabricState = Self.inspectFabric()
        if fabric != fabricState { fabric = fabricState }
        let accountState = Self.inspectAccount()
        if account != accountState { account = accountState }
        let jitState: SetupStatus
        switch LauncherBridge.jitEnabled() {
        case .some(true): jitState = .ready("Enabled")
        case .some(false): jitState = .attention("Not enabled yet — StikDebug enables it when you press Play.")
        case .none: jitState = .attention("Unknown on this build.")
        }
        if jit != jitState { jit = jitState }
    }

    nonisolated private static func inspectProvider(fallback: SetupStatus?) -> SetupStatus {
        let installed = modsDirectory().appendingPathComponent("vrmc-provider.jar")
        guard FileManager.default.fileExists(atPath: installed.path) else {
            if case .missing = fallback { return fallback! }
            return .missing("The VRMC mod is missing from the mods folder.")
        }
        if case .ready = fallback { return fallback! }
        return .ready("Installed")
    }

    nonisolated private static func installedVivecraftJars() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: modsDirectory(), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files.filter {
            $0.pathExtension.lowercased() == "jar" && $0.lastPathComponent.lowercased().hasPrefix("vivecraft")
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Hashing 6.7 MB every refresh would be wasteful: cache by path + size + modification date.
    nonisolated(unsafe) private static var vivecraftHashCache: (key: String, hash: String)?

    nonisolated private static func inspectVivecraft() -> SetupStatus {
        let jars = installedVivecraftJars()
        guard let jar = jars.first else {
            return .missing("Vivecraft \(vivecraftVersion) is not installed.")
        }
        if jars.count > 1 {
            return .attention("More than one Vivecraft jar is installed (\(jars.map(\.lastPathComponent).joined(separator: ", "))). Keep one, or the game will not start.")
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: jar.path)
        let key = "\(jar.path)|\(attrs?[.size] ?? 0)|\(attrs?[.modificationDate] ?? Date.distantPast)"
        let hash: String?
        if let cached = vivecraftHashCache, cached.key == key {
            hash = cached.hash
        } else {
            hash = sha256(of: jar)
            if let hash { vivecraftHashCache = (key, hash) }
        }
        if hash == vivecraftSHA256 {
            return .ready("\(vivecraftVersion), verified")
        }
        return .attention("\(jar.lastPathComponent) is not the tested build (\(vivecraftVersion)). It may work; replace it if the game fails to start.")
    }

    nonisolated private static func inspectFabric() -> SetupStatus {
        let url = gameDirectory().appendingPathComponent("launcher_profiles.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = root["profiles"] as? [String: Any] else {
            return .missing("No game profile yet. In Launcher, install Fabric for Minecraft \(minecraftVersion).")
        }
        func versionId(_ name: String) -> String {
            ((profiles[name] as? [String: Any])?["lastVersionId"] as? String) ?? ""
        }
        func isFabricTarget(_ id: String) -> Bool {
            let lower = id.lowercased()
            return lower.contains("fabric") && lower.hasSuffix(minecraftVersion)
        }
        let selected = root["selectedProfile"] as? String ?? ""
        let selectedId = versionId(selected)
        if isFabricTarget(selectedId) {
            return .ready(selectedId)
        }
        if let other = profiles.keys.sorted().first(where: { isFabricTarget(versionId($0)) }) {
            return .attention("Select the profile “\(other)” in Launcher (currently “\(selected)”).")
        }
        return .missing("In Launcher, install Fabric for Minecraft \(minecraftVersion) and select that profile.")
    }

    nonisolated private static func inspectAccount() -> SetupStatus {
        let dir = shellDocumentsURL().appendingPathComponent("accounts")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let accounts = files.filter { $0.pathExtension.lowercased() == "json" }
        if let first = accounts.first {
            return .ready(accounts.count == 1 ? first.deletingPathExtension().lastPathComponent
                                              : "\(accounts.count) accounts")
        }
        return .missing("Sign in with your Minecraft account in Launcher.")
    }

    // MARK: Vivecraft

    /// Download the pinned Vivecraft build from Modrinth, verify it, and install it. Nothing is
    /// installed unless the size and SHA-256 match the pinned values.
    func downloadVivecraft() {
        guard !downloading else { return }
        downloading = true
        downloadProgress = 0
        lastActionMessage = ""
        shellLog("setup: Vivecraft download started (\(Self.vivecraftURL.absoluteString))")
        Task {
            let result = await Self.fetchVivecraft { fraction in
                Task { @MainActor in SetupManager.shared.downloadProgress = fraction }
            }
            self.downloading = false
            switch result {
            case .success:
                self.lastActionMessage = "Vivecraft \(Self.vivecraftVersion) installed and verified."
                shellLog("setup: Vivecraft installed and verified")
            case .failure(let error):
                self.lastActionMessage = error.message
                shellLog("setup: Vivecraft download FAILED: \(error.message)")
            }
            self.refresh()
        }
    }

    struct SetupError: Error { let message: String }

    nonisolated private static func fetchVivecraft(progress: @escaping @Sendable (Double) -> Void) async -> Result<Void, SetupError> {
        var request = URLRequest(url: vivecraftURL)
        request.timeoutInterval = 60
        // Modrinth asks automated clients to identify themselves; a generic product token only.
        request.setValue("VRMC/1.3 (visionOS sideload)", forHTTPHeaderField: "User-Agent")
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vivecraft-\(UUID().uuidString).jar")
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                return .failure(SetupError(message: "Download failed (HTTP \(code)). Check the connection, or import the jar from Files."))
            }
            FileManager.default.createFile(atPath: temp.path, contents: nil)
            let handle = try FileHandle(forWritingTo: temp)
            defer { try? handle.close() }
            var buffer = Data()
            buffer.reserveCapacity(1 << 16)
            var received = 0
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 1 << 16 {
                    received += buffer.count
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                    progress(min(1.0, Double(received) / Double(vivecraftBytes)))
                    if received > vivecraftBytes * 2 {
                        return .failure(SetupError(message: "Download rejected: the file is larger than expected."))
                    }
                }
            }
            if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
            try handle.close()
        } catch {
            return .failure(SetupError(message: "Download failed: \(error.localizedDescription)"))
        }
        guard let hash = sha256(of: temp), hash == vivecraftSHA256 else {
            return .failure(SetupError(message: "Download rejected: the file does not match the expected checksum. Nothing was installed."))
        }
        return installVivecraft(from: temp, as: vivecraftFileName)
    }

    /// Put one Vivecraft jar into mods/ and remove every other Vivecraft jar (Fabric refuses to
    /// start with two copies of the same mod).
    nonisolated private static func installVivecraft(from source: URL, as name: String) -> Result<Void, SetupError> {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: modsDirectory(), withIntermediateDirectories: true)
            let staging = modsDirectory().appendingPathComponent(".vivecraft.jar.tmp")
            try? fm.removeItem(at: staging)
            try fm.copyItem(at: source, to: staging)
            for old in installedVivecraftJars() { try fm.removeItem(at: old) }
            try fm.moveItem(at: staging, to: modsDirectory().appendingPathComponent(name))
            vivecraftHashCache = nil
            return .success(())
        } catch {
            return .failure(SetupError(message: "Could not install Vivecraft: \(error.localizedDescription)"))
        }
    }

    /// Install a Vivecraft jar the user picked in Files. The pinned build is reported as verified;
    /// any other Vivecraft jar is installed with a clear "untested build" note.
    func importVivecraft(from picked: URL) {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let name = picked.lastPathComponent
        guard picked.pathExtension.lowercased() == "jar", name.lowercased().hasPrefix("vivecraft") else {
            lastActionMessage = "That is not a Vivecraft jar (expected a file named vivecraft-….jar)."
            return
        }
        guard let head = try? FileHandle(forReadingFrom: picked).read(upToCount: 4),
              head.count == 4, head[0] == 0x50, head[1] == 0x4B else {
            lastActionMessage = "That file is not a valid jar."
            return
        }
        let size = ((try? picked.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
        guard size > 100_000, size < 64_000_000 else {
            lastActionMessage = "That file does not look like Vivecraft (unexpected size)."
            return
        }
        let verified = Self.sha256(of: picked) == Self.vivecraftSHA256
        switch Self.installVivecraft(from: picked, as: verified ? Self.vivecraftFileName : name) {
        case .success:
            lastActionMessage = verified ? "Vivecraft \(Self.vivecraftVersion) imported and verified."
                                         : "\(name) imported. It is not the tested build."
            shellLog("setup: Vivecraft imported verified=\(verified)")
        case .failure(let error):
            lastActionMessage = error.message
            shellLog("setup: Vivecraft import FAILED: \(error.message)")
        }
        refresh()
    }
}
