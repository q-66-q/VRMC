import SwiftUI
import CompositorServices
import UIKit
import Observation
import Foundation
import AudioToolbox
import CryptoKit

/// Entry point called from the Amethyst C main() (iOS-compat binary) via dlopen/dlsym.
/// The shell adopts SwiftUI's app lifecycle so visionOS immersive scenes / CompositorLayer exist.
func shellLog(_ message: String) {
    let line = "[shell] \(Date()) \(message)\n"
    NSLog("%@", line)
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let url = docs.appendingPathComponent("vrmc-shell.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}

private func shellDocumentsURL() -> URL {
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
}

/// M6/M5 in-headset acceptance checklist persisted to Documents and included in diagnostics exports.
private struct ShellAcceptanceItem: Identifiable, Codable {
    var id: String
    var title: String
    var status: String
}

private let shellAcceptanceStatuses = ["NOT RUN", "PARTIAL", "PASS", "FAIL"]

private func shellAcceptanceDefaults() -> [ShellAcceptanceItem] {
    [
        .init(id: "H1", title: "Menu/continue/new world", status: "NOT RUN"),
        .init(id: "H2", title: "Move/turn/teleport/jump/sneak", status: "NOT RUN"),
        .init(id: "H3", title: "Seated + standing modes", status: "NOT RUN"),
        .init(id: "H4", title: "Break/place/use/eat/interact", status: "NOT RUN"),
        .init(id: "H5", title: "Inventory + hotbar (wheel 1-9)", status: "NOT RUN"),
        .init(id: "H6", title: "Pause/options/death/respawn", status: "NOT RUN"),
        .init(id: "H7", title: "Visible hands/held item", status: "NOT RUN"),
        .init(id: "H8", title: "Bow draw/fire (two hands)", status: "NOT RUN"),
        .init(id: "H9", title: "Climbing + climb jump", status: "NOT RUN"),
        .init(id: "H10", title: "Save/reload/settings persistence", status: "NOT RUN"),
        .init(id: "AC-1", title: "Fresh install -> world, native", status: "NOT RUN"),
        .init(id: "AC-2", title: "Stereo/eye/head alignment", status: "NOT RUN"),
        .init(id: "AC-3", title: "Hands-only control", status: "NOT RUN"),
        .init(id: "AC-4", title: "All P0 actions, no stuck input", status: "NOT RUN"),
        .init(id: "AC-5", title: "Soak/launch/world-load clean", status: "NOT RUN"),
        .init(id: "AC-6", title: "Legal/source/no MC binaries", status: "NOT RUN"),
    ]
}

private func shellLoadAcceptanceChecklist() -> [ShellAcceptanceItem] {
    let url = shellDocumentsURL().appendingPathComponent("vrmc-acceptance-checklist.json")
    guard let data = try? Data(contentsOf: url),
          let items = try? JSONDecoder().decode([ShellAcceptanceItem].self, from: data),
          !items.isEmpty else {
        return shellAcceptanceDefaults()
    }
    return items
}

private func shellChecklistMarkdown(_ items: [ShellAcceptanceItem]) -> String {
    var text = "# VRMC device acceptance checklist\n\n"
    text += "generated: \(Date())\n\n"
    text += "| ID | Check | Status |\n|---|---|---|\n"
    for item in items {
        text += "| \(item.id) | \(item.title) | \(item.status) |\n"
    }
    text += "\nPaste the completed rows into VERIFY evidence; device-only gates are not satisfied by host runs.\n"
    return text
}

@discardableResult
private func shellSaveAcceptanceChecklist(_ items: [ShellAcceptanceItem]) -> Bool {
    let docs = shellDocumentsURL()
    let url = docs.appendingPathComponent("vrmc-acceptance-checklist.json")
    do {
        let data = try JSONEncoder().encode(items)
        try data.write(to: url, options: .atomic)
        try shellChecklistMarkdown(items).write(
            to: docs.appendingPathComponent("vrmc-acceptance-summary.md"),
            atomically: true, encoding: .utf8)
        return true
    } catch {
        shellLog("VRMC acceptance checklist save FAILED: \(error)")
        return false
    }
}

private func shellDocumentFlag(_ name: String) -> Bool {
    return FileManager.default.fileExists(atPath: shellDocumentsURL().appendingPathComponent(name).path)
}

private func shellDocumentString(_ name: String) -> String? {
    let url = shellDocumentsURL().appendingPathComponent(name)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

// M5 launcher settings: the provider reads vrmc-runtime.properties from the default game directory at
// the next launch. The shell panel edits only the keys it owns and preserves any other user keys.
private func shellRuntimeSettingsURL() -> URL {
    return shellDocumentsURL()
        .appendingPathComponent("instances/default")
        .appendingPathComponent("vrmc-runtime.properties")
}

/// Minimal `key=value` .properties reader shared by the launcher-owned settings files: skips blank,
/// `#` and `!` comment lines and lines without `=`; later duplicates win (java.util.Properties order).
private func shellReadProperties(_ url: URL) -> [String: String] {
    var values: [String: String] = [:]
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return values }
    for line in text.split(whereSeparator: \.isNewline) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("!") { continue }
        guard let eq = trimmed.firstIndex(of: "=") else { continue }
        let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
        let value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        if !key.isEmpty { values[key] = value }
    }
    return values
}

private func shellReadRuntimeSettings() -> [String: String] {
    return shellReadProperties(shellRuntimeSettingsURL())
}

/// Queue an M5 provider command (recenter / calibrate-height / reload-settings / diag / status).
/// The provider consumes it while the game runs; queued commands are harmless if consumed early.
private func shellQueueGameCommand(_ command: String) -> Bool {
    let url = shellDocumentsURL()
        .appendingPathComponent("instances/default")
        .appendingPathComponent("vrmc-command.txt")
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try (command + "\n").write(to: url, atomically: true, encoding: .utf8)
        shellLog("VRMC command queued: \(command) -> \(url.path)")
        return true
    } catch {
        shellLog("VRMC command queue FAILED (\(command)): \(error)")
        return false
    }
}

/// M5 diagnostics export: one local text bundle the user can AirDrop/share. No network, no telemetry.
private func shellBuildDiagnosticsBundle() -> URL? {
    let docs = shellDocumentsURL()
    let game = docs.appendingPathComponent("instances/default")
    var entries: [(String, URL, Int)] = [
        ("shell log", docs.appendingPathComponent("vrmc-shell.log"), 262_144),
        ("compositor log", docs.appendingPathComponent("vrmc-compositor.log"), 262_144),
        ("thermal log", docs.appendingPathComponent("vrmc-thermal.log"), 65_536),
        ("minecraft log (tail)", docs.appendingPathComponent("latestlog.txt"), 262_144),
        ("provider status", game.appendingPathComponent("vrmc-status.json"), 65_536),
        ("shutdown journal", game.appendingPathComponent("vrmc-shutdown.log"), 65_536),
        ("command results", game.appendingPathComponent("vrmc-command-result.txt"), 65_536),
        ("runtime settings", game.appendingPathComponent("vrmc-runtime.properties"), 32_768),
        ("input tuning", game.appendingPathComponent("vrmc-input-tune.properties"), 32_768),
        ("acceptance checklist", docs.appendingPathComponent("vrmc-acceptance-checklist.json"), 32_768),
        ("acceptance summary", docs.appendingPathComponent("vrmc-acceptance-summary.md"), 32_768),
        ("thermal state", game.appendingPathComponent("vrmc-thermal-state.txt"), 4_096),
        ("hand calibration", game.appendingPathComponent("vrmc-hand-calibration.txt"), 16_384),
        ("vignette flag", docs.appendingPathComponent("vrmc-vignette.flag"), 1_024),
        ("game latest log", game.appendingPathComponent("logs/latest.log"), 262_144),
        ("compositor heartbeat", docs.appendingPathComponent("vrmc-heartbeat.txt"), 4_096),
    ]
    // Include crash/teardown artifacts so a support bundle captures the evidence that matters.
    var extras: [URL] = [
        docs.appendingPathComponent("vrmc-compositor.prev.log"),
        docs.appendingPathComponent("vrmc-shell.prev.log"),
        game.appendingPathComponent("hs_err_pid.log"),
    ]
    if let files = try? FileManager.default.contentsOfDirectory(
        at: game, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
        for url in files where url.lastPathComponent.hasPrefix("hs_err_pid")
            && url.pathExtension == "log" {
            extras.append(url)
        }
    }
    let crashReports = game.appendingPathComponent("crash-reports")
    if let reports = try? FileManager.default.contentsOfDirectory(at: crashReports,
                                                                  includingPropertiesForKeys: nil) {
        for url in reports where url.pathExtension == "txt" { extras.append(url) }
    }
    for (index, url) in extras.prefix(6).enumerated() {
        entries.append(("crash/extra \(index + 1)", url, 131_072))
    }
    var text = "VRMC diagnostics export\n"
    text += "app=\(Bundle.main.bundleIdentifier ?? "?") version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")\n"
    text += "generated=\(Date())\n"
    let providerJar = game.appendingPathComponent("mods/vrmc-provider.jar")
    let providerHash = shellFileSHA256(providerJar).map { String($0.prefix(32)) } ?? "missing"
    text += "providerJarSha256Prefix=\(providerHash) path=\(providerJar.path)\n"
    let provisioning = ShellProvisioning.lastReport ?? ShellProvisioning.run()
    for line in provisioning.lines { text += "provisioning: \(line)\n" }
    text += "note=fully local; contains logs and runtime settings only, no telemetry\n\n"
    for (name, url, cap) in entries {
        text += "===== \(name): \(url.lastPathComponent) =====\n"
        guard let data = try? Data(contentsOf: url) else {
            text += "(missing)\n\n"
            continue
        }
        let slice = data.count > cap ? data.suffix(cap) : data
        if data.count > cap { text += "(truncated to last \(cap) bytes of \(data.count))\n" }
        text += String(data: slice, encoding: .utf8) ?? "(not UTF-8)"
        if !text.hasSuffix("\n") { text += "\n" }
        text += "\n"
    }
    let stamp = DateFormatter()
    stamp.dateFormat = "yyyyMMdd-HHmmss"
    let out = docs.appendingPathComponent("vrmc-diagnostics-\(stamp.string(from: Date())).txt")
    do {
        try text.write(to: out, atomically: true, encoding: .utf8)
        shellLog("diagnostics export written: \(out.path) bytes=\(text.utf8.count)")
        return out
    } catch {
        shellLog("diagnostics export FAILED: \(error)")
        return nil
    }
}

private func shellFileSHA256(_ url: URL) -> String? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

private func shellVignetteURL() -> URL {
    return shellDocumentsURL().appendingPathComponent("vrmc-vignette.flag")
}

private func shellReadVignette() -> (enabled: Bool, strength: Double) {
    let url = shellVignetteURL()
    guard FileManager.default.fileExists(atPath: url.path) else { return (false, 0.5) }
    let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = Double(trimmed) ?? 0.5
    return (true, min(0.9, max(0.0, value)))
}

