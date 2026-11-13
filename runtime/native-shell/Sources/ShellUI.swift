import SwiftUI
import UIKit
import UniformTypeIdentifiers

// VRMC window UI (release 1.3): a standard visionOS app window — glass, a tab bar ornament, system
// controls and SF Symbols — instead of the developer overlay that sat on top of the launcher.
//
//   Play      first-run setup checklist, the Play button and in-game actions
//   Comfort   play style, turning, vignette, height, world scale, performance
//   Controls  gesture reference and hand sensitivity
//   Help      session status, recovery, diagnostics export
//
// One UI only: pressing Play never switches to the launcher's own screens. A single launcher view
// controller stays mounted in a hidden 1×1 pt host inside this window, so LauncherBridge can press
// the launcher's own Play button (which owns the install/JIT/launch flow) with no second UI shown.
// The launcher screens become visible only when the user deliberately opens "Minecraft setup" from
// the Play setup card or Help, never automatically.
//
// Settings are written to the same files the provider reads (vrmc-runtime.properties,
// vrmc-input-tune.properties, Documents/vrmc-vignette.flag). While a game runs, saving also asks
// the game to reload them, so changes apply without restarting.

enum ShellTab: Hashable {
    case play, mods, comfort, controls, help
}

struct RootView: View {
    @Bindable var shell: ShellCoordinator
    @State private var tab: ShellTab = .play
    @State private var setup = SetupManager.shared
    /// The launcher's own screens, shown only when the user asks for them (sign-in, Fabric, JIT).
    @State private var launcherSetupPresented = false
    /// The hidden host owns the single launcher controller except while the setup sheet is on screen.
    /// It is switched off before the sheet is presented and back on only after the sheet is gone, so
    /// the two hosts never contest the one controller while the cover animates.
    @State private var launcherHostActive = true
    /// Exactly one RootView instance (the primary window scene) owns the hidden launcher host and the
    /// setup refresh loop. Restored duplicate scenes still render the normal UI - so the window the
    /// guard keeps is never blank - but stay inert until the window-scene guard destroys the extras.
    @State private var isPrimaryWindow = false
    @State private var didClaimWindow = false

