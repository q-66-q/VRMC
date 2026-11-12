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

func shellDocumentsURL() -> URL {
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
}

/// M6/M5 in-headset acceptance checklist persisted to Documents and included in diagnostics exports.
struct ShellAcceptanceItem: Identifiable, Codable {
    var id: String
    var title: String
    var status: String
}

let shellAcceptanceStatuses = ["NOT RUN", "PARTIAL", "PASS", "FAIL"]

func shellAcceptanceDefaults() -> [ShellAcceptanceItem] {
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

func shellLoadAcceptanceChecklist() -> [ShellAcceptanceItem] {
    let url = shellDocumentsURL().appendingPathComponent("vrmc-acceptance-checklist.json")
    guard let data = try? Data(contentsOf: url),
          let items = try? JSONDecoder().decode([ShellAcceptanceItem].self, from: data),
          !items.isEmpty else {
        return shellAcceptanceDefaults()
    }
    return items
}

func shellChecklistMarkdown(_ items: [ShellAcceptanceItem]) -> String {
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
func shellSaveAcceptanceChecklist(_ items: [ShellAcceptanceItem]) -> Bool {
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

func shellDocumentFlag(_ name: String) -> Bool {
    return FileManager.default.fileExists(atPath: shellDocumentsURL().appendingPathComponent(name).path)
}

func shellDocumentString(_ name: String) -> String? {
    let url = shellDocumentsURL().appendingPathComponent(name)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

// M5 launcher settings: the provider reads vrmc-runtime.properties from the default game directory at
// the next launch. The shell panel edits only the keys it owns and preserves any other user keys.
func shellRuntimeSettingsURL() -> URL {
    return shellDocumentsURL()
        .appendingPathComponent("instances/default")
        .appendingPathComponent("vrmc-runtime.properties")
}

func shellReadRuntimeSettings() -> [String: String] {
    var values: [String: String] = [:]
    guard let text = try? String(contentsOf: shellRuntimeSettingsURL(), encoding: .utf8) else { return values }
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

/// Queue an M5 provider command (recenter / calibrate-height / reload-settings / diag / status).
/// The provider consumes it while the game runs; queued commands are harmless if consumed early.
func shellQueueGameCommand(_ command: String) -> Bool {
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
func shellBuildDiagnosticsBundle() -> URL? {
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

func shellFileSHA256(_ url: URL) -> String? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

func shellVignetteURL() -> URL {
    return shellDocumentsURL().appendingPathComponent("vrmc-vignette.flag")
}

func shellReadVignette() -> (enabled: Bool, strength: Double) {
    let url = shellVignetteURL()
    guard FileManager.default.fileExists(atPath: url.path) else { return (false, 0.5) }
    let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = Double(trimmed) ?? 0.5
    return (true, min(0.9, max(0.0, value)))
}

@discardableResult
func shellWriteVignette(enabled: Bool, strength: Double) -> Bool {
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

func shellInputTuneURL() -> URL {
    return shellDocumentsURL()
        .appendingPathComponent("instances/default")
        .appendingPathComponent("vrmc-input-tune.properties")
}

func shellReadInputTune() -> [String: String] {
    var values: [String: String] = [:]
    guard let text = try? String(contentsOf: shellInputTuneURL(), encoding: .utf8) else { return values }
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

@discardableResult
func shellWriteInputTune(_ values: [String: String]) -> Bool {
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
func shellWriteRuntimeSettings(_ values: [String: String]) -> Bool {
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
@MainActor
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

/// Keep an append-only log bounded: when it grows past maxBytes only its newest half is kept.
/// (vrmc-thermal.log gained a line every 30 s of use and was never rotated.)
private func trimAppendOnlyLog(_ name: String, maxBytes: Int) {
    let url = shellDocumentsURL().appendingPathComponent(name)
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let size = attrs[.size] as? Int, size > maxBytes,
          let data = try? Data(contentsOf: url) else { return }
    var tail = data.suffix(maxBytes / 2)
    if let newline = tail.firstIndex(of: 0x0A) { tail = tail.suffix(from: tail.index(after: newline)) }
    try? Data(tail).write(to: url, options: .atomic)
}

@_cdecl("vrmc_shell_start")
public func vrmcShellStart() -> Int32 {
    rotateSessionLog("vrmc-shell.log", prev: "vrmc-shell.prev.log")
    // Read these before vrmc-clear-diagnostics deletes the diagnostic flags.
    let selftestRequested = shellDocumentFlag("vrmc-immersive-selftest.flag")
    let openOnLaunchRequested = shellDocumentFlag("vrmc-open-on-launch.flag")
    shellLog("vrmc_shell_start invoked")
    // Must run before VRMCShellApp.main() so no autolaunch/on-launch flag survives this process.
    neutralizeDiagnosticFlagsIfRequested()
    trimAppendOnlyLog("vrmc-thermal.log", maxBytes: 512 * 1024)
    // vrmc_shell_start runs on the main thread (called from the Amethyst C main() before
    // UIApplicationMain), so the main-actor state below can be touched synchronously. Keeping the
    // entry point nonisolated preserves its C-callable signature.
    MainActor.assumeIsolated {
        ShellStartupFlags.selftest = selftestRequested
        ShellStartupFlags.openOnLaunch = openOnLaunchRequested
        LauncherBridge.suppressLegacyWelcome()
        // Automatic setup: the bundled provider mod is installed/updated before the launcher can
        // start a game, so a fresh install never needs a manual jar copy.
        SetupManager.shared.installBundledProviderAtStartup()
        VRMCShellApp.main()
    }
    return 0
}

/// M8: maximum layer render quality [0,1] (visionOS 26+). This is the upper bound for the drawable's
/// resolution and for the dynamic-quality range the compositor's runtime controller may use inside.
/// 1.0 = the highest render quality the device supports (native per-eye panel resolution, i.e. the
/// "4K in both eyes" target); Documents/vrmc-max-render-quality.txt can pin a lower value for A/B
/// without rebuilding. An absent/unparsable file falls back to 1.0, never fails the immersive open.
func shellMaxRenderQuality() -> LayerRenderer.RenderQuality {
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

/// SwiftUI-owned container that hosts the single launcher view controller.
///
/// SwiftUI only ever manages this plain container; `LauncherBridge` moves the one launcher controller
/// into whichever container is currently active (the hidden 1×1 Play host or the Minecraft setup
/// sheet). That indirection is what keeps the launcher usable from the hidden host without a SwiftUI
/// teardown ever pulling it out of the other host.
final class LauncherHostContainer: UIViewController {
    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        self.view = view
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        children.first?.view.frame = view.bounds
    }
}

struct LauncherHostView: UIViewControllerRepresentable {
    /// The hidden host turns itself off while the Minecraft setup sheet owns the launcher.
    var isActive: Bool = true

    func makeUIViewController(context: Context) -> LauncherHostContainer {
        let container = LauncherHostContainer()
        if isActive { LauncherBridge.attachLauncher(to: container) }
        return container
    }

    func updateUIViewController(_ container: LauncherHostContainer, context: Context) {
        guard isActive else { return }
        LauncherBridge.attachLauncher(to: container)
    }
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

    /// True between the launcher starting the game and the provider/compositor reporting it stopped.
    private(set) var gameRunning = false
    @ObservationIgnored private var gameStarted = false {
        didSet { if gameRunning != gameStarted { gameRunning = gameStarted } }
    }
    /// Cancels the wait-for-first-game-frame task when the game stops or a new one starts.
    @ObservationIgnored private var gameOpenTask: Task<Void, Never>?
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
    /// Generation of the most recent session that actually presented at least one compositor frame.
    /// gameDidStop() clears `presenting` before the compositor's VRMCImmersiveEnded notification
    /// arrives, so compositorDidEnd() must not mistake that reset for "never presented" (the 1.3.3
    /// run logged "presentation never confirmed" after presenting 19,517 frames).
    @ObservationIgnored private var lastPresentedGeneration: Int32 = 0
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
    private(set) var statusMessage = "Ready"
    /// Last failure to open the immersive space, shown in the window so errors stay actionable.
    private(set) var lastOpenError: String?

    /// Automatic VR entry state for the Play tab (release 1.3.4, bug B). The 1.3.3 device run shows
    /// the user pressing "Enter VR" at +14 s while the automatic open was still waiting for the first
    /// game frame: the button must not be offered while the automatic attempt is expected to win.
    private(set) var autoOpenPending = false
    /// Human-readable automatic-open stage ("Waiting for the game picture…" -> "Entering VR…").
    private(set) var autoOpenStage = ""
    /// After a bounded wait the manual fallback is offered next to the status (a cold start took
    /// 14 s in 1.3.3; the automatic wait can legitimately take longer, but never indefinitely quiet).
    private(set) var autoOpenFallbackAvailable = false
    @ObservationIgnored private var autoOpenFallbackTask: Task<Void, Never>?

    private func beginAutoOpenPending() {
        autoOpenPending = true
        autoOpenStage = "Waiting for the game picture…"
        autoOpenFallbackAvailable = false
        autoOpenFallbackTask?.cancel()
        autoOpenFallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard let self, !Task.isCancelled, self.autoOpenPending else { return }
            self.autoOpenFallbackAvailable = true
            self.shellLogSafe("auto open still pending after 25 s; offering the manual Enter VR fallback")
        }
    }

    private func clearAutoOpenPending() {
        autoOpenPending = false
        autoOpenStage = ""
        autoOpenFallbackAvailable = false
        autoOpenFallbackTask?.cancel()
        autoOpenFallbackTask = nil
    }

    /// Advances the pending stage; ignored once the automatic attempt was superseded/cleared.
    private func setAutoOpenStage(_ stage: String) {
        guard autoOpenPending else { return }
        autoOpenStage = stage
    }

    /// Manual "Enter VR" (staged immersive entry): open the immersive space on demand, independent of
    /// the game/JIT path, so the CompositorServices renderer can be validated on its own. The automatic
    /// path (after the game starts, i.e. after JIT readiness) stays enabled; this button is also the
    /// recovery path when the automatic open fails.
    func enterVRManually() {
        shellLog("MANUAL: Enter VR pressed (immersive=\(immersiveOpen) opening=\(opening) appActive=\(appActive) windowActive=\(windowSceneActive) presenting=\(presenting))")
        // A deliberate press supersedes the automatic attempt; the UI shows the manual path from here.
        clearAutoOpenPending()
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
        observe(Notification.Name("VRMCGameStopped")) { coordinator, event in
            coordinator.gameDidStop(reason: event.reason ?? "unknown")
        }
        observe(Notification.Name("VRMCImmersiveEnded")) { coordinator, event in
            coordinator.compositorDidEnd(generation: event.generation)
        }
        observe(Notification.Name("VRMCCompositorRunning")) { coordinator, event in
            coordinator.compositorDidStartPresenting(generation: event.generation)
        }
        observe(UIApplication.willResignActiveNotification) { $0.willResignActive() }
        observe(UIApplication.didEnterBackgroundNotification) { $0.didEnterBackground() }
        observe(UIApplication.didBecomeActiveNotification) { $0.appDidBecomeActive() }
        observe(UIApplication.didFinishLaunchingNotification) { $0.refreshActivityStates("didFinishLaunching") }
        observe(UIScene.didActivateNotification) {
            $0.refreshActivityStates("UIScene.didActivate")
            $0.noteWindowSceneActivation()
        }
        observe(UIScene.willDeactivateNotification) { $0.refreshActivityStates("UIScene.willDeactivate") }
        observeSceneConnect(UIScene.willConnectNotification)
        observe(ProcessInfo.thermalStateDidChangeNotification) { $0.logThermal("thermal-state-changed") }
        refreshActivityStates("init")
        // Startup pass: the single-window guard also runs without waiting for a lifecycle callback
        // (covers a restored duplicate that never posts UIScene.didActivate).
        scheduleWindowScenePrune()
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

    /// Only the values the coordinator needs, so nothing non-Sendable crosses an isolation boundary.
    private struct ShellNotificationEvent: Sendable {
        var reason: String?
        var generation: Int32?
    }

    private func observe(_ name: Notification.Name,
                         _ handler: @escaping @MainActor @Sendable (ShellCoordinator) -> Void) {
        observe(name) { coordinator, _ in handler(coordinator) }
    }

    private func observe(_ name: Notification.Name,
                         _ handler: @escaping @MainActor @Sendable (ShellCoordinator, ShellNotificationEvent) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
            // The block runs on the main queue; extract Sendable values before hopping actors.
            let userInfo = note.userInfo
            let event = ShellNotificationEvent(
                reason: userInfo?["reason"] as? String,
                generation: (userInfo?["generation"] as? NSNumber)?.int32Value
            )
            Task { @MainActor in handler(ShellCoordinator.shared, event) }
        })
    }

    /// UIScene.willConnect carries the attaching scene in the notification object, which the generic
    /// observers drop. The scene guard only needs to know that a window scene may be attaching; the
    /// prune inspects UIApplication.shared.connectedScenes itself (nothing non-Sendable crosses into
    /// the main-actor task).
    private func observeSceneConnect(_ name: Notification.Name) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in ShellCoordinator.shared.noteWindowSceneConnect() }
        })
    }

    /// Called from the App body so the coordinator always holds the current environment actions.
    func bind(open: OpenImmersiveSpaceAction, dismiss: DismissImmersiveSpaceAction) {
        openAction = open
        dismissAction = dismiss
    }

    // MARK: - Activity state

    /// Every connected window scene. Only .windowApplication scenes are the shell's 2D window(s);
    /// CPSceneSessionRoleImmersiveSpaceApplication is the immersive space and must never be pruned
    /// or parked.
    private func connectedWindowScenes() -> [UIWindowScene] {
        UIApplication.shared.connectedScenes.compactMap { scene in
            guard scene.session.role == .windowApplication else { return nil }
            return scene as? UIWindowScene
        }
    }

    /// Compact window listing for the logs. The 1.3.3 device run had 8 restored scenes / 16 windows
    /// and every state line repeated the whole list (making logs unreadable and huge); cap the
    /// detailed part at two scenes with two windows each and keep the totals.
    private func windowStateDescription() -> String {
        let scenes = connectedWindowScenes()
        let windowCount = scenes.reduce(0) { $0 + $1.windows.count }
        var parts: [String] = []
        for scene in scenes.prefix(2) {
            var desc = "scene(\(scene.windows.count))"
            for (index, window) in scene.windows.prefix(2).enumerated() {
                desc += String(format: " w%d[hidden=%@ alpha=%.2f level=%.1f]",
                               index, window.isHidden ? "true" : "false",
                               window.alpha, window.windowLevel.rawValue)
            }
            if scene.windows.count > 2 { desc += " +\(scene.windows.count - 2) more windows" }
            parts.append(desc)
        }
        if scenes.count > 2 { parts.append("+\(scenes.count - 2) more scenes") }
        guard !parts.isEmpty else { return "windows=no-window-scenes" }
        return "windows=" + parts.joined(separator: " ")
            + " (total \(scenes.count) scenes/\(windowCount) windows)"
    }

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
        let scenes = UIApplication.shared.connectedScenes
        var parts: [String] = []
        for scene in scenes.prefix(2) {
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
        if scenes.count > 2 { parts.append("+\(scenes.count - 2) more scenes") }
        return parts.joined(separator: ",")
    }

    // MARK: - Single window scene guard (release 1.3.4, bug A)

    /// The 1.3.3 device run restored EIGHT .windowApplication scenes: the app plist allows multiple
    /// scenes and every window session left behind by earlier launches is restored and reconnected,
    /// each one mounting its own RootView (8 duplicate UIs, 16 windows, log lines repeating the whole
    /// scene list). The guard keeps exactly one window scene and destroys the extras through the
    /// public requestSceneSessionDestruction API. The immersive space is a separate scene role
    /// (CPSceneSessionRoleImmersiveSpaceApplication) and is never touched - the shipped plist must
    /// keep UIApplicationSupportsMultipleScenes=true for it.
    @ObservationIgnored private var primaryWindowClaimed = false
    @ObservationIgnored private var primaryWindowScene: UIWindowScene?
    @ObservationIgnored private var firstActivatedWindowScene: UIWindowScene?
    @ObservationIgnored private var windowScenePruneTask: Task<Void, Never>?
    @ObservationIgnored private var windowScenePruneAttempts = 0
    @ObservationIgnored private var windowScenePruneInFlight = false

    /// Called once by the first RootView to appear: it owns the single UI (hidden launcher host and
    /// the setup refresh loop). Later restored scenes still render but stay inert until the guard
    /// prunes them, so the user always has one working window.
    func claimPrimaryWindow() -> Bool {
        guard !primaryWindowClaimed else { return false }
        primaryWindowClaimed = true
        return true
    }

    /// The primary RootView's window scene (reported by a 0x0 UIViewRepresentable probe). The guard
    /// keeps this scene, so the survivor is the one that actually owns the UI/launcher host, never a
    /// restored duplicate. Ignored once a scene has been recorded.
    func notePrimaryWindowScene(_ scene: UIWindowScene) {
        guard primaryWindowClaimed, primaryWindowScene == nil else { return }
        primaryWindowScene = scene
        shellLog("window-scene guard: primary window scene id=\(scene.session.persistentIdentifier.prefix(8)) connected=\(connectedWindowScenes().count)")
        scheduleWindowScenePrune()
    }

    /// A UIScene.willConnect notification: re-arm the debounced prune. Never prune synchronously from
    /// a lifecycle callback - the launch restore burst connects several scenes in a row.
    private func noteWindowSceneConnect() {
        scheduleWindowScenePrune()
    }

    private func noteWindowSceneActivation() {
        let scenes = connectedWindowScenes()
        if firstActivatedWindowScene == nil,
           let scene = scenes.first(where: { $0.activationState == .foregroundActive }) {
            firstActivatedWindowScene = scene
        }
        scheduleWindowScenePrune()
    }

    /// One debounced pass at a time: wait for the restore burst to settle, then prune. Destruction is
    /// asynchronous, so a single verification pass follows; later activations trigger further passes
    /// instead of a tight loop.
    private func scheduleWindowScenePrune() {
        guard windowScenePruneTask == nil, !windowScenePruneInFlight else { return }
        windowScenePruneTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.windowScenePruneTask = nil
            self.pruneExtraWindowScenes()
        }
    }

    private func choosePrimaryWindowScene(_ scenes: [UIWindowScene]) -> UIWindowScene? {
        if let claimed = primaryWindowScene, scenes.contains(where: { $0 === claimed }) { return claimed }
        if let key = scenes.first(where: { $0.windows.contains(where: { $0.isKeyWindow }) }) { return key }
        if let first = firstActivatedWindowScene, scenes.contains(where: { $0 === first }) { return first }
        return scenes.first
    }

    private func pruneExtraWindowScenes() {
        let scenes = connectedWindowScenes()
        guard scenes.count > 1, let keeper = choosePrimaryWindowScene(scenes) else { return }
        // Never restructure scenes while the immersive session is live; re-check after it ends.
        guard !immersiveOpen, !presenting else {
            shellLog("window-scene guard: deferred while immersive is open/presenting (windowScenes=\(scenes.count))")
            deferWindowScenePrune(after: 3)
            return
        }
        guard appActive else {
            shellLog("window-scene guard: deferred until the app is active (windowScenes=\(scenes.count))")
            deferWindowScenePrune(after: 2)
            return
        }
        windowScenePruneAttempts += 1
        let keeperID = keeper.session.persistentIdentifier
        var requested = 0
        for scene in scenes where scene !== keeper {
            let session = scene.session
            // Belt and braces: only .windowApplication scenes are duplicates of our 2D UI.
            guard session.role == .windowApplication else { continue }
            requested += 1
            let id = session.persistentIdentifier
            shellLog("window-scene guard: destroying duplicate window scene id=\(id.prefix(8)) windows=\(scene.windows.count)")
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { error in
                shellLog("window-scene guard: destruction of scene id=\(id.prefix(8)) failed (ignored): \(error.localizedDescription)")
            }
        }
        shellLog("window-scene guard: keeping session \(keeperID.prefix(8)), destroying \(requested) duplicate window scene(s) (before=\(scenes.count), after-request=\(scenes.count - requested), attempt=\(windowScenePruneAttempts))")
        scheduleWindowScenePruneVerification()
    }

    private func deferWindowScenePrune(after seconds: Int) {
        windowScenePruneInFlight = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self else { return }
            self.windowScenePruneInFlight = false
            self.scheduleWindowScenePrune()
        }
    }

    private func scheduleWindowScenePruneVerification() {
        guard windowScenePruneAttempts < 3 else { return }
        windowScenePruneInFlight = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            self.windowScenePruneInFlight = false
            let remaining = self.connectedWindowScenes().count
            if remaining > 1 {
                shellLog("window-scene guard: \(remaining) window scene(s) still connected after the prune attempt; retrying once")
            }
            self.scheduleWindowScenePrune()
        }
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
        writeSessionState("running")
        statusMessage = "Starting Minecraft…"
        // Automatic VR entry is the expected path, but it waits for the provider's first game frame
        // (14 s in the 1.3.3 cold start, up to 90 s by design). Publish that state so the Play tab can
        // show progress instead of inviting a manual "Enter VR" press while the auto attempt runs.
        clearAutoOpenPending()
        if !safeMode { beginAutoOpenPending() }
        gameOpenTask?.cancel()
        gameOpenTask = Task { [weak self] in
            // Open the immersive space when the game has a picture to show. The old fixed 15 s wait
            // was too long on a warm start and too short on a cold one (the space then opened onto
            // an empty scene). Minimum 3 s so the provider/renderer exist; give up waiting after
            // 90 s and open anyway so a slow start still ends up in VR.
            try? await Task.sleep(for: .seconds(3))
            var waited = 3.0
            while !Task.isCancelled, waited < 90.0 {
                if VRMCCompositor_ProviderEyesReady() != 0 { break }
                try? await Task.sleep(for: .milliseconds(500))
                waited += 0.5
            }
            guard let self, !Task.isCancelled, self.gameStarted else { return }
            self.setAutoOpenStage("Entering VR…")
            self.shellLogSafe("game frame \(VRMCCompositor_ProviderEyesReady() != 0 ? "ready" : "NOT ready") after \(String(format: "%.1f", waited)) s; opening immersive space")
            self.openVR(reason: "auto")
        }
    }

    /// One-word session marker used by the crash guard at the next launch: "running" while a game
    /// is up, "background" once the app left the foreground, "ended" after a normal game stop.
    private func writeSessionState(_ state: String) {
        let url = shellDocumentsURL().appendingPathComponent("vrmc-session-state.txt")
        try? state.write(to: url, atomically: true, encoding: .utf8)
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
                    self.statusMessage = "Playing in VR"
                }
            }
        }
    }

    // MARK: - M6 crash guard

    private func crashCountURL() -> URL {
        shellDocumentsURL().appendingPathComponent("vrmc-crash-count.txt")
    }

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
                    // No clean provider teardown. That is the normal result of closing the app from
                    // the system while the game runs (the only way to quit on the headset), so it
                    // only counts as a crash when the app was still in the foreground with a game
                    // running when the process died.
                    let stateURL = docs.appendingPathComponent("vrmc-session-state.txt")
                    let state = (try? String(contentsOf: stateURL, encoding: .utf8))?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "running"
                    if state == "running" {
                        unclean = true
                        count += 1
                    } else {
                        shellLog("CRASH-GUARD: previous session ended without teardown while state=\(state); treated as a normal quit")
                        count = 0
                    }
                }
            }
        }
        try? FileManager.default.removeItem(at: docs.appendingPathComponent("vrmc-session-state.txt"))
        try? String(count).write(to: countURL, atomically: true, encoding: .utf8)
        if unclean {
            crashGuardMessage = count >= 2
                ? "The last two sessions ended unexpectedly. VR will not open by itself until you clear safe mode."
                : "The last session ended unexpectedly."
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
        statusMessage = "Playing in VR"
        lastOpenError = nil
        clearAutoOpenPending()
        // The auto-retry after a layer that dies right after opening compares generations. The open
        // request happens before the compositor thread exists (generation 0), so the real generation is
        // only known here, at the first presented frame.
        lastOpenGeneration = VRMCCompositor_CurrentGeneration()
        lastPresentedGeneration = lastOpenGeneration
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
        gameOpenTask?.cancel(); gameOpenTask = nil
        clearAutoOpenPending()
        gameStarted = false
        writeSessionState("ended")
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
        statusMessage = "Game ended"
        setGameWindowsVisible(true, log: "window restored after game stop")
        Task { [weak self] in
            guard let self else { return }
            if await self.dismissIfCurrent(myEpoch: myEpoch) {
                self.shellLogSafe("immersive space dismissed after game stop epoch=\(myEpoch)")
            }
        }
    }

    private func compositorDidEnd(generation: Int32?) {
        let current = VRMCCompositor_CurrentGeneration()
        let generationText = generation.map(String.init) ?? "nil"
        // gameDidStop() clears `presenting` before this notification arrives (teardown requests the
        // compositor stop first), so "did this session ever present?" comes from the snapshot taken
        // at the first presented frame, not from the already-reset presentation flag.
        let hadPresentedFrame = presenting || (generation != nil && generation == lastPresentedGeneration)
        shellLog("VRMCImmersiveEnded generation=\(generationText) current=\(current) presenting=\(presenting) hadPresentedFrame=\(hadPresentedFrame) \(windowStateDescription())")
        // A session that ended after a newer one was opened must not close the newer one.
        if let generation, generation != current {
            shellLog("ignoring stale generation=\(generation) current=\(current)")
            return
        }
        epoch += 1
        let myEpoch = epoch
        presenting = false
        statusMessage = gameStarted ? "VR paused — game still running" : "VR ended"
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
            // dismiss so a later openImmersiveSpace is not rejected. Log only a dismissal that this
            // path actually performed (game stop may have dismissed it a moment earlier).
            if await self.dismissIfCurrent(myEpoch: myEpoch) {
                self.shellLogSafe("immersive space dismissed epoch=\(myEpoch)")
            }
            if self.epoch != myEpoch { return }
            if shouldAutoRetry {
                try? await Task.sleep(for: .seconds(2))
                if self.epoch != myEpoch { return }
                let wantsReopen = self.gameStarted || self.selftestMode || self.openOnLaunch || self.wantsImmersive
                if wantsReopen && !self.immersiveOpen && self.appActive {
                    self.openVR(reason: "auto-retry")
                }
            } else if self.reopenOnActive && self.appActive && !self.immersiveOpen {
                self.openVR(reason: "ended-while-active")
            }
        }
    }

    /// Dismisses the immersive space when this task is still the current epoch and a dismiss is
    /// pending. Returns true only when a dismiss call was actually made, so the two teardown paths
    /// (game stop and compositor end) do not both log "immersive space dismissed" for one dismissal.
    @discardableResult
    private func dismissIfCurrent(myEpoch: Int) async -> Bool {
        guard epoch == myEpoch, needsDismiss else { return false }
        guard let dismissAction else {
            if epoch == myEpoch { needsDismiss = false }
            return false
        }
        await dismissAction()
        if epoch == myEpoch { needsDismiss = false }
        return true
    }

    private func stopForBackground(_ reason: String) {
        resignGraceTask?.cancel()
        resignGraceTask = nil
        shellLog("\(reason) gameStarted=\(gameStarted) immersive=\(immersiveOpen) presenting=\(presenting) \(windowStateDescription())")
        appActive = false
        windowSceneActive = false
        // Backgrounding cancels the pending automatic open (the reopen-on-activation path takes over).
        clearAutoOpenPending()
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
        if gameStarted { writeSessionState("background") }
        stopForBackground("didEnterBackground")
    }

    private func appDidBecomeActive() {
        if resignGraceTask != nil {
            resignGraceTask?.cancel()
            resignGraceTask = nil
            shellLog("willResignActive cancelled by didBecomeActive (compositor not stopped, grace 1.8 s)")
        }
        appActive = true
        if gameStarted { writeSessionState("running") }
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
            statusMessage = "Safe mode: tap Enter VR to continue"
            clearAutoOpenPending()
            return
        }
        guard let openAction else {
            shellLog("\(reason): openImmersiveSpace action not bound yet")
            if reason == "auto" {
                clearAutoOpenPending()
                lastOpenError = "VR is not available yet. Tap Enter VR to retry."
                statusMessage = "VR unavailable"
            }
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
                // The deferred case is a real outcome: stop showing "auto open pending" and let the
                // fallback button come back (the automatic retry still happens on the next activation).
                if reason == "auto" { self.clearAutoOpenPending() }
                return
            }
            // Give the scene time to finish activating/transitioning; auto/selftest run immediately.
            if reason != "auto" && reason != "selftest" {
                try? await Task.sleep(for: .seconds(2))
            }
            if self.epoch != startEpoch {
                self.shellLogSafe("\(reason): aborted before open (epoch changed)")
                if reason == "auto" { self.clearAutoOpenPending() }
                return
            }
            // A previous space may still be registered with SwiftUI; dismiss it first and settle.
            if self.needsDismiss {
                if let dismissAction = self.dismissAction { await dismissAction() }
                if self.epoch != startEpoch {
                    self.shellLogSafe("\(reason): aborted after dismiss (epoch changed)")
                    if reason == "auto" { self.clearAutoOpenPending() }
                    return
                }
                self.needsDismiss = false
                try? await Task.sleep(for: .milliseconds(500))
            }
            for attempt in 1...4 {
                if self.epoch != startEpoch {
                    self.shellLogSafe("\(reason): aborted attempt \(attempt) (epoch changed)")
                    if reason == "auto" { self.clearAutoOpenPending() }
                    return
                }
                guard self.appActive, self.windowSceneActive else {
                    self.shellLogSafe("\(reason): app no longer foreground-active; deferring open")
                    if reason == "auto" { self.clearAutoOpenPending() }
                    return
                }
                let result = await openAction(id: "vr")
                self.shellLogSafe("\(reason) attempt \(attempt) openImmersiveSpace result=\(result) epoch=\(self.epoch) \(self.windowStateDescription())")
                if case .opened = result {
                    self.opening = false
                    self.clearAutoOpenPending()
                    self.immersiveOpen = true
                    self.wantsImmersive = true
                    self.presenting = false
                    self.statusMessage = "Entering VR…"
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
                    self.clearAutoOpenPending()
                    if reason == "manual" { self.lastOpenError = "Immersive space open was cancelled by the system." }
                    return
                }
                // An error usually means SwiftUI still considers a previous space open.
                if let dismissAction = self.dismissAction { await dismissAction() }
                self.needsDismiss = true
                try? await Task.sleep(for: .seconds(2))
            }
            if reason == "manual" || reason == "auto" || reason == "selftest" {
                self.clearAutoOpenPending()
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

    func shellLogSafe(_ message: String) {
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
            RootView(shell: shell)
        }
        .defaultSize(width: 1180, height: 780)
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