@discardableResult
private func shellWriteVignette(enabled: Bool, strength: Double) -> Bool {
    let url = shellVignetteURL()
    do {
        if enabled {
            try String(format: "%.2f", min(0.9, max(0.0, strength))).write(to: url, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
        shellLog("VRMC vignette saved: enabled=\(enabled) strength=\(strength) -> \(url.path)")
        return true
    } catch {
        shellLog("VRMC vignette save FAILED: \(error)")
        return false
    }
}

private func shellInputTuneURL() -> URL {
    return shellDocumentsURL()
        .appendingPathComponent("instances/default")
        .appendingPathComponent("vrmc-input-tune.properties")
}

private func shellReadInputTune() -> [String: String] {
    return shellReadProperties(shellInputTuneURL())
}

@discardableResult
private func shellWriteInputTune(_ values: [String: String]) -> Bool {
    let url = shellInputTuneURL()
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let header = "# VRMC hand-input tuning edited by the launcher (M4). Applied at the next game launch.\n"
        let body = values.keys.sorted().map { "\($0)=\(values[$0] ?? "")\n" }.joined()
        try (header + body).write(to: url, atomically: true, encoding: .utf8)
        shellLog("VRMC input tune saved: \(url.path) keys=\(values.keys.sorted().joined(separator: ","))")
        return true
    } catch {
        shellLog("VRMC input tune save FAILED: \(error)")
        return false
    }
}

@discardableResult
private func shellWriteRuntimeSettings(_ values: [String: String]) -> Bool {
    let url = shellRuntimeSettingsURL()
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let header = "# VRMC runtime settings edited by the launcher (M5). Applied at the next game launch.\n"
        let body = values.keys.sorted().map { "\($0)=\(values[$0] ?? "")\n" }.joined()
        try (header + body).write(to: url, atomically: true, encoding: .utf8)
        shellLog("VRMC settings saved: \(url.path) keys=\(values.keys.sorted().joined(separator: ","))")
        return true
    } catch {
        shellLog("VRMC settings save FAILED: \(error)")
        return false
    }
}

// M3c: the app data container cannot be cleaned with devicectl (copy/list only), so a leftover
// diagnostic flag (e.g. a forced test pattern) can poison every later run. Pushing
// Documents/vrmc-clear-diagnostics.flag makes the shell delete the list below at startup, before
// any autolaunch/immersive-on-launch flag could be consumed, and log one line per deletion.
private let diagnosticFlagsClearedAtStartup = [
    "vrmc-test-pattern.flag",
    "vrmc-reproj-off.flag",
    "vrmc-reproj-on.flag",
    "vrmc-reproj-debug.flag",
    "vrmc-no-sampling.flag",
    "vrmc-legacy-root-swap.flag",
    "vrmc-immersive-on-launch.flag",
    "vrmc-immersive-selftest.flag",
    "vrmc-open-on-launch.flag",
    "vrmc-clear-probe.flag",
    "vrmc-present-proof.flag",
    "vrmc-no-parking.flag",
    "vrmc-hide-windows.flag",
    "vrmc-hide-chrome-always.flag",
    "vrmc-legacy-single-drawable.flag",
    "vrmc-depth-near.flag",
    "vrmc-depth-zero.flag",
    "vrmc-present-wait.flag",
    "vrmc-input-sim.flag",
    "vrmc-no-anchor.flag",
    "vrmc-capture.flag",
    "vrmc-drawable-dump.flag",
    "vrmc-audible-canary.flag",
    "autolaunch.flag",
    "vrmc-clear-diagnostics.flag",
]

private func neutralizeDiagnosticFlagsIfRequested() {
    let fm = FileManager.default
    let docs = shellDocumentsURL()
    let trigger = docs.appendingPathComponent("vrmc-clear-diagnostics.flag")
    guard fm.fileExists(atPath: trigger.path) else { return }
    shellLog("clear-diagnostics: vrmc-clear-diagnostics.flag present; removing diagnostic flags before app start")
    for name in diagnosticFlagsClearedAtStartup {
        let url = docs.appendingPathComponent(name)
        guard fm.fileExists(atPath: url.path) else { continue }
        do {
            try fm.removeItem(at: url)
            shellLog("clear-diagnostics: deleted \(name)")
        } catch {
            shellLog("clear-diagnostics: FAILED to delete \(name): \(error.localizedDescription)")
        }
    }
    do {
        try fm.removeItem(at: trigger)
        shellLog("clear-diagnostics: deleted vrmc-clear-diagnostics.flag (self)")
    } catch {
        shellLog("clear-diagnostics: FAILED to delete vrmc-clear-diagnostics.flag: \(error.localizedDescription)")
    }
    shellLog("clear-diagnostics: done")
}

/// Diagnostic open flags captured BEFORE vrmc-clear-diagnostics deletes them, so pushing
/// clear-diagnostics + selftest/open-on-launch together still opens the immersive space this launch.
private enum ShellStartupFlags {
    static var selftest = false
    static var openOnLaunch = false
}

/// Rotate an append-only session log to <name>.prev.log at app start, so each launch has its own file.
/// The session logs otherwise accumulate across launches (EV-0091/EV-0092 contain 18+ launches in one
/// file), which makes whole-file log triage produce false PASS/REGRESSION verdicts.
private func rotateSessionLog(_ name: String, prev: String) {
    let docs = shellDocumentsURL()
    let fm = FileManager.default
    let cur = docs.appendingPathComponent(name)
    let old = docs.appendingPathComponent(prev)
    try? fm.removeItem(at: old)
    if fm.fileExists(atPath: cur.path) {
        try? fm.moveItem(at: cur, to: old)
    }
}

/// Launcher mod auto-provisioning (ModProvisioner.swift): bundled provider install/upgrade and
/// hash-verified Vivecraft import. The latest report feeds the launcher's Mods panel and diagnostics.
enum ShellProvisioning {
    private(set) static var lastReport: ModProvisionReport?
    private(set) static var vivecraftFileName = ModProvisioningManifest.builtIn.vivecraftFileName

    static func makeProvisioner() -> ModProvisioner {
        let docs = shellDocumentsURL()
        let bundleDir = Bundle.main.bundleURL.appendingPathComponent("vrmc")
        return ModProvisioner(
            documentsDir: docs,
            modsDir: docs.appendingPathComponent("instances/default/mods"),
            bundledProvider: bundleDir.appendingPathComponent(ModProvisioner.providerFileName),
            manifest: ModProvisioningManifest.load(from: bundleDir.appendingPathComponent("provisioning.json")),
            log: shellLog)
    }

    @discardableResult
    static func run() -> ModProvisionReport {
        let provisioner = makeProvisioner()
        let report = provisioner.run()
        lastReport = report
        vivecraftFileName = provisioner.manifest.vivecraftFileName
        return report
    }
}

@_cdecl("vrmc_shell_start")
public func vrmcShellStart() -> Int32 {
    rotateSessionLog("vrmc-shell.log", prev: "vrmc-shell.prev.log")
    ShellStartupFlags.selftest = shellDocumentFlag("vrmc-immersive-selftest.flag")
    ShellStartupFlags.openOnLaunch = shellDocumentFlag("vrmc-open-on-launch.flag")
    shellLog("vrmc_shell_start invoked")
    // Must run before VRMCShellApp.main() so no autolaunch/on-launch flag survives this process.
    neutralizeDiagnosticFlagsIfRequested()
    // Before the launcher UI exists, so the first game launch already sees a provisioned mods/ dir.
    ShellProvisioning.run()
    VRMCShellApp.main()
    return 0
}

/// M8: maximum layer render quality [0,1] (visionOS 26+). This is the upper bound for the drawable's
/// resolution and for the dynamic-quality range the compositor's runtime controller may use inside.
/// 1.0 = the highest render quality the device supports (native per-eye panel resolution, i.e. the
/// "4K in both eyes" target); Documents/vrmc-max-render-quality.txt can pin a lower value for A/B
/// without rebuilding. An absent/unparsable file falls back to 1.0, never fails the immersive open.
private func shellMaxRenderQuality() -> LayerRenderer.RenderQuality {
    let fallback = LayerRenderer.RenderQuality(rawValue: 1.0)
    let path = shellDocumentsURL().appendingPathComponent("vrmc-max-render-quality.txt")
    guard let raw = try? String(contentsOf: path, encoding: .utf8) else { return fallback }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Float(trimmed), value >= 0.05, value <= 1.0 else {
        shellLog("max render quality: ignoring unparsable override '\(trimmed)' (using 1.0)")
        return fallback
    }
    shellLog("max render quality: Documents/vrmc-max-render-quality.txt = \(value)")
    return LayerRenderer.RenderQuality(rawValue: value)
}

struct ShellLayerConfiguration: CompositorLayerConfiguration {
    func makeConfiguration(capabilities: LayerRenderer.Capabilities,
                           configuration: inout LayerRenderer.Configuration) {
        // M8: foveated rendering + dynamic render quality.
        //  - Foveation is requested whenever the layer supports it (Apple's "Drawing fully immersive
        //    content using Metal" sample does exactly this): drawables then expose rasterization rate
        //    maps with a high-density centre and a smaller physical texture, which is how the system
        //    gives the fovea native per-eye resolution for less memory/compositor cost.
        //  - The layout is chosen from the layouts the layer reports for the requested foveation mode.
        //    The accepted device path is .dedicated; if foveation only allows another layout we use
        //    that instead of failing the immersive open.
        //  - maxRenderQuality is the ceiling for the drawable resolution; the compositor starts its
        //    runtime quality there (or lower from Documents/vrmc-render-quality.txt) and publishes the
        //    resulting logical per-eye size to the provider through the bridge.
        let foveationSupported = capabilities.supportsFoveation
        let foveationDisabledByFlag = shellDocumentFlag("vrmc-foveation-off.flag")
        let wantFoveation = foveationSupported && !foveationDisabledByFlag
        let supportedLayouts = capabilities.supportedLayouts(
            options: wantFoveation ? [.foveationEnabled] : [])
        var chosenLayout: LayerRenderer.Layout = .dedicated
        if supportedLayouts.contains(.dedicated) {
            chosenLayout = .dedicated
        } else if supportedLayouts.contains(.layered) {
            chosenLayout = .layered
        } else if let first = supportedLayouts.first {
            chosenLayout = first
        }
        configuration.layout = chosenLayout
        configuration.colorFormat = .rgba16Float
        var maxQualityText = "system-default"
        if #available(visionOS 26.0, *) {
            let defaultQuality = capabilities.defaultRenderQuality.rawValue
            // Only touch maxRenderQuality when the layer reports a usable default quality. Some
            // runtimes (observed: the visionOS 27.0 simulator) report NaN, and setting an explicit
            // quality there makes CompositorLayer creation fail (CPImmersiveScene.layer abort in
            // didMoveToWindow) - the immersive space then never opens.
            let qualitySupported = defaultQuality.isFinite && defaultQuality > 0.0 && defaultQuality <= 1.0
            if qualitySupported {
                let maxQuality = shellMaxRenderQuality()
                configuration.maxRenderQuality = maxQuality
                maxQualityText = String(format: "%.2f", maxQuality.rawValue)
            } else {
                shellLog("layer config: render-quality control UNSUPPORTED (defaultRenderQuality="
                    + "\(defaultQuality)); leaving maxRenderQuality at the system default")
            }
            shellLog("layer config: supportsFoveation=\(foveationSupported) defaultRenderQuality="
                + "\(defaultQuality) qualitySupported=\(qualitySupported) maxRenderQuality="
                + "\(maxQualityText) supportedLayouts=\(supportedLayouts.map { "\($0)" })")
        } else {
            shellLog("layer config: dynamic render quality unavailable (pre-visionOS 26)")
        }
        configuration.isFoveationEnabled = wantFoveation
        shellLog("layer config: layout=\(chosenLayout) foveation=\(wantFoveation) "
            + "(supported=\(foveationSupported) disabledByFlag=\(foveationDisabledByFlag)) "
            + "maxRenderQuality=\(maxQualityText)")
        // M4-W2: tracking-area textures are OPT-IN via Documents/vrmc-gaze.flag. Leaving the layer
        // configuration untouched unless gaze is requested keeps the device/simulator presentation path
        // exactly like the accepted build (the simulator regressed when this was unconditional).
        let gazeRequested = shellDocumentFlag("vrmc-gaze.flag") && !shellDocumentFlag("vrmc-no-tracking-areas.flag")
        if #available(visionOS 26.0, *), gazeRequested {
            let supported = capabilities.supportedTrackingAreasFormats
            if let format = supported.first(where: { $0 == .r32Uint || $0 == .r16Uint }) {
                configuration.trackingAreasFormat = format
                configuration.trackingAreasUsage = [.renderTarget]
                shellLog("tracking areas: format=\(format.rawValue) supported=\(supported.map(\.rawValue))")
            } else {
                shellLog("tracking areas: none of the integer formats are supported (\(supported.map(\.rawValue))); gaze disabled")
            }
        }
    }
}