    var body: some View {
        TabView(selection: $tab) {
            PlayView(shell: shell, setup: setup, presentLauncherSetup: presentLauncherSetup)
                .tabItem { Label("Play", systemImage: "play.circle") }
                .tag(ShellTab.play)
            ModsView(shell: shell)
                .tabItem { Label("Mods", systemImage: "shippingbox") }
                .tag(ShellTab.mods)
            ComfortView(shell: shell)
                .tabItem { Label("Comfort", systemImage: "figure.seated.side") }
                .tag(ShellTab.comfort)
            ControlsView(shell: shell)
                .tabItem { Label("Controls", systemImage: "hand.raised") }
                .tag(ShellTab.controls)
            HelpView(shell: shell, setup: setup, presentLauncherSetup: presentLauncherSetup)
                .tabItem { Label("Help", systemImage: "lifepreserver") }
                .tag(ShellTab.help)
        }
        .overlay(alignment: .topLeading) { if isPrimaryWindow { hiddenLauncherHost } }
        .overlay(alignment: .topLeading) { if isPrimaryWindow { primaryWindowProbe } }
        .fullScreenCover(isPresented: $launcherSetupPresented, onDismiss: {
            // The sheet has finished dismissing: hand the launcher back to the hidden in-window host.
            launcherHostActive = true
        }) {
            LauncherSetupSheet { launcherSetupPresented = false }
        }
        .onChange(of: shell.gameRunning) { _, running in
            // The launcher started the game from the setup sheet: leave setup behind.
            if running { launcherSetupPresented = false }
        }
        .task(id: isPrimaryWindow) {
            // Only the primary window refreshes setup; duplicate restored scenes must not start loops.
            guard isPrimaryWindow else { return }
            setup.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                setup.refresh()
            }
        }
        .onAppear { claimWindow() }
    }

    /// 0x0 bridge that reports which UIWindowScene this RootView is hosted in. The coordinator keeps
    /// that scene in the single-window guard, so the survivor is the window showing this UI and
    /// owning the hidden launcher host.
    private var primaryWindowProbe: some View {
        WindowSceneProbe { scene in
            shell.notePrimaryWindowScene(scene)
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func claimWindow() {
        guard !didClaimWindow else { return }
        didClaimWindow = true
        if shell.claimPrimaryWindow() {
            isPrimaryWindow = true
            shellLog("window UI appeared (release 1.3.4, single UI, primary scene)")
        } else {
            // One line per suppressed duplicate; the window-scene guard destroys these scenes.
            shellLog("window UI appeared (duplicate restored scene; UI suppressed until the window-scene guard prunes it)")
        }
    }

    /// Deliberate setup entry points only: the Play setup card and Help call this. Play never does.
    private func presentLauncherSetup() {
        launcherHostActive = false
        launcherSetupPresented = true
    }

    /// The single launcher view controller, loaded and laid out inside the window but invisible and
    /// non-interactive: that is what lets LauncherBridge drive the launcher's own install/JIT/launch
    /// flow without showing a second UI. The setup sheet takes the same controller over while it is
    /// open, then hands it back here.
    private var hiddenLauncherHost: some View {
        // Laid out at the app window's default size so the launcher builds its normal (full-size)
        // view hierarchy, but fully transparent and non-interactive: nothing of it is ever shown.
        LauncherHostView(isActive: launcherHostActive)
            .frame(width: 1180, height: 780)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// 0×0 UIKit bridge that reports the UIWindowScene a SwiftUI root view is hosted in.
///
/// SwiftUI's app lifecycle has no scene delegate to ask, and the shell keeps exactly one window scene
/// (1.3.3 restored eight duplicate scenes). The first RootView reports its scene here; the
/// coordinator's window-scene guard keeps that scene and destroys the duplicate ones.
private struct WindowSceneProbe: UIViewRepresentable {
    final class ProbeView: UIView {
        var onScene: ((UIWindowScene) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        func report() {
            guard let scene = window?.windowScene else { return }
            onScene?(scene)
        }
    }

    let onScene: (UIWindowScene) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.onScene = onScene
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.onScene = onScene
        view.report()
    }
}

/// The Amethyst launcher's own screens, presented only when the user asks for them: Microsoft sign-in,
/// Fabric profile install and the JIT prompt live there. Play never opens this sheet.
private struct LauncherSetupSheet: View {
    let onDone: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LauncherHostView()
                .ignoresSafeArea()
            Button(action: onDone) {
                Label("Done", systemImage: "checkmark")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .padding(24)
            .accessibilityLabel("Close Minecraft setup")
            .accessibilityHint("Returns to VRMC")
        }
        .background(.regularMaterial)
    }
}

// MARK: - Shared pieces

/// Send one command to the running game (consumed by the provider within ~0.5 s).
@MainActor
func sendGameCommands(_ commands: [String]) {
    Task {
        for (index, command) in commands.enumerated() {
            if index > 0 { try? await Task.sleep(for: .milliseconds(1200)) }
            _ = shellQueueGameCommand(command)
        }
    }
}

private struct StatusRow: View {
    let title: String
    let systemImage: String
    let status: SetupStatus

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 32)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(status.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            statusIcon
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var statusIcon: some View {
        switch status {
        case .checking:
            ProgressView()
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .accessibilityLabel("Ready")
        case .attention:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.yellow)
                .accessibilityLabel("Needs attention")
        case .missing:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                .accessibilityLabel("Missing")
        }
    }
}

// MARK: - Play

private struct PlayView: View {
    @Bindable var shell: ShellCoordinator
    var setup: SetupManager
    /// Opens the launcher's own screens (sign-in, Fabric, JIT). Deliberate user action only.
    let presentLauncherSetup: () -> Void
    @State private var importing = false
    @State private var playMessage = ""
    @State private var launching = false
    /// The Play-task is kept so a game that starts through another path stops the stale wait loop.
    @State private var playTask: Task<Void, Never>?
    @State private var slowStart = false
    @State private var launchFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    if !shell.crashGuardMessage.isEmpty { safeModeCard }
                    if launchFailed && !shell.gameRunning { launchFailedCard }
                    if slowStart && launching && !shell.gameRunning { slowStartCard }
                    if shell.gameRunning { inGameCard } else { setupCard }
                }
                .padding(32)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("VRMC")
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType(filenameExtension: "jar") ?? .data, .data]) { result in
            if case .success(let url) = result { setup.importVivecraft(from: url) }
        }
        .onChange(of: shell.gameRunning) { _, running in
            // The game can also be started from Minecraft setup; drop any stale Play-tab state and
            // stop the wait loop (otherwise it keeps polling for up to 180 s in the background).
            if running {
                playTask?.cancel()
                playTask = nil
                launching = false
                slowStart = false
                launchFailed = false
                playMessage = ""
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Minecraft in VR")
                    .font(.largeTitle.weight(.bold))
                Text(heroSubtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if shell.gameRunning {
                if !shell.immersiveOpen {
                    if shell.autoOpenPending {
                        // The automatic entry is expected to win; show its stage instead of a button
                        // that would invite a premature manual press (the 1.3.3 device bug). Only
                        // after a bounded wait is the manual fallback offered next to the status.
                        VStack(alignment: .trailing, spacing: 10) {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(shell.autoOpenStage.isEmpty ? "Entering VR…" : shell.autoOpenStage)
                            }
                            .font(.title3.weight(.semibold))
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(shell.autoOpenStage.isEmpty ? "Entering VR" : shell.autoOpenStage)
                            if shell.autoOpenFallbackAvailable {
                                Button {
                                    shell.enterVRManually()
                                } label: {
                                    Label("Enter VR now", systemImage: "visionpro")
                                        .padding(.horizontal, 8)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .accessibilityHint("Opens VR without waiting for the automatic entry. Use this if it does not open by itself.")
                            }
                        }
                    } else {
                        Button {
                            shell.enterVRManually()
                        } label: {
                            Label("Enter VR", systemImage: "visionpro")
                                .font(.title3.weight(.semibold))
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.extraLarge)
                        .accessibilityHint("Opens the VR view manually. Use this if it does not open by itself.")
                    }
                }
            } else if launching {
                Button {} label: {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Starting…")
                    }
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 20)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .disabled(true)
                .accessibilityLabel("Starting Minecraft")
            } else if startable {
                Button {
                    play()
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 20)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .accessibilityHint("Starts Minecraft in this app")
            } else if setup.readyToPlay {
                // Microsoft sign-in / Fabric profile are the launcher's own flows. Play would only
                // push the launcher's screens invisibly, so send the user to the deliberate sheet.
                Button {
                    presentLauncherSetup()
                } label: {
                    Label("Set up Minecraft", systemImage: "wrench.and.screwdriver")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 20)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .accessibilityHint("Opens Minecraft setup to sign in and install Fabric")
            } else {
                Button {
                    play()
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 20)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .disabled(true)
                .accessibilityHint("Install the VRMC mod and Vivecraft first")
            }
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32))
    }

    private var heroSubtitle: String {
        if let error = shell.lastOpenError { return error }
        if shell.gameRunning {
            if shell.presenting { return "Playing. Left fist tap opens the game menu; the VRMC Quick Menu is in it." }
            if shell.autoOpenPending { return shell.autoOpenStage.isEmpty ? "Entering VR…" : shell.autoOpenStage }
            return shell.statusMessage
        }
        if !playMessage.isEmpty { return playMessage }
        if setup.readyToPlay {
            if !setup.fabric.isReady || !setup.account.isReady {
                return "One last step: sign in and pick the Fabric profile in Minecraft setup."
            }
            return "VRMC is ready. Press Play to start Minecraft."
        }
        return "A few things to set up before the first game."
    }

    /// Play can drive the launcher directly only when the launcher's own prerequisites are in place;
    /// otherwise the hero offers the deliberate "Set up Minecraft" sheet instead.
    private var startable: Bool {
        setup.readyToPlay && setup.fabric.isReady && setup.account.isReady
    }

    /// Start Minecraft through the launcher's own Play button, in place, with no UI switch.
    ///
    /// The button lives in the hidden launcher host and only exists/becomes enabled after the
    /// launcher has loaded its versions and accounts, so the press is retried for a few seconds.
    /// If nothing starts, the Play tab says so inline and offers "Open Minecraft setup"; the launcher
    /// screens are never presented automatically.
    private func play() {
        guard !launching else { return }
        playMessage = "Starting Minecraft…"
        launchFailed = false
        slowStart = false
        launching = true
        playTask?.cancel()
        playTask = Task {
            var pressed = false
            for attempt in 0..<30 {
                if Task.isCancelled { return }
                if LauncherBridge.pressPlay() {
                    pressed = true
                    break
                }
                if attempt >= 2 { playMessage = "Waiting for the launcher…" }
                try? await Task.sleep(for: .milliseconds(400))
            }
            guard !Task.isCancelled else { return }
            guard pressed else {
                launching = false
                launchFailed = true
                playMessage = "Minecraft did not start. The launcher is still getting ready."
                return
            }
            playMessage = "Starting Minecraft…"
            // The launcher runs its install/JIT flow and then starts the JVM; wait for the game's own
            // started notification instead of assuming the button press was enough. The first run can
            // take minutes (downloads, JIT), so the ceiling is generous and the setup button appears
            // while still starting rather than declaring failure early.
            for tick in 0..<360 {
                if Task.isCancelled { return }
                if shell.gameRunning {
                    launching = false
                    slowStart = false
                    launchFailed = false
                    playMessage = ""
                    return
                }
                if tick == 40 { slowStart = true }
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard !Task.isCancelled else { return }
            launching = false
            slowStart = false
            launchFailed = true
            playMessage = "Minecraft is taking longer than expected to start."
        }
    }

    private var safeModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(shell.crashGuardMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.yellow)
            Text("Your worlds are safe. If it keeps happening, export diagnostics from Help.")
                .foregroundStyle(.secondary)
            if shell.safeMode {
                Button("Clear safe mode") { shell.clearCrashGuard() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var slowStartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Still starting…", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            Text("The first launch can take a few minutes while Minecraft downloads what it needs. If nothing happens, open Minecraft setup to check sign-in, Fabric and JIT.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                presentLauncherSetup()
            } label: {
                Label("Open Minecraft setup", systemImage: "wrench.and.screwdriver")
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var launchFailedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Minecraft did not start", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.yellow)
            Text("The launcher may still need a Microsoft sign-in, a Fabric profile or JIT. Open Minecraft setup to finish it, then press Play again. Nothing else has changed.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button {
                    presentLauncherSetup()
                } label: {
                    Label("Open Minecraft setup", systemImage: "wrench.and.screwdriver")
                }
                .buttonStyle(.borderedProminent)
                Button("Try again") { play() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Setup").font(.title2.weight(.semibold))
            StatusRow(title: "VRMC mod", systemImage: "puzzlepiece.extension", status: setup.provider)
            if !setup.provider.isReady {
                Button("Reinstall VRMC mod") { setup.reinstallProvider() }
                    .buttonStyle(.bordered)
                    .padding(.leading, 46)
            }
            Divider()
            StatusRow(title: "Vivecraft \(SetupManager.vivecraftVersion)", systemImage: "visionpro",
                      status: setup.vivecraft)
            if !setup.vivecraft.isReady {
                VStack(alignment: .leading, spacing: 10) {
                    if setup.downloading {
                        ProgressView(value: setup.downloadProgress) {
                            Text("Downloading from Modrinth…")
                        }
                        .frame(maxWidth: 360)
                    } else {
                        HStack(spacing: 12) {
                            Button {
                                setup.downloadVivecraft()
                            } label: {
                                Label("Download (6.7 MB)", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            Button {
                                importing = true
                            } label: {
                                Label("Import from Files", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Text("Vivecraft is a separate open-source mod (LGPL). VRMC downloads the tested build from Modrinth and checks its fingerprint before installing it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 46)
            }
            Divider()
            StatusRow(title: "Fabric for Minecraft \(SetupManager.minecraftVersion)", systemImage: "shippingbox",
                      status: setup.fabric)
            Divider()
            StatusRow(title: "Minecraft account", systemImage: "person.crop.circle", status: setup.account)
            if !setup.fabric.isReady || !setup.account.isReady || !setup.jit.isReady {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        presentLauncherSetup()
                    } label: {
                        Label("Open Minecraft setup", systemImage: "wrench.and.screwdriver")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Shows the Minecraft launcher screens for sign-in, Fabric and JIT")
                    Text("Sign-in, Fabric and the JIT prompt happen in Minecraft setup. Play starts the game directly; open this only if the game does not start.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 46)
            }
            Divider()
            StatusRow(title: "JIT (StikDebug)", systemImage: "bolt", status: setup.jit)
            if !setup.lastActionMessage.isEmpty {
                Text(setup.lastActionMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
    }

    private var inGameCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("In game").font(.title2.weight(.semibold))
            Text("These act on the running game. The same controls are in VR: pause with a left fist tap, then choose “VRMC Quick Menu”.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                actionButton("Recenter view", "scope") { sendGameCommands(["recenter"]) }
                actionButton("Calibrate height", "ruler") { sendGameCommands(["calibrate-height"]) }
                actionButton("Open Quick Menu", "slider.horizontal.3") { sendGameCommands(["quick-menu"]) }
                actionButton("Release stuck input", "hand.raised.slash") { sendGameCommands(["release-input"]) }
            }
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
    }

    private func actionButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Comfort

private struct ComfortView: View {
    @Bindable var shell: ShellCoordinator
    @State private var seated = false
    @State private var turn = 45
    @State private var vignetteOn = true
    @State private var vignette = 0.5
    @State private var autoHeight = true
    @State private var height = 1.70
    @State private var worldScale = 1.0
    @State private var autoSprint = true
    @State private var preset = "none"
    @State private var renderDistance = 12
    @State private var reduceWhenHot = false
    @State private var adaptive = false
    @State private var saved = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Play style", selection: $seated) {
                        Text("Standing").tag(false)
                        Text("Seated").tag(true)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Play style")
                } footer: {
                    Text(seated
                         ? "Seated: right middle-finger pinch tap jumps, hold sneaks; left middle-finger pinch tap turns left, double tap turns right. All other hand gestures stay the same."
                         : "Standing: rise on your toes to jump, crouch to sneak.")
                }
                Section("Turning") {
                    Picker("Turning", selection: $turn) {
                        Text("Snap 15°").tag(15)
                        Text("Snap 30°").tag(30)
                        Text("Snap 45°").tag(45)
                        Text("Snap 90°").tag(90)
                        Text("Smooth").tag(0)
                    }
                }
                Section {
                    Toggle("Comfort vignette", isOn: $vignetteOn)
                    if vignetteOn {
                        LabeledContent("Strength") {
                            Slider(value: $vignette, in: 0.1...0.9, step: 0.05)
                                .frame(maxWidth: 360)
                                .accessibilityLabel("Vignette strength")
                        }
                    }
                } header: {
                    Text("Motion comfort")
                } footer: {
                    Text("Darkens the edges of your view. Recommended if movement makes you uneasy.")
                }
                Section("Body") {
                    Toggle("Detect my height automatically", isOn: $autoHeight)
                    if !autoHeight {
                        LabeledContent("Height \(String(format: "%.2f", height)) m") {
                            Slider(value: $height, in: 1.30...2.10, step: 0.01)
                                .frame(maxWidth: 360)
                                .accessibilityLabel("Player height")
                                .accessibilityValue(String(format: "%.2f metres", height))
                        }
                    }
                    LabeledContent("World scale \(String(format: "%.2f", worldScale))×") {
                        Slider(value: $worldScale, in: 0.8...1.5, step: 0.05)
                                .frame(maxWidth: 360)
                                .accessibilityLabel("World scale")
                                .accessibilityValue(String(format: "%.2f times", worldScale))
                    }
                    Toggle("Sprint when moving at full speed", isOn: $autoSprint)
                }
                Section {
                    Picker("Graphics", selection: $preset) {
                        Text("Default").tag("none")
                        Text("Performance").tag("performance")
                        Text("Balanced").tag("balanced")
                        Text("Quality").tag("quality")
                    }
                    Stepper("Render distance: \(renderDistance) chunks", value: $renderDistance, in: 6...24)
                    Toggle("Lower quality when the headset gets warm", isOn: $reduceWhenHot)
                    Toggle("Cap the frame rate when frames are missed", isOn: $adaptive)
                } header: {
                    Text("Performance")
                }
                Section {
                    Button {
                        save()
                    } label: {
                        Label("Save", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    if !saved.isEmpty {
                        Text(saved).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Comfort")
        }
        .onAppear { if !loaded { load(); loaded = true } }
    }

    private func load() {
        let values = shellReadRuntimeSettings()
        seated = values["comfort.seated"] == "true"
        if let raw = values["comfort.worldRotationIncrement"], let angle = Double(raw) {
            turn = [0, 15, 30, 45, 90].min(by: { abs(Double($0) - angle) < abs(Double($1) - angle) }) ?? 45
        }
        let v = shellReadVignette()
        vignetteOn = v.enabled
        vignette = v.enabled ? max(0.1, v.strength) : 0.5
        if let raw = values["comfort.manualHeight"], let h = Double(raw), h > 0 {
            autoHeight = false
            height = min(2.10, max(1.30, h))
        } else {
            autoHeight = true
        }
        if let raw = values["comfort.worldScale"], let s = Double(raw), (0.8...1.5).contains(s) { worldScale = s }
        autoSprint = values["comfort.autoSprint"] != "false"
        preset = values["performance.preset"] ?? "none"
        if let raw = values["performance.renderDistance"], let n = Int(raw) { renderDistance = min(24, max(6, n)) }
        reduceWhenHot = values["performance.thermalResponse"] == "reduce"
        adaptive = values["performance.adaptiveFramerate"] == "true"
    }

    private func save() {
        // Only the keys this screen owns are changed; anything else in the file is preserved.
        var values = shellReadRuntimeSettings()
        values["comfort.seated"] = seated ? "true" : "false"
        values["comfort.worldRotationIncrement"] = String(turn)
        values["comfort.manualHeight"] = autoHeight ? "-1" : String(format: "%.2f", height)
        values["comfort.worldScale"] = String(format: "%.2f", worldScale)
        values["comfort.autoSprint"] = autoSprint ? "true" : "false"
        values["performance.preset"] = preset
        values["performance.renderDistance"] = String(renderDistance)
        values["performance.thermalResponse"] = reduceWhenHot ? "reduce" : "notify"
        values["performance.adaptiveFramerate"] = adaptive ? "true" : "false"
        let ok = shellWriteRuntimeSettings(values) && shellWriteVignette(enabled: vignetteOn, strength: vignette)
        if !ok {
            saved = "Could not save. Try again."
        } else if shell.gameRunning {
            sendGameCommands(["reload-settings"])
            saved = "Saved and applied to the running game."
        } else {
            saved = "Saved. Applies when you start the game."
        }
    }
}

// MARK: - Controls

private struct GestureRow: View {
    let gesture: String
    let action: String
    let symbol: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.title3).frame(width: 34).foregroundStyle(.secondary)
            Text(gesture).font(.body.weight(.medium))
            Spacer()
            Text(action).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ControlsView: View {
    @Bindable var shell: ShellCoordinator
    @State private var pinchSensitivity = 0.5
    @State private var moveSpeed = 3.0
    @State private var deadzone = 0.10
    @State private var saved = ""
    @State private var confirmReset = false
    @State private var seated = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Aim and act") {
                    GestureRow(gesture: "Look", action: "Aim / point in menus", symbol: "eye")
                    GestureRow(gesture: "Right pinch, short", action: "Place · use · click", symbol: "hand.pinch")
                    GestureRow(gesture: "Right pinch, hold", action: "Break / mine", symbol: "hammer")
                    GestureRow(gesture: "Right punch", action: "Attack", symbol: "bolt")
                    GestureRow(gesture: "Right fist tap", action: "Use · mount · dismount", symbol: "hand.raised.fingers.spread")
                }
                Section("Move") {
                    GestureRow(gesture: "Left pinch, hold and move", action: "Walk / strafe", symbol: "figure.walk")
                    if seated {
                        GestureRow(gesture: "Right middle pinch tap / hold", action: "Jump / sneak", symbol: "arrow.up.and.down")
                        GestureRow(gesture: "Left middle pinch tap / double", action: "Turn left / right", symbol: "arrow.left.arrow.right")
                    } else {
                        GestureRow(gesture: "Rise / crouch", action: "Jump / sneak", symbol: "arrow.up.and.down")
                    }
                    GestureRow(gesture: "Both middle pinches, double tap", action: "Recenter", symbol: "scope")
                }
                Section("Menus and items") {
                    GestureRow(gesture: "Left fist tap", action: "Game menu · back", symbol: "line.3.horizontal")
                    GestureRow(gesture: "Both fists tap", action: "Inventory", symbol: "square.grid.3x3")
                    GestureRow(gesture: "Touch hotbar / index tap", action: "Change slot", symbol: "rectangle.split.3x1")
                    GestureRow(gesture: "Hands apart, open back hand", action: "Draw / fire bow", symbol: "arrow.up.right")
                    GestureRow(gesture: "Right hand to mouth", action: "Eat / drink", symbol: "fork.knife")
                }
                Section {
                    LabeledContent("Pinch sensitivity") {
                        Slider(value: $pinchSensitivity, in: 0...1, step: 0.05) {
                            Text("Pinch sensitivity")
                        } minimumValueLabel: {
                            Text("Firm")
                        } maximumValueLabel: {
                            Text("Light")
                        }
                        .frame(maxWidth: 400)
                    }
                    LabeledContent("Walking speed \(String(format: "%.1f", moveSpeed))") {
                        Slider(value: $moveSpeed, in: 1.0...6.0, step: 0.1)
                                .frame(maxWidth: 400)
                                .accessibilityLabel("Walking speed")
                    }
                    LabeledContent("Movement dead zone \(Int(deadzone * 100)) cm") {
                        Slider(value: $deadzone, in: 0.02...0.30, step: 0.01)
                                .frame(maxWidth: 400)
                                .accessibilityLabel("Movement dead zone")
                    }
                    Button {
                        save()
                    } label: {
                        Label("Save", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Reset hand tuning", role: .destructive) { confirmReset = true }
                    if !saved.isEmpty { Text(saved).foregroundStyle(.secondary) }
                } header: {
                    Text("Hand tuning")
                } footer: {
                    Text("Lighter pinches trigger with less finger contact. If actions fire on their own, move toward Firm.")
                }
            }
            .navigationTitle("Controls")
            .confirmationDialog("Reset hand tuning?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { reset() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Hand tuning goes back to the defaults. Comfort settings and worlds are not changed.")
            }
        }
        .onAppear {
            // Load once so switching tabs does not silently discard unsaved slider edits.
            if !loaded { load(); loaded = true }
        }
    }

    // Sensitivity maps onto the M7 engine's thumb-index Schmitt pair (metres): firm 15/35 mm ..
    // default 25/45 mm (0.5) .. light 35/55 mm.
    private func pinchOn(_ s: Double) -> Double { 0.015 + 0.020 * s }
    private func load() {
        seated = shellReadRuntimeSettings()["comfort.seated"] == "true"
        let tune = shellReadInputTune()
        if let raw = tune["m7.pinch.on"], let on = Double(raw) {
            pinchSensitivity = min(1, max(0, (on - 0.015) / 0.020))
        } else {
            pinchSensitivity = 0.5
        }
        moveSpeed = Double(tune["move.forwardScale"] ?? "") ?? 3.0
        deadzone = Double(tune["move.deadzone"] ?? "") ?? 0.10
    }

    private func save() {
        var tune = shellReadInputTune()
        let on = pinchOn(pinchSensitivity)
        tune["m7.pinch.on"] = String(format: "%.3f", on)
        tune["m7.pinch.off"] = String(format: "%.3f", on + 0.020)
        tune["move.forwardScale"] = String(format: "%.2f", moveSpeed)
        tune["move.strafeScale"] = String(format: "%.2f", moveSpeed)
        tune["move.deadzone"] = String(format: "%.2f", deadzone)
        guard shellWriteInputTune(tune) else { saved = "Could not save. Try again."; return }
        if shell.gameRunning {
            sendGameCommands(["reload-input"])
            saved = "Saved and applied to the running game."
        } else {
            saved = "Saved. Applies when you start the game."
        }
    }

    private func reset() {
        try? FileManager.default.removeItem(at: shellInputTuneURL())
        load()
        if shell.gameRunning { sendGameCommands(["reload-input"]) }
        saved = "Hand tuning reset."
    }
}

// MARK: - Help

private struct HelpView: View {
    @Bindable var shell: ShellCoordinator
    var setup: SetupManager
    let presentLauncherSetup: () -> Void
    @State private var status: [String: Any] = [:]
    @State private var exportURL: URL?
    @State private var exportMessage = ""
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    LabeledContent("State", value: sessionState)
                    LabeledContent("Hands", value: handsText)
                    LabeledContent("Frame time (95th pct.)", value: frameText)
                    LabeledContent("Headset temperature", value: thermalText)
                }
                Section {
                    Button {
                        shell.enterVRManually()
                    } label: {
                        Label("Enter VR again", systemImage: "visionpro")
                    }
                    // While the automatic entry is pending this is the fallback, not an invitation;
                    // it becomes available when the auto attempt ends (or after its bounded wait) and
                    // the Play tab then offers it too.
                    .disabled(shell.immersiveOpen || !shell.gameRunning
                              || (shell.autoOpenPending && !shell.autoOpenFallbackAvailable))
                    Button {
                        sendGameCommands(["release-input"])
                    } label: {
                        Label("Release stuck input", systemImage: "hand.raised.slash")
                    }
                    .disabled(!shell.gameRunning)
                    if shell.safeMode {
                        Button {
                            shell.clearCrashGuard()
                        } label: {
                            Label("Clear safe mode", systemImage: "checkmark.shield")
                        }
                    }
                } header: {
                    Text("Recovery")
                } footer: {
                    Text("To quit, close the VRMC window. Your world is saved by Minecraft as you play.")
                }
                Section {
                    Button {
                        presentLauncherSetup()
                    } label: {
                        Label("Open Minecraft setup", systemImage: "wrench.and.screwdriver")
                    }
                    .accessibilityHint("Shows the Minecraft launcher screens for sign-in, Fabric and JIT")
                } header: {
                    Text("Minecraft setup")
                } footer: {
                    Text("Play starts the game directly. Open this only if it does not start: sign in, install Fabric, or enable JIT here.")
                }
                Section {
                    Button {
                        export()
                    } label: {
                        Label(exporting ? "Preparing…" : "Export diagnostics", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(exporting)
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share diagnostics file", systemImage: "square.and.arrow.up")
                        }
                    }
                    if !exportMessage.isEmpty { Text(exportMessage).foregroundStyle(.secondary) }
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Creates one text file with VRMC logs and settings. It stays on this device unless you share it.")
                }
                Section("About") {
                    LabeledContent("VRMC", value: appVersion)
                    LabeledContent("Minecraft", value: SetupManager.minecraftVersion)
                    LabeledContent("Vivecraft", value: SetupManager.vivecraftVersion)
                    LabeledContent("VRMC mod", value: setup.provider.detail)
                    Text("VRMC is not affiliated with Mojang, Microsoft, Vivecraft or Apple. VR can cause discomfort; take breaks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Help")
        }
        .task {
            while !Task.isCancelled {
                status = readStatus()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private var sessionState: String {
        if shell.presenting { return "Playing in VR" }
        if shell.gameRunning { return shell.statusMessage }
        return "Not playing"
    }

    private var live: Bool { shell.gameRunning && !status.isEmpty }

    private var handsText: String {
        guard live else { return "—" }
        let left = status["handLeftTracked"] as? Bool ?? false
        let right = status["handRightTracked"] as? Bool ?? false
        switch (left, right) {
        case (true, true): return "Both tracked"
        case (true, false): return "Left only"
        case (false, true): return "Right only"
        default: return "Not visible"
        }
    }

    private var frameText: String {
        guard live, let p95 = status["frameP95Ms"] as? Double, p95 > 0 else { return "—" }
        return String(format: "%.1f ms (%@)", p95, p95 <= 11.2 ? "smooth" : "busy")
    }

    private var thermalText: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "Hot — quality may be lowered"
        case .critical: return "Too hot — take a break"
        @unknown default: return "Unknown"
        }
    }

    private func readStatus() -> [String: Any] {
        let url = SetupManager.gameDirectory().appendingPathComponent("vrmc-status.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    private func export() {
        exporting = true
        exportMessage = ""
        Task.detached {
            let url = shellBuildDiagnosticsBundle()
            await MainActor.run {
                exporting = false
                exportURL = url
                exportMessage = url == nil ? "Export failed." : "Ready to share."
            }
        }
    }
}
