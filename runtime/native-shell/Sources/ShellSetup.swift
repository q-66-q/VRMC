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
///
/// The launcher is never a second UI: `LauncherHostView` keeps its one view controller loaded in a
/// hidden in-window host (or in the user-requested Minecraft setup sheet), and pressing Play drives
/// the launcher's own Play button from there.
@MainActor
enum LauncherBridge {
    private static var cachedController: UIViewController?

    /// The one launcher view controller of this process. It is created once and reused by the hidden
    /// Play host and the Minecraft setup sheet, so both always talk to the same instance.
    static func launcherController() -> UIViewController {
        if let cachedController {
            // Another host site may have owned it; detach the single instance from its old parent
            // before it is attached to a new container.
            if cachedController.parent != nil {
                cachedController.willMove(toParent: nil)
                cachedController.view.removeFromSuperview()
                cachedController.removeFromParent()
            }
            cachedController.loadViewIfNeeded()
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
        // Loading the view now builds the launcher's navigation controller and its Play button even
        // while the host is still the hidden in-window view.
        controller.loadViewIfNeeded()
        return controller
    }

    /// Attach the single launcher view controller to a SwiftUI-owned host container.
    ///
    /// The launcher is deliberately NOT the SwiftUI representable itself: a UIViewController can only
    /// have one parent, and the hidden Play host and the setup sheet must be able to come and go
    /// without one teardown pulling the launcher out of the other.
    static func attachLauncher(to container: UIViewController) {
        let containerView: UIView = container.view
        if let cachedController, cachedController.parent === container {
            cachedController.view.frame = containerView.bounds
            return
        }
        let controller = launcherController()
        container.addChild(controller)
        controller.view.frame = containerView.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.addSubview(controller.view)
        controller.didMove(toParent: container)
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

    /// Press the launcher's own Play button, exactly as a tap would (same enabled state, same
    /// install/JIT/download flow). Returns false while the launcher is still loading its versions or
    /// accounts, so callers retry instead of sending the user to a second UI.
    ///
    /// The launcher lives in a hidden host that is in the window, so "the view is loaded and the
    /// button is enabled" is the real precondition here. Requiring `view.window != nil` as well made
    /// the hidden path fragile while the window is being parked for VR.
    @discardableResult
    static func pressPlay() -> Bool {
        guard let (owner, button) = playButton() else {
            shellLog("launcher play: button not available yet")
            return false
        }
        guard owner.viewIfLoaded != nil else {
            shellLog("launcher play: launcher view not loaded yet")
            return false
        }
        guard button.isEnabled else {
            shellLog("launcher play: button still disabled (launcher loading or setup incomplete)")
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
        // Last resort: the launcher's own game-start method. It skips the install/JIT pre-flight, so
        // it is only used when the documented button action is not present in this build.
        let launch = NSSelectorFromString("launchMinecraft:")
        if owner.responds(to: launch) {
            owner.perform(launch, with: nil)
            shellLog("launcher play: invoked launchMinecraft: directly")
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
    /// True while more than one Vivecraft jar is installed. Fabric refuses to start with two copies,
    /// so Play must stay disabled even though inspectVivecraft() reports the jar as "attention"
    /// (an untested *single* build is still allowed to play).
    private(set) var vivecraftDuplicate = false

    /// Play is gated only on what automatic setup owns and can verify itself (the bundled VRMC mod
    /// and the Vivecraft jar). The launcher owns the Fabric profile, the account and JIT, and its own
    /// Play button already reflects those, so an unreadable/stale launcher file can never dead-end
    /// our Play button while the game is in fact launchable.
    var readyToPlay: Bool {
        provider.isReady && vivecraftUsable && !vivecraftDuplicate
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

    // MARK: Minimal zip reader (import validation)

    /// Lists a zip's central-directory entry names. A jar is a zip; the import path uses this to
    /// prove the picked file is a readable zip and really contains fabric.mod.json instead of only
    /// checking the first four magic bytes and the size (REVIEW_1.3 R10). Returns nil when the file
    /// is not a readable zip.
    nonisolated static func zipEntryNames(of url: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd(), fileSize > 22 else { return nil }
        let tailLength = Int(min(fileSize, 65_557))
        guard let tail = readBytes(from: handle, offset: Int64(fileSize) - Int64(tailLength), count: tailLength),
              let eocd = lastIndex(of: [0x50, 0x4B, 0x05, 0x06], in: tail) else { return nil }
        let entryCount = Int(u16(tail, eocd + 10))
        let directorySize = Int(u32(tail, eocd + 12))
        let directoryOffset = Int64(u32(tail, eocd + 16))
        guard entryCount > 0, entryCount <= 20_000, directorySize > 0, directorySize <= 16 * 1024 * 1024,
              let directory = readBytes(from: handle, offset: directoryOffset, count: directorySize) else {
            return nil
        }
        var names: [String] = []
        var offset = 0
        for _ in 0..<entryCount {
            guard offset + 46 <= directory.count, u32(directory, offset) == 0x0201_4B50 else { return nil }
            let nameLength = Int(u16(directory, offset + 28))
            let extraLength = Int(u16(directory, offset + 30))
            let commentLength = Int(u16(directory, offset + 32))
            let nameStart = offset + 46
            guard nameStart + nameLength <= directory.count else { return nil }
            let nameStartIndex = directory.startIndex + nameStart
            let nameEndIndex = nameStartIndex + nameLength
            names.append(String(decoding: directory[nameStartIndex..<nameEndIndex], as: UTF8.self))
            offset = nameStart + nameLength + extraLength + commentLength
        }
        return names
    }

    nonisolated private static func readBytes(from handle: FileHandle, offset: Int64, count: Int) -> Data? {
        guard count > 0, offset >= 0 else { return Data() }
        do {
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: count)
        } catch {
            return nil
        }
    }

    nonisolated private static func u16(_ data: Data, _ index: Int) -> UInt16 {
        UInt16(data[data.startIndex + index]) | (UInt16(data[data.startIndex + index + 1]) << 8)
    }

    nonisolated private static func u32(_ data: Data, _ index: Int) -> UInt32 {
        UInt32(data[data.startIndex + index])
            | (UInt32(data[data.startIndex + index + 1]) << 8)
            | (UInt32(data[data.startIndex + index + 2]) << 16)
            | (UInt32(data[data.startIndex + index + 3]) << 24)
    }

    nonisolated private static func lastIndex(of needle: [UInt8], in data: Data) -> Int? {
        guard data.count >= needle.count else { return nil }
        var index = data.count - needle.count
        while index >= 0 {
            let start = data.startIndex + index
            if Array(data[start..<(start + needle.count)]) == needle { return index }
            index -= 1
        }
        return nil
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
            // A second Vivecraft jar is a hard "the game will not start" condition (Fabric refuses
            // duplicate mod ids), unlike an untested single build, which .attention still allows.
            let duplicate = Self.installedVivecraftJars().count > 1
            if vivecraftDuplicate != duplicate { vivecraftDuplicate = duplicate }
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
        // A failed automatic install must not become "ready" just because a file exists at the
        // install path: when this build bundles the provider, only the exact bundled hash counts as
        // installed (the same check installBundledProvider() makes). Covers a startup install that
        // failed after writing the file and a corrupted/partial jar dropped in by something else.
        if let bundled = bundledProviderURL(), let bundledHash = sha256(of: bundled),
           let installedHash = sha256(of: installed) {
            if installedHash == bundledHash {
                return .ready("Installed \(bundledHash.prefix(8))")
            }
            shellLog("setup: installed provider failed verification "
                + "(installed=\(installedHash.prefix(12)) expected=\(bundledHash.prefix(12)))")
            return .missing("The VRMC mod failed verification. Reinstall it.")
        }
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
    /// Main-actor-only (refresh/install call it on the main actor); the 1.3 download task wrote a
    /// nonisolated(unsafe) version of this cache from the background while refresh() read it.
    private static var vivecraftHashCache: (key: String, hash: String)?

    private static func inspectVivecraft() -> SetupStatus {
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
            return .missing("No game profile yet. Open Minecraft setup to install Fabric for Minecraft \(minecraftVersion).")
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
            return .attention("Select the profile “\(other)” in Minecraft setup (currently “\(selected)”).")
        }
        return .missing("In Minecraft setup, install Fabric for Minecraft \(minecraftVersion) and select that profile.")
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
        return .missing("Sign in with your Minecraft account in Minecraft setup.")
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
                Self.vivecraftHashCache = nil
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

    /// Buffered streamed download progress. URLSession hands us whole Data chunks: each chunk is
    /// appended straight to the destination file and progress is computed once per chunk. The 1.3
    /// path iterated AsyncBytes one byte at a time (~6.7 M async hops for a 6.7 MB jar), which made
    /// the download slower than the network on device.
    private final class DownloadProgressDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let handle: FileHandle
        private let expectedBytes: Int64
        private let progress: @Sendable (Double) -> Void
        private let lock = NSLock()
        private var received: Int64 = 0
        private var failure: SetupError?
        private var continuation: CheckedContinuation<Result<Void, SetupError>, Never>?

        init(handle: FileHandle, expectedBytes: Int, progress: @escaping @Sendable (Double) -> Void) {
            self.handle = handle
            self.expectedBytes = Int64(expectedBytes)
            self.progress = progress
        }

        /// Runs the download to completion. The session is created per download and invalidated when
        /// the task completes.
        func run(_ request: URLRequest) async -> Result<Void, SetupError> {
            await withCheckedContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 60
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                session.dataTask(with: request).resume()
            }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                lock.lock()
                if failure == nil {
                    failure = SetupError(message: "Download failed (HTTP \(http.statusCode)). Check the connection, or import the jar from Files.")
                }
                lock.unlock()
                completionHandler(.cancel)
                return
            }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            let failed = failure != nil
            lock.unlock()
            guard !failed else { return }
            do {
                try handle.write(contentsOf: data)
            } catch {
                lock.lock()
                if failure == nil { failure = SetupError(message: "Download failed: \(error.localizedDescription)") }
                lock.unlock()
                dataTask.cancel()
                return
            }
            lock.lock()
            received += Int64(data.count)
            let soFar = received
            if soFar > expectedBytes * 2, failure == nil {
                failure = SetupError(message: "Download rejected: the file is larger than expected.")
            }
            lock.unlock()
            progress(min(1.0, Double(soFar) / Double(expectedBytes)))
            if soFar > expectedBytes * 2 { dataTask.cancel() }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            session.finishTasksAndInvalidate()
            lock.lock()
            guard let continuation else { lock.unlock(); return }
            self.continuation = nil
            let failure = self.failure
            lock.unlock()
            if let failure {
                continuation.resume(returning: .failure(failure))
            } else if let error {
                continuation.resume(returning: .failure(SetupError(message: "Download failed: \(error.localizedDescription)")))
            } else {
                continuation.resume(returning: .success(()))
            }
        }
    }

    nonisolated private static func fetchVivecraft(progress: @escaping @Sendable (Double) -> Void) async -> Result<Void, SetupError> {
        var request = URLRequest(url: vivecraftURL)
        request.timeoutInterval = 60
        // Modrinth asks automated clients to identify themselves; a generic product token only.
        request.setValue("VRMC/1.3 (visionOS sideload)", forHTTPHeaderField: "User-Agent")
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vivecraft-\(UUID().uuidString).jar")
        defer { try? FileManager.default.removeItem(at: temp) }
        FileManager.default.createFile(atPath: temp.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: temp) else {
            return .failure(SetupError(message: "Download failed: could not create the destination file."))
        }
        let delegate = DownloadProgressDelegate(handle: handle, expectedBytes: vivecraftBytes, progress: progress)
        let result = await delegate.run(request)
        try? handle.close()
        if case .failure(let error) = result { return .failure(error) }
        guard let hash = sha256(of: temp), hash == vivecraftSHA256 else {
            return .failure(SetupError(message: "Download rejected: the file does not match the expected checksum. Nothing was installed."))
        }
        return installVivecraft(from: temp, as: vivecraftFileName)
    }

    /// Put one Vivecraft jar into mods/ and remove every other Vivecraft jar (Fabric refuses to
    /// start with two copies of the same mod). The old jar(s) are moved aside, not deleted, and are
    /// restored if the final move/verification fails, so a failed install never loses a working mod.
    nonisolated private static func installVivecraft(from source: URL, as name: String) -> Result<Void, SetupError> {
        let fm = FileManager.default
        let mods = modsDirectory()
        let destination = mods.appendingPathComponent(name)
        var staged: URL?
        var backups: [(backup: URL, original: URL)] = []
        do {
            guard let sourceHash = sha256(of: source) else {
                return .failure(SetupError(message: "Could not read the Vivecraft jar."))
            }
            try fm.createDirectory(at: mods, withIntermediateDirectories: true)
            let staging = mods.appendingPathComponent(".vivecraft.jar.tmp")
            try? fm.removeItem(at: staging)
            try fm.copyItem(at: source, to: staging)
            staged = staging
            // Move existing jars aside first; do not delete them before the new jar is in place.
            for (index, old) in installedVivecraftJars().enumerated() {
                let backup = mods.appendingPathComponent(".\(old.lastPathComponent).bak\(index)")
                try? fm.removeItem(at: backup)
                try fm.moveItem(at: old, to: backup)
                backups.append((backup, old))
            }
            try fm.moveItem(at: staging, to: destination)
            staged = nil
            guard sha256(of: destination) == sourceHash else {
                throw SetupError(message: "the installed jar failed verification")
            }
            for entry in backups { try? fm.removeItem(at: entry.backup) }
            return .success(())
        } catch {
            if let staged { try? fm.removeItem(at: staged) }
            try? fm.removeItem(at: destination)
            var restored = 0
            for entry in backups.reversed() {
                if (try? fm.moveItem(at: entry.backup, to: entry.original)) != nil { restored += 1 }
            }
            shellLog("setup: Vivecraft install FAILED (\(error)); restored \(restored) previous jar(s)")
            let message = "Could not install Vivecraft: \(error.localizedDescription)."
                + (restored > 0 ? " The previous mod was restored." : "")
            return .failure(SetupError(message: message))
        }
    }

    /// Install a Vivecraft jar the user picked in Files. Honest validation: the file must be a
    /// readable zip whose central directory contains fabric.mod.json (a real Fabric mod), and only a
    /// byte-identical copy of the pinned build is called the tested build - imports are not
    /// SHA-verified (only the one-tap download is). Other Vivecraft jars install as "untested".
    func importVivecraft(from picked: URL) {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let name = picked.lastPathComponent
        guard picked.pathExtension.lowercased() == "jar", name.lowercased().hasPrefix("vivecraft") else {
            lastActionMessage = "That is not a Vivecraft jar (expected a file named vivecraft-….jar)."
            return
        }
        let size = ((try? picked.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
        guard size > 100_000, size < 64_000_000 else {
            lastActionMessage = "That file does not look like Vivecraft (unexpected size)."
            return
        }
        guard let entries = Self.zipEntryNames(of: picked) else {
            lastActionMessage = "That file is not a readable jar (damaged or not a zip file)."
            shellLog("setup: Vivecraft import rejected: not a readable zip")
            return
        }
        guard entries.contains(where: { $0 == "fabric.mod.json" || $0.hasSuffix("/fabric.mod.json") }) else {
            lastActionMessage = "That jar is not a Fabric mod (it has no fabric.mod.json)."
            shellLog("setup: Vivecraft import rejected: no fabric.mod.json among \(entries.count) zip entries")
            return
        }
        let pinned = Self.sha256(of: picked) == Self.vivecraftSHA256
        switch Self.installVivecraft(from: picked, as: pinned ? Self.vivecraftFileName : name) {
        case .success:
            Self.vivecraftHashCache = nil
            lastActionMessage = pinned
                ? "Vivecraft \(Self.vivecraftVersion) imported (this is the tested build)."
                : "\(name) imported. It is not the tested build."
            shellLog("setup: Vivecraft imported pinned=\(pinned) zipEntries=\(entries.count)")
        case .failure(let error):
            lastActionMessage = error.message
            shellLog("setup: Vivecraft import FAILED: \(error.message)")
        }
        refresh()
    }
}