struct LauncherHostView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        if let cls = NSClassFromString("LauncherSplitViewController") as? UIViewController.Type {
            return cls.init()
        }
        let fallback = UIViewController()
        fallback.view.backgroundColor = .systemBackground
        return fallback
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

/// App-level owner of the immersive lifecycle.
///
/// Amethyst's game launch must not replace the WindowGroup's root view controller (the M3b patch
/// presents the game surface modally over it instead): replacing the root destroys the SwiftUI view,
/// which is what dropped the scene's persistentSystemOverlays(.hidden) chrome preference and the
/// lifecycle subscriptions in EV-0085/EV-0086. The coordinator stays app-level anyway.
///
/// M3c presentation hardening (EV-0090/EV-0091 black immersive):
///  - Windows are NEVER hidden with isHidden anymore (that is followed by UIScene.willDeactivate in
///    the device logs). Parking is alpha-only + non-interactive, and only happens AFTER the
///    compositor posts VRMCCompositorRunning (its first presented frame). vrmc-hide-windows.flag
///    restores the old hide behaviour for A/B; vrmc-no-parking.flag disables parking entirely.
///  - When no presented frame arrives, the shell logs NO-FRAME heartbeats and LEAVES THE IMMERSIVE
///    SPACE OPEN (no dismiss, no auto-retry) so the device log stays collectable.
///  - vrmc-immersive-selftest.flag opens the immersive space without the game (no JIT needed): the
///    shell starts, waits for the scene to be foreground-active, opens the space, and the compositor
///    draws its test pattern + present-proof overlay + drawable raw dumps.
@MainActor
@Observable
final class ShellCoordinator {
    static let shared = ShellCoordinator()

    /// Drives the WindowGroup chrome visibility (scene-level, survives game presentation).
    private(set) var immersiveOpen = false
    /// True once the compositor has presented at least one frame for the current session.
    private(set) var presenting = false

    @ObservationIgnored private var gameStarted = false
    /// Set when the immersive session was ended by backgrounding/resigning; cleared once reopened.
    @ObservationIgnored private var reopenOnActive = false
    /// True once an immersive session has been opened in this process (any reason: game, manual, selftest,
    /// open-on-launch). Used so background/foreground re-entry also works for the manual/diagnostic paths.
    @ObservationIgnored private var wantsImmersive = false
    @ObservationIgnored private var opening = false
    /// Incremented on every compositor-ended/background transition; guarded Tasks abort when it moves.
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var appActive = false
    @ObservationIgnored private var windowSceneActive = false
    /// Generation of the most recent successful immersive open (0 = never opened).
    @ObservationIgnored private var lastOpenGeneration: Int32 = 0
    @ObservationIgnored private var lastOpenAt: Date = .distantPast
    @ObservationIgnored private var autoRetries = 0
    /// True while a previous immersive space still needs an explicit dismiss before a reopen.
    @ObservationIgnored private var needsDismiss = false
    @ObservationIgnored private var openAction: OpenImmersiveSpaceAction?
    @ObservationIgnored private var thermalTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeatStaleLogged = false
    @ObservationIgnored private var dismissAction: DismissImmersiveSpaceAction?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// NO-FRAME watchdog for the current open; cancelled once a presented frame arrives.
    @ObservationIgnored private var noFrameTask: Task<Void, Never>?
    /// Periodic window parking while the immersive session is live: Amethyst/game code can re-show or
    /// re-alpha a window after the first park (observed: the game window stayed visible in a live game
    /// run even though the first park set alpha=0), so re-apply until the session ends.
    @ObservationIgnored private var parkingTask: Task<Void, Never>?
    /// Periodic scene/immersion state logging while immersive is live.
    @ObservationIgnored private var sceneStateTask: Task<Void, Never>?
    /// willResignActive grace timer: a transient resign must not stop the compositor (sim-lifecycle).
    @ObservationIgnored private var resignGraceTask: Task<Void, Never>?
    /// True while alpha-only parking has been applied to the windows.
    @ObservationIgnored private var windowsParked = false

    /// Keep the window chrome hidden for the whole launch (diagnostic A/B for EV-0086 issue 1).
    private(set) var hideChromeAlways = false
    private(set) var chromeMode = "automatic"
    /// Self-test mode: open the immersive space without the game (see class docs).
    private(set) var selftestMode = false
    /// Open the immersive space shortly after launch WITHOUT forcing the test pattern (diagnostic; the
    /// simulator provider-sampling harness uses it to exercise the sampled path with fake provider eyes).
    private(set) var openOnLaunch = false
    /// Disable window parking entirely (diagnostic).
    private(set) var noParking = false
    /// Restore the old isHidden=true parking for A/B (default: alpha-only, never hide).
    private(set) var hideWindowsOptIn = false
    /// M6 crash guard: previous session ended without a clean destroy-complete; after two consecutive
    /// unclean sessions the automatic immersive open is suppressed (manual Enter VR still works).
    private(set) var safeMode = false
    private(set) var crashGuardMessage = ""

    /// User-facing status for the window overlay (manual "Enter VR" control, Option 2 staging).
    private(set) var statusMessage = "Preparing VR"
    /// Last failure to open the immersive space, shown in the window so errors stay actionable.
    private(set) var lastOpenError: String?

    /// Manual "Enter VR" (staged immersive entry): open the immersive space on demand, independent of
    /// the game/JIT path, so the CompositorServices renderer can be validated on its own. The automatic
    /// path (after the game starts, i.e. after JIT readiness) stays enabled; this button is also the
    /// recovery path when the automatic open fails.
    func enterVRManually() {
        shellLog("MANUAL: Enter VR pressed (immersive=\(immersiveOpen) opening=\(opening) appActive=\(appActive) windowActive=\(windowSceneActive) presenting=\(presenting))")
        guard openAction != nil else {
            lastOpenError = "Immersive space is not bound yet; try again in a moment."
            statusMessage = "VR unavailable"
            shellLog("MANUAL: openImmersiveSpace action not bound yet")
            return
        }
        lastOpenError = nil
        statusMessage = "Opening immersive space…"
        openVR(reason: "manual")
    }

    private init() {
        hideChromeAlways = shellDocumentFlag("vrmc-hide-chrome-always.flag")
        chromeMode = hideChromeAlways ? "hidden-always" : "hidden-when-immersive"
        selftestMode = ShellStartupFlags.selftest
        openOnLaunch = ShellStartupFlags.openOnLaunch
        noParking = shellDocumentFlag("vrmc-no-parking.flag")
        hideWindowsOptIn = shellDocumentFlag("vrmc-hide-windows.flag")
        observe(Notification.Name("VRMCGameStarted")) { $0.gameDidStart() }
        observe(Notification.Name("VRMCGameStopped")) { coordinator, note in
            coordinator.gameDidStop(reason: note.userInfo?["reason"] as? String ?? "unknown")
        }
        observe(Notification.Name("VRMCImmersiveEnded")) { coordinator, note in
            coordinator.compositorDidEnd(generation: note.userInfo?["generation"] as? Int32)
        }
        observe(Notification.Name("VRMCCompositorRunning")) { coordinator, note in
            coordinator.compositorDidStartPresenting(generation: note.userInfo?["generation"] as? Int32)
        }
        observe(UIApplication.willResignActiveNotification) { $0.willResignActive() }
        observe(UIApplication.didEnterBackgroundNotification) { $0.didEnterBackground() }
        observe(UIApplication.didBecomeActiveNotification) { $0.appDidBecomeActive() }
        observe(UIApplication.didFinishLaunchingNotification) { $0.refreshActivityStates("didFinishLaunching") }
        observe(UIScene.didActivateNotification) { $0.refreshActivityStates("UIScene.didActivate") }
        observe(UIScene.willDeactivateNotification) { $0.refreshActivityStates("UIScene.willDeactivate") }
        observe(ProcessInfo.thermalStateDidChangeNotification) { $0.logThermal("thermal-state-changed") }
        refreshActivityStates("init")
        shellLog("coordinator ready chromeMode=\(chromeMode) selftest=\(selftestMode) noParking=\(noParking) hideWindowsOptIn=\(hideWindowsOptIn)")
        startThermalMonitor()
        startHeartbeatWatchdog()
        evaluateCrashGuard()
        if selftestMode {
            scheduleSelfTestOpen()
        }
        if openOnLaunch {
            scheduleOpenOnLaunch()
        }
    }

    private func observe(_ name: Notification.Name, _ handler: @escaping (ShellCoordinator) -> Void) {
        observe(name) { coordinator, _ in handler(coordinator) }
    }

