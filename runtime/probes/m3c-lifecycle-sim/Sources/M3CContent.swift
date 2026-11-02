import SwiftUI
import UIKit

/// SwiftUI window content: hosts a UIKit view controller exactly like the real shell's
/// LauncherHostView (UIViewControllerRepresentable), and binds the immersive-space / window actions.
struct M3CContent: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        UIKitHostView()
            .onAppear {
                M3CLifecycle.shared.bind(open: openImmersiveSpace,
                                         dismiss: dismissImmersiveSpace,
                                         openWindow: openWindow)
                M3CLifecycle.shared.start()
            }
            .onChange(of: scenePhase) { _, newPhase in
                M3CLifecycle.shared.scenePhaseChanged(newPhase)
            }
    }
}

struct UIKitHostView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        M3CStatusViewController()
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

/// Visible "window content" so screenshots can identify the variant and whether the window is
/// still on screen (and whether it keeps updating while parked / backgrounded).
final class M3CStatusViewController: UIViewController {
    private let label = UILabel()
    private var timer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemIndigo
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .monospacedSystemFont(ofSize: 26, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.9),
        ])
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit { timer?.invalidate() }

    private func refresh() {
        let s = M3CStats.shared.snapshot()
        let cfg = M3CLifecycle.shared.cfg
        label.text = "VRMC M3C lifecycle probe\n" +
            "park=\(cfg.park) when=\(cfg.parkWhen) scope=\(cfg.parkScope)\n" +
            "frames=\(s.frames) state=\(s.state)\n" +
            "app=\(M3CLifecycle.shared.appStateString)"
    }
}