    private func observe(_ name: Notification.Name,
                         _ handler: @escaping (ShellCoordinator, Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
            MainActor.assumeIsolated { handler(ShellCoordinator.shared, note) }
        })
    }

    /// Called from the App body so the coordinator always holds the current environment actions.
    func bind(open: OpenImmersiveSpaceAction, dismiss: DismissImmersiveSpaceAction) {
        openAction = open
        dismissAction = dismiss
    }

    // MARK: - Activity state

    private func windowStateDescription() -> String {
        var parts: [String] = []
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes
            where scene.session.role == .windowApplication {
            var desc = "scene(\(scene.windows.count))"
            for (index, window) in scene.windows.enumerated() {
                desc += String(format: " w%d[hidden=%@ alpha=%.2f level=%.1f]",
                               index, window.isHidden ? "true" : "false",
                               window.alpha, window.windowLevel.rawValue)
            }
            parts.append(desc)
        }
        return parts.isEmpty ? "windows=no-window-scenes" : "windows=" + parts.joined(separator: " ")
    }

    /// Re-reads app and window-scene activation from UIKit (the notifications alone are not reliable on
    /// visionOS while an immersive space owns focus) and logs the full window/scene picture.
    private func refreshActivityStates(_ reason: String) {
        appActive = UIApplication.shared.applicationState == .active
        windowSceneActive = false
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes
            where scene.session.role == .windowApplication {
            if scene.activationState == .foregroundActive { windowSceneActive = true }
        }
        shellLog("activity \(reason) appActive=\(appActive) windowSceneActive=\(windowSceneActive) \(windowStateDescription()) scenes=[\(sceneStateDescription())]")
    }

    /// Every connected scene with its session role and activation state. This is the objective proof of
    /// whether the immersive-space scene (CPSceneSessionRoleImmersiveSpaceApplication) is actually active
    /// and therefore whether the system should be displaying our CompositorServices layer.
    private func sceneStateDescription() -> String {
        var parts: [String] = []
        for scene in UIApplication.shared.connectedScenes {
            let role = scene.session.role.rawValue
            let state: String
            switch scene.activationState {
            case .foregroundActive: state = "fgActive"
            case .foregroundInactive: state = "fgInactive"
            case .background: state = "background"
            case .unattached: state = "unattached"
            @unknown default: state = "unknown"
            }
            parts.append("\(role):\(state)")
        }
        return parts.joined(separator: ",")
    }

    /// Periodic scene/immersion state while the immersive session is live (objective display evidence).
    private func startSceneStateLoop() {
        sceneStateTask?.cancel()
        sceneStateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                if Task.isCancelled { return }
                shellLog("STATE immersive=\(self.immersiveOpen) presenting=\(self.presenting) appActive=\(self.appActive) appState=\(UIApplication.shared.applicationState.rawValue) scenes=[\(self.sceneStateDescription())] \(self.windowStateDescription())")
            }
        }
    }

    // MARK: - Game start / self-test

    private func gameDidStart() {
        shellLog("VRMCGameStarted received")
        gameStarted = true
        Task {
            // Let the game create its renderer/provider first (provider init + first frames).
            try? await Task.sleep(for: .seconds(15))
            openVR(reason: "auto")
        }
    }

    /// Self-test: every second for up to 15 s, try to open the immersive space even though
    /// VRMCGameStarted never fired. Requires only that the SwiftUI app is foreground-active and the
    /// environment action is bound, so a plain devicectl process launch works (no JIT).
    private func scheduleSelfTestOpen() {
        shellLog("SELFTEST: vrmc-immersive-selftest.flag present; immersive space will open without the game")
        Task { [weak self] in
            guard let self else { return }
            // Let the WindowGroup/scene finish activating before the first attempt (~3 s after launch).
            try? await Task.sleep(for: .seconds(3))
            for attempt in 1...15 {
                try? await Task.sleep(for: .seconds(1))
                if self.immersiveOpen || self.opening { return }
                guard self.openAction != nil else {
                    if attempt % 5 == 0 { self.shellLogSafe("SELFTEST: openImmersiveSpace action not bound yet (attempt \(attempt))") }
                    continue
                }
                guard self.appActive && self.windowSceneActive else {
                    if attempt % 5 == 0 {
                        self.shellLogSafe("SELFTEST: waiting for foreground-active scene (attempt \(attempt) appActive=\(self.appActive) windowActive=\(self.windowSceneActive))")
                    }
                    continue
                }
                self.shellLogSafe("SELFTEST: opening immersive space (attempt \(attempt))")
                self.openVR(reason: "selftest")
                try? await Task.sleep(for: .seconds(2))
                if self.immersiveOpen || self.opening { return }
            }
            self.shellLogSafe("SELFTEST: gave up opening the immersive space after 15 s")
        }
    }

    /// Open the immersive space shortly after launch (diagnostic). Unlike the self-test this does NOT
    /// force the procedural test pattern: with a provider publishing eye textures the compositor runs
    /// the sampled flat path, which is what the simulator provider-sampling harness needs.
    private func scheduleOpenOnLaunch() {
        shellLog("OPEN-ON-LAUNCH: vrmc-open-on-launch.flag present; will open the immersive space without forcing the test pattern")
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(3))
            for attempt in 1...15 {
                if self.immersiveOpen || self.opening { return }
                guard self.openAction != nil, self.appActive, self.windowSceneActive else {
                    if attempt % 5 == 0 {
                        self.shellLogSafe("OPEN-ON-LAUNCH: waiting (attempt \(attempt) action=\(self.openAction != nil) appActive=\(self.appActive) windowActive=\(self.windowSceneActive))")
                    }
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                self.shellLogSafe("OPEN-ON-LAUNCH: opening immersive (attempt \(attempt))")
                self.openVR(reason: "onlaunch")
                try? await Task.sleep(for: .seconds(2))
                if self.immersiveOpen || self.opening { return }
                try? await Task.sleep(for: .seconds(1))
            }
            self.shellLogSafe("OPEN-ON-LAUNCH: gave up after 15 attempts")
        }
    }

    // MARK: - M6 compositor heartbeat watchdog

    /// Detect a stalled compositor even without a crash: the compositor rewrites Documents/vrmc-heartbeat.txt
    /// at most ~1 Hz while presenting. A stale heartbeat while immersive and presenting is logged once per
    /// episode and surfaced in the launcher status; it does not silently kill the session.
    private func startHeartbeatWatchdog() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                guard self.immersiveOpen && self.presenting else {
                    self.heartbeatStaleLogged = false
                    continue
                }
                let url = shellDocumentsURL().appendingPathComponent("vrmc-heartbeat.txt")
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let modified = attrs[.modificationDate] as? Date else { continue }
                let age = Date().timeIntervalSince(modified)
                if age > 20.0 {
                    if !self.heartbeatStaleLogged {
                        self.heartbeatStaleLogged = true
                        shellLog("WATCHDOG: compositor heartbeat stale \(Int(age))s while immersive+presenting; presentation may be stalled")
                        self.statusMessage = "VR presentation stalled (heartbeat \(Int(age))s old)"
                    }
                } else if self.heartbeatStaleLogged {
                    self.heartbeatStaleLogged = false
                    shellLog("WATCHDOG: compositor heartbeat recovered (age \(Int(age))s)")
                    self.statusMessage = "VR presenting"
                }
            }
        }
    }

    // MARK: - M6 crash guard

    private func crashCountURL() -> URL {
        shellDocumentsURL().appendingPathComponent("vrmc-crash-count.txt")
    }

    /// M6 crash guard, run once at launch. The provider appends `event=…` lines to
    /// instances/default/vrmc-shutdown.log and writes `destroy-complete` only on a clean teardown, so a
    /// last line without it means the previous JVM died mid-session. Consecutive unclean sessions are
    /// counted in Documents/vrmc-crash-count.txt; at two, safe mode suppresses the automatic immersive
    /// open (and writes vrmc-safe-mode.flag) until a clean session or "Clear crash safe mode". A
    /// missing journal (first run) leaves the count untouched.
    private func evaluateCrashGuard() {
        let docs = shellDocumentsURL()
        let gameDir = docs.appendingPathComponent("instances/default")
        let shutdown = gameDir.appendingPathComponent("vrmc-shutdown.log")
        let countURL = crashCountURL()
        var count = Int((try? String(contentsOf: countURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        var unclean = false
        if let text = try? String(contentsOf: shutdown, encoding: .utf8) {
            let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if let last = lines.last, last.contains("event=") {
                if last.contains("destroy-complete") {
                    count = 0
                } else {
                    unclean = true
                    count += 1
                }
            }
        }
        try? String(count).write(to: countURL, atomically: true, encoding: .utf8)
        if unclean {
            crashGuardMessage = "Previous VR session ended unexpectedly (no clean shutdown)."
            lastOpenError = count >= 2
                ? "Two recent sessions ended unexpectedly; automatic VR is disabled. Use Enter VR after exporting diagnostics."
                : "Previous session ended unexpectedly; diagnostics are available from Export diagnostics."
            shellLog("CRASH-GUARD: \(crashGuardMessage) count=\(count)")
        } else {
            crashGuardMessage = ""
        }
        let flag = docs.appendingPathComponent("vrmc-safe-mode.flag")
        if count >= 2 {
            safeMode = true
            try? Data("safe".utf8).write(to: flag)
            shellLog("CRASH-GUARD: safe mode enabled (count=\(count)); automatic VR open suppressed")
        } else {
            safeMode = false
            try? FileManager.default.removeItem(at: flag)
        }
    }

    /// Clear the crash guard from the launcher after the user has exported diagnostics.
    func clearCrashGuard() {
        safeMode = false
        crashGuardMessage = ""
        lastOpenError = nil
        try? FileManager.default.removeItem(at: crashCountURL())
        try? FileManager.default.removeItem(at: shellDocumentsURL().appendingPathComponent("vrmc-safe-mode.flag"))
        shellLog("CRASH-GUARD: cleared by user (manual)")
    }

    // MARK: - M5 thermal/performance diagnostics

    /// Periodic thermal/low-power telemetry (no telemetry leaves the device). The 30 s cadence is
    /// independent of the compositor: a changed thermal state is also logged immediately.
    private func startThermalMonitor() {
        thermalTask?.cancel()
        thermalTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.logThermal("periodic")
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func logThermal(_ reason: String) {
        let info = ProcessInfo.processInfo
        let state: String
        switch info.thermalState {
        case .nominal: state = "nominal"
        case .fair: state = "fair"
        case .serious: state = "serious"
        case .critical: state = "critical"
        @unknown default: state = "unknown"
        }
        let line = "THERMAL reason=\(reason) state=\(state) lowPower=\(info.isLowPowerModeEnabled) "
            + "uptime=\(Int(info.systemUptime))s physicalMemoryMB=\(info.physicalMemory / 1_048_576) "
            + "immersive=\(immersiveOpen) presenting=\(presenting) appActive=\(appActive) "
            + "appState=\(UIApplication.shared.applicationState.rawValue)"
        shellLog(line)
        let docs = shellDocumentsURL()
        let gameDir = docs.appendingPathComponent("instances/default")
        try? FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
        let stateFile = "state=\(state)\nlowPower=\(info.isLowPowerModeEnabled)\ntime=\(Date())\n"
        try? stateFile.write(to: gameDir.appendingPathComponent("vrmc-thermal-state.txt"),
                             atomically: true, encoding: .utf8)
        let url = docs.appendingPathComponent("vrmc-thermal.log")
        let entry = "\(Date()) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            try? handle.close()
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }

    // MARK: - Compositor notifications

    /// The compositor's first presented frame of this session. Parking the 2D windows before this
    /// (or hiding them at all) is what the device logs correlate with scene deactivation.
    private func compositorDidStartPresenting(generation: Int32?) {
        let generationText = generation.map(String.init) ?? "nil"
        shellLog("VRMCCompositorRunning generation=\(generationText) immersive=\(immersiveOpen) selftest=\(selftestMode) \(windowStateDescription())")
        presenting = true
        statusMessage = "VR presenting"
        lastOpenError = nil
        // The auto-retry after a layer that dies right after opening compares generations. The open
        // request happens before the compositor thread exists (generation 0), so the real generation is
        // only known here, at the first presented frame.
        lastOpenGeneration = VRMCCompositor_CurrentGeneration()
        // Audible canary: the operator can confirm the first presented frame even if they are not
        // looking at the centre of the field of view (diagnostic only; system sound, no asset).
        if shellDocumentFlag("vrmc-audible-canary.flag") { AudioServicesPlaySystemSound(1057) }
        noFrameTask?.cancel()
        noFrameTask = nil
        // Objective scene/immersion state logging must run in EVERY presenting mode (also selftest and
        // no-parking): this is the evidence that the immersive scene is foreground-active while the
        // compositor presents, and it must survive the early returns below.
        startSceneStateLoop()
        guard immersiveOpen else {
            shellLog("VRMCCompositorRunning ignored for parking: immersive space not open")
            return
        }
        if selftestMode {
            shellLog("SELFTEST: compositor presenting; windows left visible for the self-test (no parking)")
            return
        }
        if noParking {
            shellLog("parking disabled by vrmc-no-parking.flag; windows left untouched")
            return
        }
        setGameWindowsVisible(false, log: "window parked after first presented frame")
        startParkingLoop()
    }

    /// Game provider teardown (or the compositor's eyes-lost fallback): stop presenting the immersive
    /// space and return to the launcher instead of leaving a stale test-pattern scene and beeping.
    private func gameDidStop(reason: String) {
        shellLog("VRMCGameStopped received reason=\(reason) gameStarted=\(gameStarted) immersive=\(immersiveOpen) presenting=\(presenting) \(windowStateDescription())")
        gameStarted = false
        wantsImmersive = false
        reopenOnActive = false
        autoRetries = 0
        noFrameTask?.cancel(); noFrameTask = nil
        parkingTask?.cancel(); parkingTask = nil
        sceneStateTask?.cancel(); sceneStateTask = nil
        VRMCCompositor_RequestStop()
        if !immersiveOpen && !presenting {
            setGameWindowsVisible(true, log: "window restored after game stop (not immersive)")
            return
        }
        epoch += 1
        let myEpoch = epoch
        needsDismiss = true
        immersiveOpen = false
        presenting = false
        statusMessage = "Game ended — window restored"
        setGameWindowsVisible(true, log: "window restored after game stop")
        Task { [weak self] in
            guard let self else { return }
            await self.dismissIfCurrent(myEpoch: myEpoch)
            self.shellLogSafe("immersive space dismissed after game stop epoch=\(myEpoch)")
        }
    }

    private func compositorDidEnd(generation: Int32?) {
        let current = VRMCCompositor_CurrentGeneration()
        shellLog("VRMCImmersiveEnded generation=\(generation.map(String.init) ?? "nil") current=\(current) presenting=\(presenting) \(windowStateDescription())")
        // A session that ended after a newer one was opened must not close the newer one.
        if let generation, generation != current {
            shellLog("ignoring stale generation=\(generation) current=\(current)")
            return
        }
        epoch += 1
        let myEpoch = epoch
        let hadPresentedFrame = presenting
        presenting = false
        statusMessage = "VR ended — window restored"
        if shellDocumentFlag("vrmc-audible-canary.flag") { AudioServicesPlaySystemSound(1073) }
        noFrameTask?.cancel()
        noFrameTask = nil
        parkingTask?.cancel()
        parkingTask = nil
        sceneStateTask?.cancel()
        sceneStateTask = nil
        immersiveOpen = false
        needsDismiss = true
        setGameWindowsVisible(true, log: "window restored")

        // If the layer died while the app is active and this was our most recent open, a guarded
        // reopen recovers instead of leaving the operator stuck in the 2D window (EV-0086 gen-2 case
        // where the layer invalidated within seconds of opening with no rendered frames).
        let shouldAutoRetry = appActive && (gameStarted || selftestMode || openOnLaunch || wantsImmersive) && !reopenOnActive &&
            generation != nil && generation == lastOpenGeneration &&
            Date().timeIntervalSince(lastOpenAt) < 20 && autoRetries < 2
        if shouldAutoRetry {
            autoRetries += 1
            shellLog("auto-retry \(autoRetries)/2 generation=\(generation.map(String.init) ?? "nil") hadPresentedFrame=\(hadPresentedFrame) (layer ended right after opening)")
        } else if !hadPresentedFrame {
            shellLog("layer ended before any presented frame; not auto-retrying (presentation never confirmed)")
        }

        Task { [weak self] in
            guard let self else { return }
            // The compositor may have exited on a stop request while SwiftUI still has the space open;
            // dismiss so a later openImmersiveSpace is not rejected.
            await self.dismissIfCurrent(myEpoch: myEpoch)
            self.shellLogSafe("immersive space dismissed epoch=\(myEpoch)")
            if self.epoch != myEpoch { return }
            if shouldAutoRetry {
                try? await Task.sleep(for: .seconds(2))
                if self.epoch != myEpoch { return }
                if (self.gameStarted || self.selftestMode) && !self.immersiveOpen && self.appActive {
                    self.openVR(reason: "auto-retry")
                }
            } else if self.reopenOnActive && self.appActive && !self.immersiveOpen {
                self.openVR(reason: "ended-while-active")
            }
        }
    }

    /// Dismisses the SwiftUI immersive space only if no newer open/close happened since `myEpoch` was
    /// captured, so a late dismiss from an old session can never close a freshly reopened one.
    private func dismissIfCurrent(myEpoch: Int) async {
        guard epoch == myEpoch, needsDismiss else { return }
        if let dismissAction {
            await dismissAction()
        }
        if epoch == myEpoch { needsDismiss = false }
    }

    /// Real backgrounding: remember whether VR should come back, invalidate in-flight tasks (epoch) and
    /// ask the compositor to stop. The immersive space itself is dismissed when the compositor reports
    /// it has ended (compositorDidEnd).
    private func stopForBackground(_ reason: String) {
        resignGraceTask?.cancel()
        resignGraceTask = nil
        shellLog("\(reason) gameStarted=\(gameStarted) immersive=\(immersiveOpen) presenting=\(presenting) \(windowStateDescription())")
        appActive = false
        windowSceneActive = false
        // Reopen on return whenever VR was active in this process. The immersive session may already
        // have been invalidated by the system just before didEnterBackground (observed: layer ended a
        // beat before willResignActive), so immersiveOpen can be false here while the user still expects
        // VR to be restored. wantsImmersive is set on the first successful open (game/manual/selftest).
        if (gameStarted || wantsImmersive) {
            reopenOnActive = true
        }
        epoch += 1
        noFrameTask?.cancel()
        noFrameTask = nil
        VRMCCompositor_RequestStop()
    }

    /// A transient scene deactivation (the device log shows willResignActive without a real
    /// background in several sessions) must not end the immersive session. Wait 1.8 s: if
    /// didBecomeActive arrives first the grace is cancelled; only didEnterBackground or the timer
    /// expiry actually requests a compositor stop.
    private func willResignActive() {
        shellLog("willResignActive (grace 1.8 s before stopping the compositor) gameStarted=\(gameStarted) immersive=\(immersiveOpen) presenting=\(presenting) \(windowStateDescription())")
        appActive = false
        windowSceneActive = false
        resignGraceTask?.cancel()
        let startEpoch = epoch
        resignGraceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(1800))
            if Task.isCancelled { return }
            if self.epoch != startEpoch { return }
            if UIApplication.shared.applicationState == .active {
                self.shellLogSafe("willResignActive grace: app is active again; not stopping the compositor")
                return
            }
            self.shellLogSafe("willResignActive grace expired; stopping the compositor")
            self.stopForBackground("willResignActive-grace-expired")
        }
    }

    private func didEnterBackground() {
        resignGraceTask?.cancel()
        resignGraceTask = nil
        stopForBackground("didEnterBackground")
    }

    private func appDidBecomeActive() {
        if resignGraceTask != nil {
            resignGraceTask?.cancel()
            resignGraceTask = nil
            shellLog("willResignActive cancelled by didBecomeActive (compositor not stopped, grace 1.8 s)")
        }
        appActive = true
        refreshActivityStates("didBecomeActive")
        shellLog("didBecomeActive gameStarted=\(gameStarted) immersive=\(immersiveOpen) reopen=\(reopenOnActive) windowActive=\(windowSceneActive)")
        if selftestMode && !immersiveOpen && !opening {
            openVR(reason: "selftest")
            return
        }
        if reopenOnActive && !immersiveOpen && windowSceneActive {
            openVR(reason: "foreground")
        }
    }

    // MARK: - Open / close

    private func openVR(reason: String) {
        guard !immersiveOpen, !opening else { return }
        if safeMode && (reason == "auto" || reason == "onlaunch") {
            shellLog("SAFE MODE: automatic VR open suppressed (previous sessions did not shut down cleanly); use Enter VR")
            statusMessage = "Crash safe mode: automatic VR disabled — use Enter VR"
            return
        }
        guard let openAction else {
            shellLog("\(reason): openImmersiveSpace action not bound yet")
            return
        }
        let startEpoch = epoch
        let startReopen = reopenOnActive
        opening = true
        Task { [weak self] in
            guard let self else { return }
            defer { if self.epoch == startEpoch { self.opening = false } }
            // The scene must be foreground-active; opening during activation can be rejected or can
            // produce a layer that immediately invalidates (EV-0086 generation 2).
            for _ in 0..<10 where !(self.appActive && self.windowSceneActive) {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard self.appActive && self.windowSceneActive else {
                self.shellLogSafe("\(reason): scene not foreground-active; deferring open to next activation (will retry)")
                // Retry on the next app activation: appDidBecomeActive re-opens when reopenOnActive is set,
                // so an auto open that loses the race with scene activation is not silently dropped.
                self.reopenOnActive = true
                self.statusMessage = "VR open deferred (will retry)"
                if reason == "manual" {
                    self.lastOpenError = "The VRMC window must be in front. Look at the app and tap Enter VR again."
                }
                return
            }
            // Give the scene time to finish activating/transitioning; auto/selftest run immediately.
            if reason != "auto" && reason != "selftest" {
                try? await Task.sleep(for: .seconds(2))
            }
            if self.epoch != startEpoch { self.shellLogSafe("\(reason): aborted before open (epoch changed)"); return }
            // A previous space may still be registered with SwiftUI; dismiss it first and settle.
            if self.needsDismiss {
                if let dismissAction = self.dismissAction { await dismissAction() }
                if self.epoch != startEpoch { self.shellLogSafe("\(reason): aborted after dismiss (epoch changed)"); return }
                self.needsDismiss = false
                try? await Task.sleep(for: .milliseconds(500))
            }
            for attempt in 1...4 {
                if self.epoch != startEpoch { self.shellLogSafe("\(reason): aborted attempt \(attempt) (epoch changed)"); return }
                guard self.appActive, self.windowSceneActive else {
                    self.shellLogSafe("\(reason): app no longer foreground-active; deferring open")
                    return
                }
                let result = await openAction(id: "vr")
                self.shellLogSafe("\(reason) attempt \(attempt) openImmersiveSpace result=\(result) epoch=\(self.epoch) \(self.windowStateDescription())")
                if case .opened = result {
                    self.opening = false
                    self.immersiveOpen = true
                    self.wantsImmersive = true
                    self.presenting = false
                    self.statusMessage = "VR opened — waiting for first presented frame"
                    self.lastOpenError = nil
                    self.reopenOnActive = false
                    self.autoRetries = 0
                    self.lastOpenGeneration = VRMCCompositor_CurrentGeneration()
                    self.lastOpenAt = Date()
                    self.shellLogSafe("immersive session opened generation=\(self.lastOpenGeneration) chrome=\(self.chromeMode) reason=\(reason); waiting for the first PRESENTED compositor frame before parking windows")
                    self.waitForPresentedFrame(reason: reason)
                    return
                }
                if case .userCancelled = result {
                    self.statusMessage = "VR open cancelled"
                    if reason == "manual" { self.lastOpenError = "Immersive space open was cancelled by the system." }
                    return
                }
                // An error usually means SwiftUI still considers a previous space open.
                if let dismissAction = self.dismissAction { await dismissAction() }
                self.needsDismiss = true
                try? await Task.sleep(for: .seconds(2))
            }
            if reason == "manual" || reason == "auto" || reason == "selftest" {
                self.lastOpenError = "Could not open the immersive space (4 attempts). The window stays usable; tap Enter VR to retry."
                self.statusMessage = "VR open failed"
            }
            self.reopenOnActive = self.reopenOnActive || startReopen
        }
    }

    /// NO-FRAME watchdog: never dismiss, never auto-retry from here. Leaving the space open keeps the
    /// compositor log and the immersive session collectable, which is what makes the next run decisive.
    private func waitForPresentedFrame(reason: String) {
        noFrameTask?.cancel()
        let openedAt = Date()
        let generation = lastOpenGeneration
        noFrameTask = Task { [weak self] in
            guard let self else { return }
            for tick in 1...4 {
                try? await Task.sleep(for: .seconds(8))
                if Task.isCancelled { return }
                if self.presenting { return }
                let elapsed = Int(Date().timeIntervalSince(openedAt))
                if tick == 1 {
                    self.shellLogSafe("NO-FRAME: no presented compositor frame \(elapsed) s after open (reason=\(reason) generation=\(generation) \(self.windowStateDescription())); leaving the immersive space OPEN (no dismiss, no retry) - see vrmc-compositor.log")
                } else {
                    self.shellLogSafe("NO-FRAME heartbeat \(tick)/4: still no presented compositor frame \(elapsed) s after open (reason=\(reason)); space left open")
                }
            }
        }
    }

    private func shellLogSafe(_ message: String) {
        shellLog(message)
    }

    // MARK: - Window parking

    /// Park/show the regular windows. Default parking is alpha-only: the window stays in the scene
    /// (isHidden is never set), it is just transparent and non-interactive. Hiding every window is
    /// followed by UIScene.willDeactivate in the EV-0090 device logs, which is the suspected cause of
    /// the scene deactivation/backgrounding that kills the immersive session.
    /// vrmc-hide-windows.flag restores the old hide behaviour for A/B.
    /// Keep the game/launcher windows parked for the whole immersive session (see parkingTask).
    private func startParkingLoop() {
        parkingTask?.cancel()
        parkingTask = Task { [weak self] in
            var lastSignature = ""
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if Task.isCancelled { return }
                guard self.immersiveOpen, self.presenting, !self.noParking else { continue }
                let signature = self.windowStateDescription()
                if signature != lastSignature {
                    lastSignature = signature
                    self.setGameWindowsVisible(false, log: "window re-parked (periodic)")
                } else {
                    self.reapplyWindowParking()
                }
            }
        }
    }

    /// Re-apply the parked values without logging on every tick.
    private func reapplyWindowParking() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes
            where scene.session.role == .windowApplication {
            for window in scene.windows {
                window.alpha = 0
                window.isUserInteractionEnabled = false
                if hideWindowsOptIn { window.isHidden = true }
            }
        }
    }

    private func setGameWindowsVisible(_ visible: Bool, log: String) {
        var count = 0
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes
            where scene.session.role == .windowApplication {
            for window in scene.windows {
                if visible {
                    window.alpha = 1
                    window.isUserInteractionEnabled = true
                    if hideWindowsOptIn { window.isHidden = false }
                } else {
                    window.alpha = 0
                    window.isUserInteractionEnabled = false
                    if hideWindowsOptIn { window.isHidden = true }
                }
                count += 1
            }
        }
        windowsParked = !visible
        let mode = hideWindowsOptIn ? "hide+alpha0 (opt-in)" : "alpha-only (never isHidden)"
        shellLog("\(log) windows=\(count) visible=\(visible) mode=\(mode) chrome=\(chromeMode) parked=\(windowsParked) \(windowStateDescription())")
    }
}

/// Minimal window control surface for the staged immersive entry (Option 2): the launcher stays in
/// the window while this overlay adds an explicit "Enter VR" trigger, the current immersive status and
/// any actionable error. It lets the CompositorServices path be validated manually, independently of
/// the JIT/game timing; the automatic open after the game starts stays enabled.
struct VRControlOverlay: View {
    @Bindable var shell: ShellCoordinator
    @State private var showSettings = false
    @State private var seated = false
    @State private var seatedFreeMove = false
    @State private var snapAngle = 45
    @State private var seatedHmdPointer = false
    @State private var autoSprint = true
    @State private var autoSprintThreshold = 0.9
    @State private var preset = "none"
    @State private var renderDistance = 12
    @State private var frameLimit = 90
    @State private var worldScale = 1.0
    @State private var autoHeight = true
    @State private var manualHeight = 1.70
    @State private var diagPeriod = 30
    @State private var thermalResponse = "notify"
    @State private var adaptiveFramerate = false
    @State private var middleGestures = true
    @State private var swipeGestures = false
    @State private var vignetteEnabled = false
    @State private var vignetteStrength = 0.5
    // Advanced gesture tuning (metres for distance thresholds; hotbar range in metres).
    @State private var pinchOnMm = 30.0
    @State private var pinchOffMm = 45.0
    @State private var fistOn = 1.25
    @State private var fistOff = 1.55
    @State private var middleOnMm = 35.0
    @State private var middleOffMm = 50.0
    @State private var ringOnMm = 32.0
    @State private var ringOffMm = 46.0
    @State private var swipeSpeed = 1.2
    @State private var hotbarRange = 0.18
    @State private var moveForwardScale = 3.0
    @State private var moveStrafeScale = 3.0
    @State private var moveDeadzone = 0.10
    @State private var moveOriginZ = 0.05
    @State private var rotatePulseMs = 120.0
    @State private var holdLastPoseMs = 250.0
    @State private var handComponentJoints = false
    @State private var settingsStatus = ""
    @State private var commandStatus = ""
    @State private var lastCommandResult = ""
    @State private var providerStatusLine = ""
    @State private var confirmResetSettings = false
    @State private var confirmResetInput = false
    @State private var acceptanceItems = shellLoadAcceptanceChecklist()
    @State private var exportURL: URL?
    @State private var exportStatus = ""
    @State private var statusLine = ""
    @State private var diagnosticTail: [String] = []
    @State private var modsReport: ModProvisionReport? = ShellProvisioning.lastReport

    private var acceptanceSummary: String {
        let pass = acceptanceItems.filter { $0.status == "PASS" }.count
        let fail = acceptanceItems.filter { $0.status == "FAIL" }.count
        let partial = acceptanceItems.filter { $0.status == "PARTIAL" }.count
        let notRun = acceptanceItems.filter { $0.status == "NOT RUN" }.count
        return "PASS=\(pass) PARTIAL=\(partial) FAIL=\(fail) NOT RUN=\(notRun)"
    }

    /// Required-mods status: a green "ready" or orange "action needed" summary; expanding it shows the
    /// per-mod lines and, when Vivecraft is absent/rejected, exactly what a fresh install must do.
    @ViewBuilder private var modsPanel: some View {
        if let report = modsReport {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(report.lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    if !report.vivecraftPresent {
                        Text("Vivecraft is not redistributed. Download \(ShellProvisioning.vivecraftFileName) from the Vivecraft project, save it to On My Apple Vision Pro > VRMC in the Files app (or AirDrop it), then tap Re-check.")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    Button("Re-check mods") { modsReport = ShellProvisioning.run() }
                        .font(.caption2).buttonStyle(.bordered)
                }
            } label: {
                Text(report.ready ? "Mods: ready" : "Mods: action needed")
                    .font(.caption).foregroundStyle(report.ready ? Color.green : Color.orange)
            }
            .font(.caption)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    shell.enterVRManually()
                } label: {
                    Text(shell.immersiveOpen ? "VR active" : "Enter VR")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(shell.immersiveOpen ? Color.green.opacity(0.25) : Color.accentColor.opacity(0.30))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(shell.immersiveOpen)

                VStack(alignment: .leading, spacing: 2) {
                    Text(shell.immersiveOpen ? "Immersive active" : "Immersive off")
                        .font(.caption).bold()
                    Text(shell.presenting ? "presenting" : (shell.immersiveOpen ? "waiting for frame" : "not presenting"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Text(shell.statusMessage).font(.caption).foregroundStyle(.secondary)
            if let error = shell.lastOpenError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if !statusLine.isEmpty {
                Text(statusLine).font(.caption2).foregroundStyle(.secondary)
            }
            if !providerStatusLine.isEmpty {
                Text(providerStatusLine).font(.caption2).foregroundStyle(.secondary)
            }
            modsPanel
            if !diagnosticTail.isEmpty {
                DisclosureGroup("Recent diagnostics") {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(diagnosticTail.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Button("Refresh") { refreshDiagnosticTail() }.font(.caption2).buttonStyle(.bordered)
                    }
                }
                .font(.caption)
            }
            DisclosureGroup("Acceptance checklist") {
                VStack(alignment: .leading, spacing: 3) {
                    Text(acceptanceSummary).font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    ForEach($acceptanceItems) { $item in
                        HStack(spacing: 6) {
                            Text(item.id).font(.system(size: 9, design: .monospaced))
                                .frame(width: 34, alignment: .leading)
                            Text(item.title).font(.system(size: 10)).lineLimit(1)
                            Spacer(minLength: 4)
                            Picker("", selection: $item.status) {
                                ForEach(shellAcceptanceStatuses, id: \.self) { status in
                                    Text(status).tag(status)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .font(.system(size: 10))
                        }
                    }
                    HStack {
                        Button("Save checklist") {
                            settingsStatus = shellSaveAcceptanceChecklist(acceptanceItems)
                                ? "Acceptance checklist saved." : "Checklist save failed."
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        Button("Reset checklist") {
                            acceptanceItems = shellAcceptanceDefaults()
                            _ = shellSaveAcceptanceChecklist(acceptanceItems)
                            settingsStatus = "Acceptance checklist reset."
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)

            if !shell.crashGuardMessage.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(shell.crashGuardMessage).font(.caption2).foregroundStyle(.orange)
                    if shell.safeMode {
                        Button("Clear crash safe mode") { shell.clearCrashGuard() }
                            .font(.caption2)
                            .buttonStyle(.bordered)
                    }
                }
            }

            DisclosureGroup("VRMC settings (next game launch)", isExpanded: $showSettings) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Seated mode", isOn: $seated)
                    Toggle("Seated free move", isOn: $seatedFreeMove)
                    Toggle("Seated HMD pointer (head-aim GUI cursor)", isOn: $seatedHmdPointer)
                    Toggle("Auto-sprint at full stick", isOn: $autoSprint)
                    if autoSprint {
                        HStack {
                            Text("Auto-sprint threshold: \(String(format: "%.2f", autoSprintThreshold))").font(.caption2)
                            Slider(value: $autoSprintThreshold, in: 0.5...1.0, step: 0.01)
                        }
                    }
                    HStack {
                        Text("Turn").font(.caption)
                        Spacer()
                        Picker("Turn", selection: $snapAngle) {
                            Text("Smooth").tag(0)
                            Text("15°").tag(15)
                            Text("30°").tag(30)
                            Text("45°").tag(45)
                            Text("90°").tag(90)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    Toggle("Middle-pinch gestures (locomotion/jump/sneak/radial)", isOn: $middleGestures)
                    Toggle("Open-hand swipe gestures (hotbar/chat/keyboard/swap/drop)", isOn: $swipeGestures)
                    Toggle("Comfort vignette", isOn: $vignetteEnabled)
                    if vignetteEnabled {
                        HStack {
                            Text("Vignette strength: \(String(format: "%.2f", vignetteStrength))").font(.caption)
                            Slider(value: $vignetteStrength, in: 0.1...0.9, step: 0.05)
                        }
                    }
                    HStack {
                        Text("Performance").font(.caption)
                        Spacer()
                        Picker("Performance", selection: $preset) {
                            Text("None").tag("none")
                            Text("Performance").tag("performance")
                            Text("Balanced").tag("balanced")
                            Text("Quality").tag("quality")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    Stepper("Render distance: \(renderDistance)", value: $renderDistance, in: 6...24)
                    DisclosureGroup("Input tuning (advanced)") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Pinch on/off: \(Int(pinchOnMm))/\(Int(pinchOffMm)) mm").font(.caption2)
                                Slider(value: $pinchOnMm, in: 15...45, step: 1)
                                Slider(value: $pinchOffMm, in: 25...70, step: 1)
                            }
                            HStack {
                                Text("Fist on/off: \(String(format: "%.2f", fistOn))/\(String(format: "%.2f", fistOff))").font(.caption2)
                                Slider(value: $fistOn, in: 0.9...1.5, step: 0.01)
                                Slider(value: $fistOff, in: 1.2...2.0, step: 0.01)
                            }
                            HStack {
                                Text("Middle pinch on/off: \(Int(middleOnMm))/\(Int(middleOffMm)) mm").font(.caption2)
                                Slider(value: $middleOnMm, in: 20...50, step: 1)
                                Slider(value: $middleOffMm, in: 35...70, step: 1)
                            }
                            HStack {
                                Text("Ring pinch on/off: \(Int(ringOnMm))/\(Int(ringOffMm)) mm").font(.caption2)
                                Slider(value: $ringOnMm, in: 15...45, step: 1)
                                Slider(value: $ringOffMm, in: 30...60, step: 1)
                            }
                            HStack {
                                Text("Swipe speed: \(String(format: "%.1f", swipeSpeed)) m/s").font(.caption2)
                                Slider(value: $swipeSpeed, in: 0.5...3.0, step: 0.1)
                            }
                            HStack {
                                Text("Hotbar range: \(String(format: "%.2f", hotbarRange)) m").font(.caption2)
                                Slider(value: $hotbarRange, in: 0.10...0.30, step: 0.01)
                            }
                            HStack {
                                Text("Move forward/strafe: \(String(format: "%.1f", moveForwardScale))/\(String(format: "%.1f", moveStrafeScale))").font(.caption2)
                                Slider(value: $moveForwardScale, in: 1.0...6.0, step: 0.1)
                                Slider(value: $moveStrafeScale, in: 1.0...6.0, step: 0.1)
                            }
                            HStack {
                                Text("Move deadzone: \(String(format: "%.2f", moveDeadzone)) · originZ: \(String(format: "%.2f", moveOriginZ))").font(.caption2)
                                Slider(value: $moveDeadzone, in: 0.02...0.40, step: 0.01)
                                Slider(value: $moveOriginZ, in: -0.30...0.30, step: 0.01)
                            }
                            HStack {
                                Text("Snap-turn pulse: \(Int(rotatePulseMs)) ms").font(.caption2)
                                Slider(value: $rotatePulseMs, in: 60...300, step: 10)
                            }
                            HStack {
                                Text("Tracking-dropout pose hold: \(Int(holdLastPoseMs)) ms").font(.caption2)
                                Slider(value: $holdLastPoseMs, in: 0...1000, step: 50)
                            }
                            Toggle("Fingertip held-item component (experimental)", isOn: $handComponentJoints)
                            Text("Press Reload input to apply while the game runs; otherwise next launch. Keep off > on.").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.top, 4)
                    }
                    Stepper("Frame limit: \(frameLimit)", value: $frameLimit, in: 60...120, step: 30)
                    HStack {
                        Text("World scale: \(String(format: "%.2f", worldScale))×").font(.caption)
                        Slider(value: $worldScale, in: 0.8...1.5, step: 0.05)
                    }
                    Toggle("Auto height", isOn: $autoHeight)
                    if !autoHeight {
                        HStack {
                            Text("Height: \(String(format: "%.2f", manualHeight)) m").font(.caption)
                            Slider(value: $manualHeight, in: 1.30...2.10, step: 0.01)
                        }
                    }
                    HStack {
                        Text("Thermal response").font(.caption)
                        Spacer()
                        Picker("Thermal response", selection: $thermalResponse) {
                            Text("Notify").tag("notify")
                            Text("Reduce quality").tag("reduce")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    Toggle("Adaptive framerate (cap after 2 over-budget windows)", isOn: $adaptiveFramerate)
                    Stepper("Diagnostics period: \(diagPeriod)s", value: $diagPeriod, in: 10...120, step: 10)
                    Button {
                        applySettings()
                    } label: {
                        Text("Save for next launch")
                            .font(.caption).bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    if !settingsStatus.isEmpty {
                        Text(settingsStatus).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button("Recenter") {
                            commandStatus = shellQueueGameCommand("recenter") ? "Recenter queued." : "Queue failed."
                        }
                        .buttonStyle(.bordered)
                        Button("Calibrate height") {
                            commandStatus = shellQueueGameCommand("calibrate-height") ? "Height calibration queued." : "Queue failed."
                        }
                        .buttonStyle(.bordered)
                    }
                    HStack(spacing: 8) {
                        Button("Reload settings") {
                            commandStatus = shellQueueGameCommand("reload-settings") ? "Reload queued." : "Queue failed."
                        }
                        .buttonStyle(.bordered)
                        Button("Diagnostics") {
                            commandStatus = shellQueueGameCommand("diag") ? "Diagnostics queued." : "Queue failed."
                        }
                        .buttonStyle(.bordered)
                        Button("Reload input") {
                            commandStatus = shellQueueGameCommand("reload-input") ? "Input reload queued." : "Queue failed."
                        }
                        .buttonStyle(.bordered)
                        Button("Controls help") {
                            commandStatus = shellQueueGameCommand("controls") ? "Controls help queued." : "Queue failed."
                        }
                        .buttonStyle(.bordered)
                        Button("Status") {
                            commandStatus = shellQueueGameCommand("status") ? "Status write queued." : "Queue failed."
                        }
                        .buttonStyle(.bordered)
                        Button("Restore performance") {
                            commandStatus = shellQueueGameCommand("restore-performance") ? "Performance restore queued." : "Queue failed."
                        }
                        .buttonStyle(.bordered)
                        Button("Calibrate hands") {
                            commandStatus = shellQueueGameCommand("calibrate-hands") ? "Hand calibration started (follow action-bar prompts)." : "Queue failed."
                        }
                        .buttonStyle(.bordered)
                        Button("Apply hand calibration") {
                            commandStatus = shellQueueGameCommand("apply-hand-calibration") ? "Apply calibration queued." : "Queue failed."
                        }
                        .buttonStyle(.bordered)
                        Button("Release stuck input") {
                            commandStatus = shellQueueGameCommand("release-input") ? "Input release queued." : "Queue failed."
                        }
                        .buttonStyle(.bordered)
                    }
                    if !commandStatus.isEmpty {
                        Text(commandStatus).font(.caption2).foregroundStyle(.secondary)
                    }
                    if !lastCommandResult.isEmpty {
                        Text("Last result: \(lastCommandResult)").font(.caption2).foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        Button("Export diagnostics") {
                            if let url = shellBuildDiagnosticsBundle() {
                                exportURL = url
                                exportStatus = "Bundle ready — use Share to save/AirDrop."
                            } else {
                                exportStatus = "Export failed — see shell log."
                            }
                        }
                        .buttonStyle(.bordered)
                        if let exportURL {
                            ShareLink(item: exportURL) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    if !exportStatus.isEmpty {
                        Text(exportStatus).font(.caption2).foregroundStyle(.secondary)
                    }
                    Button("Reset input tuning") { confirmResetInput = true }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        .confirmationDialog("Reset input tuning?", isPresented: $confirmResetInput,
                                            titleVisibility: .visible) {
                            Button("Reset input tuning", role: .destructive) {
                                try? FileManager.default.removeItem(at: shellInputTuneURL())
                                loadSettings()
                                _ = shellQueueGameCommand("reload-input")
                                settingsStatus = "Input tuning reset to defaults (reload queued)."
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Removes vrmc-input-tune.properties only. Runtime/comfort settings, saves and logs are kept.")
                        }
                    Button("Reset VRMC settings") { confirmResetSettings = true }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        .confirmationDialog("Reset VRMC settings?", isPresented: $confirmResetSettings,
                                            titleVisibility: .visible) {
                            Button("Reset settings", role: .destructive) {
                                try? FileManager.default.removeItem(at: shellRuntimeSettingsURL())
                                try? FileManager.default.removeItem(at: shellInputTuneURL())
                                try? FileManager.default.removeItem(at: shellVignetteURL())
                                loadSettings()
                                settingsStatus = "VRMC settings reset to defaults."
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Removes runtime, input-tune and vignette settings only. Saves, logs and the crash guard are kept.")
                        }
                    DisclosureGroup("Gesture reference") {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Pinch (thumb+index): attack / GUI click; left hold = teleport").font(.caption2)
                            Text("Fist: use hold (right, bow draw) / GUI right-click tap / menu (left tap)").font(.caption2)
                            Text("Both fists tap: inventory menu; both middle taps: climb jump; both middle double-tap: recenter").font(.caption2)
                            Text("Middle pinch (thumb+middle): left hold + move hand = walk/strafe; right hold = sneak; right tap = jump; left tap/double = snap turn; right double = radial; both tap = climb jump; both double = recenter").font(.caption2)
                            Text("Open-hand swipes (opt-in): right horizontal = hotbar ±; right vertical = scroll; left up/down = keyboard/chat; left horizontal = swap/drop").font(.caption2)
                            Text("Both thumb-ring pinches: hold, move left hand left/right to choose hotbar slot 1–9, release to select").font(.caption2)
                        }
                        .padding(.top, 2)
                    }
                    Text("Provider reads settings/input at game start; the compositor reads the vignette at the next immersive open. Invalid values are ignored/logged. Diagnostics: vrmc-shell.log, vrmc-thermal.log.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.top, 4)
            }
            .font(.caption)
        }
        .padding(12)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(20)
        .onAppear { loadSettings() }
        .task {
            while !Task.isCancelled {
                refreshStatus()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func refreshStatus() {
        let docs = shellDocumentsURL()
        let game = docs.appendingPathComponent("instances/default")
        var parts: [String] = []
        if let data = try? Data(contentsOf: game.appendingPathComponent("vrmc-status.json")),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let bridge = obj["bridgeReady"] as? Bool ?? false
            let gen = obj["displayViewsGen"] as? Int ?? 0
            let left = obj["handLeftTracked"] as? Bool ?? false
            let right = obj["handRightTracked"] as? Bool ?? false
            let seated = obj["seated"] as? Bool ?? false
            parts.append("bridge=\(bridge ? "ready" : "not ready")")
            parts.append("displayGen=\(gen)")
            parts.append("hands=\(left ? "L" : "-")\(right ? "R" : "-")")
            parts.append("seated=\(seated)")
            let providerJar = game.appendingPathComponent("mods/vrmc-provider.jar")
            if FileManager.default.fileExists(atPath: providerJar.path) {
                let hash = shellFileSHA256(providerJar).map { String($0.prefix(12)) } ?? "?"
                parts.append("providerJar=\(hash)")
            } else {
                parts.append("providerJar=MISSING")
            }
        } else {
            parts.append("provider status: no session yet")
        }
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        parts.append("thermal=\(thermal)")
        parts.append("lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off")")
        statusLine = parts.joined(separator: " · ")
        if diagnosticTail.isEmpty { refreshDiagnosticTail() }
        let statusURL = game.appendingPathComponent("vrmc-status.json")
        if let data = try? Data(contentsOf: statusURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let abi = obj["abi"].map { "\($0)" } ?? "?"
            let bridge = (obj["bridgeReady"] as? Bool).map { $0 ? "ok" : "no" } ?? "?"
            let tracked = obj["trackedFrames"].map { "\($0)" } ?? "?"
            let left = (obj["handLeftTracked"] as? Bool) == true ? "L" : "-"
            let right = (obj["handRightTracked"] as? Bool) == true ? "R" : "-"
            let thermal = obj["thermalState"] as? String ?? "?"
            let adaptive = (obj["adaptiveFramerateApplied"] as? Bool) == true ? "capped" : "off"
            let p95 = (obj["frameP95Ms"] as? Double).map { String(format: "%.1f", $0) } ?? "?"
            let missed = obj["missed90Frames"].map { "\($0)" } ?? "?"
            var bow = ""
            if (obj["bowActive"] as? Bool) == true {
                let pct = (obj["bowDrawPercent"] as? Double).map { Int(($0 * 100).rounded()) } ?? 0
                let notched = (obj["bowNotched"] as? Bool) == true ? "notched " : ""
                bow = " bow=\(notched)\(pct)%"
            }
            var climb = ""
            let grabbing = (obj["climbGrabbing"] as? Bool) == true
            let climbey = (obj["climbeyClimb"] as? Bool) == true
            let climbActive = (obj["climbActive"] as? Bool) == true
            if grabbing || climbey || climbActive {
                climb = " climb=\(grabbing ? "grab" : "-")/\(climbey ? "climbey" : "-")/\(climbActive ? "active" : "-")"
            }
            let gestures = obj["gestures"] as? String ?? ""
            let gestureText = gestures.isEmpty ? "" : " gestures=\(gestures)"
            providerStatusLine = "provider: abi=\(abi) bridge=\(bridge) tracked=\(tracked) hands=\(left)\(right) thermal=\(thermal) adaptive=\(adaptive) p95=\(p95)ms missed90=\(missed)\(bow)\(climb)\(gestureText)"
        } else {
            providerStatusLine = ""
        }
        let resultURL = game.appendingPathComponent("vrmc-command-result.txt")
        if let text = try? String(contentsOf: resultURL, encoding: .utf8) {
            let lines = text.split(whereSeparator: \.isNewline)
            if let last = lines.last { lastCommandResult = String(last.suffix(200)) }
        }
    }

    private func refreshDiagnosticTail() {
        let docs = shellDocumentsURL()
        let game = docs.appendingPathComponent("instances/default")
        let files = [
            docs.appendingPathComponent("vrmc-compositor.log"),
            docs.appendingPathComponent("vrmc-shell.log"),
            docs.appendingPathComponent("latestlog.txt"),
            game.appendingPathComponent("vrmc-status.json"),
        ]
        var lines: [String] = []
        for url in files {
            guard let data = try? Data(contentsOf: url) else { continue }
            let slice = data.count > 131_072 ? data.suffix(131_072) : data
            guard let text = String(data: slice, encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline).suffix(2000) {
                let s = String(line)
                if s.contains("[VRMC-") || s.contains("WARN") || s.contains("ERROR")
                    || s.contains("FAIL") || s.contains("CRASH") {
                    lines.append("\(url.lastPathComponent): \(s.prefix(220))")
                }
            }
        }
        diagnosticTail = Array(lines.suffix(8))
    }

    private func loadSettings() {
        let values = shellReadRuntimeSettings()
        seated = values["comfort.seated"] == "true"
        seatedFreeMove = values["comfort.seatedFreeMove"] == "true"
        seatedHmdPointer = values["comfort.seatedHmdPointer"] == "true"
        autoSprint = values["comfort.autoSprint"] != "false"
        if let raw = values["comfort.autoSprintThreshold"], let v = Double(raw) {
            autoSprintThreshold = min(1.0, max(0.5, v))
        }
        if let raw = values["comfort.worldRotationIncrement"], let angle = Float(raw) {
            let allowed = [0, 15, 30, 45, 90]
            snapAngle = allowed.min(by: { abs(Double($0) - Double(angle)) < abs(Double($1) - Double(angle)) }) ?? 0
        }
        preset = values["performance.preset"] ?? "none"
        if let raw = values["performance.renderDistance"], let n = Int(raw) { renderDistance = min(24, max(6, n)) }
        if let raw = values["performance.framerateLimit"], let n = Int(raw) { frameLimit = min(120, max(60, (n / 30) * 30)) }
        if let raw = values["comfort.worldScale"], let v = Float(raw), v >= 0.8, v <= 1.5 { worldScale = Double(v) }
        if let raw = values["comfort.manualHeight"], let v = Float(raw), v != -1.0 {
            autoHeight = false
            manualHeight = min(2.10, max(1.30, Double(v)))
        } else {
            autoHeight = true
        }
        if let raw = values["diagnostics.periodSeconds"], let n = Int(raw) { diagPeriod = min(120, max(10, (n / 10) * 10)) }
        thermalResponse = values["performance.thermalResponse"] == "reduce" ? "reduce" : "notify"
        adaptiveFramerate = values["performance.adaptiveFramerate"] == "true"
        let input = shellReadInputTune()
        middleGestures = input["middle.enabled"]?.lowercased() != "false"
        swipeGestures = ["true", "1"].contains(input["swipe.enabled"]?.lowercased() ?? "")
        let vignette = shellReadVignette()
        vignetteEnabled = vignette.enabled
        vignetteStrength = vignette.strength
        pinchOnMm = (Double(input["pinch.on"] ?? "") ?? 0.030) * 1000.0
        pinchOffMm = (Double(input["pinch.off"] ?? "") ?? 0.045) * 1000.0
        fistOn = Double(input["fist.on"] ?? "") ?? 1.25
        fistOff = Double(input["fist.off"] ?? "") ?? 1.55
        middleOnMm = (Double(input["middle.on"] ?? "") ?? 0.035) * 1000.0
        middleOffMm = (Double(input["middle.off"] ?? "") ?? 0.050) * 1000.0
        ringOnMm = (Double(input["ring.on"] ?? "") ?? 0.032) * 1000.0
        ringOffMm = (Double(input["ring.off"] ?? "") ?? 0.046) * 1000.0
        swipeSpeed = Double(input["swipe.speed"] ?? "") ?? 1.2
        hotbarRange = Double(input["hotbar.range"] ?? "") ?? 0.18
        moveForwardScale = Double(input["move.forwardScale"] ?? "") ?? 3.0
        moveStrafeScale = Double(input["move.strafeScale"] ?? "") ?? 3.0
        moveDeadzone = Double(input["move.deadzone"] ?? "") ?? 0.10
        moveOriginZ = Double(input["move.originZ"] ?? "") ?? 0.05
        rotatePulseMs = Double(input["move.rotatePulseMs"] ?? "") ?? 120.0
        holdLastPoseMs = Double(input["tracking.holdLastPoseMs"] ?? "") ?? 250.0
        handComponentJoints = input["hands.componentMode"]?.lowercased() == "joints"
    }

    private func applySettings() {
        var values = shellReadRuntimeSettings()
        values["comfort.seated"] = seated ? "true" : "false"
        values["comfort.seatedFreeMove"] = seatedFreeMove ? "true" : "false"
        values["comfort.seatedHmdPointer"] = seatedHmdPointer ? "true" : "false"
        values["comfort.autoSprint"] = autoSprint ? "true" : "false"
        values["comfort.autoSprintThreshold"] = String(format: "%.2f", autoSprintThreshold)
        values["comfort.worldRotationIncrement"] = String(snapAngle)
        values["performance.preset"] = preset
        values["performance.renderDistance"] = String(renderDistance)
        values["performance.framerateLimit"] = String(frameLimit)
        values["comfort.worldScale"] = String(format: "%.2f", worldScale)
        values["comfort.manualHeight"] = autoHeight ? "-1" : String(format: "%.2f", manualHeight)
        values["diagnostics.periodSeconds"] = String(diagPeriod)
        values["performance.thermalResponse"] = thermalResponse
        values["performance.adaptiveFramerate"] = adaptiveFramerate ? "true" : "false"
        var input = shellReadInputTune()
        input["middle.enabled"] = middleGestures ? "true" : "false"
        input["swipe.enabled"] = swipeGestures ? "true" : "false"
        let pOn = min(pinchOnMm, pinchOffMm - 1.0) / 1000.0
        let pOff = max(pinchOffMm, pinchOnMm + 1.0) / 1000.0
        let fOn = min(fistOn, fistOff - 0.01)
        let fOff = max(fistOff, fistOn + 0.01)
        input["pinch.on"] = String(format: "%.3f", pOn)
        input["pinch.off"] = String(format: "%.3f", pOff)
        input["fist.on"] = String(format: "%.2f", fOn)
        input["fist.off"] = String(format: "%.2f", fOff)
        let mOn = min(middleOnMm, middleOffMm - 1.0) / 1000.0
        let mOff = max(middleOffMm, middleOnMm + 1.0) / 1000.0
        let rOn = min(ringOnMm, ringOffMm - 1.0) / 1000.0
        let rOff = max(ringOffMm, ringOnMm + 1.0) / 1000.0
        input["middle.on"] = String(format: "%.3f", mOn)
        input["middle.off"] = String(format: "%.3f", mOff)
        input["ring.on"] = String(format: "%.3f", rOn)
        input["ring.off"] = String(format: "%.3f", rOff)
        input["swipe.speed"] = String(format: "%.2f", swipeSpeed)
        input["hotbar.range"] = String(format: "%.2f", hotbarRange)
        input["move.forwardScale"] = String(format: "%.2f", moveForwardScale)
        input["move.strafeScale"] = String(format: "%.2f", moveStrafeScale)
        input["move.deadzone"] = String(format: "%.2f", moveDeadzone)
        input["move.originZ"] = String(format: "%.2f", moveOriginZ)
        input["move.rotatePulseMs"] = String(format: "%.0f", rotatePulseMs)
        input["tracking.holdLastPoseMs"] = String(format: "%.0f", holdLastPoseMs)
        input["hands.componentMode"] = handComponentJoints ? "joints" : "identity"
        let runtimeOK = shellWriteRuntimeSettings(values)
        let inputOK = shellWriteInputTune(input)
        let vignetteOK = shellWriteVignette(enabled: vignetteEnabled, strength: vignetteStrength)
        settingsStatus = (runtimeOK && inputOK && vignetteOK)
            ? "Saved — applies at next game start (vignette at next immersive open)."
            : "Save failed — see shell log."
    }
}

@main
struct VRMCShellApp: App {
    @State private var shell = ShellCoordinator.shared
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some Scene {
        shell.bind(open: openImmersiveSpace, dismiss: dismissImmersiveSpace)
        return scenes
    }

    @SceneBuilder private var scenes: some Scene {
        WindowGroup {
            ZStack(alignment: .topLeading) {
                LauncherHostView()
                    .onAppear { shellLog("launcher host appeared") }
                VRControlOverlay(shell: shell)
            }
        }
        // For a WindowGroup this controls the window chrome (bottom bar / ornaments). Scene-level so it
        // applies to the whole game session; with the M3b modal game-surface presentation the SwiftUI
        // scene stays alive, so this preference survives the game launch (EV-0086 regression).
        .persistentSystemOverlays((shell.immersiveOpen || shell.hideChromeAlways) ? .hidden : .automatic)

        ImmersiveSpace(id: "vr") {
            CompositorLayer(configuration: ShellLayerConfiguration()) { layerRenderer in
                // M4-W2: the system tags indirect pinch activations with the tracking area the user
                // was gazing at. Forward the id/phase/kind into the bridge; the provider turns the
                // tile into a GUI click. Events without a tracking area are ignored. Gaze is opt-in:
                // do not install the handler unless tracking areas were requested.
                if shellDocumentFlag("vrmc-gaze.flag") && !shellDocumentFlag("vrmc-no-tracking-areas.flag") {
                layerRenderer.onSpatialEvent = { events in
                    for event in events where event.trackingAreaIdentifier != .invalid {
                        let phase: Int32
                        switch event.phase {
                        case .active: phase = 1
                        case .ended: phase = 2
                        case .cancelled: phase = 3
                        @unknown default: phase = 0
                        }
                        let kind: Int32
                        switch event.kind {
                        case .indirectPinch: kind = 1
                        case .directPinch: kind = 2
                        case .touch: kind = 3
                        case .pointer: kind = 4
                        case .pencil: kind = 5
                        @unknown default: kind = 0
                        }
                        shellLog("spatial event tile=\(event.trackingAreaIdentifier) phase=\(phase) kind=\(kind)")
                        VRMCInput_PublishGazeEvent(event.trackingAreaIdentifier.rawValue, phase, kind)
                    }
                }
                }
                VRMCCompositor_InitAndRun(layerRenderer)
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
