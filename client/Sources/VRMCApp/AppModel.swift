import Foundation
import SwiftUI
import VRMCore

@MainActor
final class AppModel: ObservableObject {
    @Published var host: String
    @Published var port: String
    @Published var status: String = "Disconnected"
    @Published var metrics: SessionCoordinator.Metrics?
    @Published var wantsImmersive = false
    @Published var immersiveOpen = false
    @Published var trackingStatus = "Hand tracking not started"
    @Published var useSyntheticHands = false

    let frameStore = FrameStore()
    private var coordinator: SessionCoordinator?
    private var handTracking: HandTrackingService?
    private var synthetic: SyntheticHands?
    private var started = false

    let demoMode: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        demoMode = arguments.contains("-VRMCDemoMode") || environment["VRMC_DEMO_MODE"] == "1"
        let envHost = environment["VRMC_HOST"]
        host = envHost ?? "127.0.0.1"
        port = environment["VRMC_PORT"] ?? "48625"
        useSyntheticHands = demoMode || environment["VRMC_SYNTHETIC_HANDS"] == "1"
        if demoMode {
            status = "Demo mode: start the mock host, then enter VR"
            wantsImmersive = true
        }
    }

    func connect() {
        guard !started else { return }
        guard let portValue = UInt16(port), !host.isEmpty else {
            status = "Invalid host or port"
            return
        }
        started = true
        status = "Connecting…"
        let coordinator = SessionCoordinator(
            frameStore: frameStore,
            host: host,
            controlPort: portValue,
            insecureDev: true,
            onMetrics: { [weak self] metrics in
                Task { @MainActor [weak self] in
                    self?.metrics = metrics
                }
            },
            onStatus: { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.status = status
                }
            }
        )
        self.coordinator = coordinator
        coordinator.start()
        wantsImmersive = true
    }

    func startTracking() {
        guard let coordinator else { return }
        if useSyntheticHands {
            let synthetic = SyntheticHands { left, right, head, quality in
                coordinator.updateTracking(left: left, right: right, head: head, quality: quality)
            }
            synthetic.start()
            self.synthetic = synthetic
            trackingStatus = "Synthetic hands (demo)"
            return
        }
        guard #available(visionOS 26.0, *) else {
            trackingStatus = "visionOS 26 required for hand tracking"
            return
        }
        let service = HandTrackingService(
            update: { left, right, head, quality in
                coordinator.updateTracking(left: left, right: right, head: head, quality: quality)
            },
            onStatus: { [weak self] text in
                Task { @MainActor [weak self] in
                    self?.trackingStatus = text
                }
            }
        )
        handTracking = service
        trackingStatus = "Starting hand tracking…"
        service.start()
    }

    func stopTracking() {
        synthetic?.stop()
        synthetic = nil
        handTracking?.stop()
        handTracking = nil
        trackingStatus = "Hand tracking stopped"
    }

    func disconnect() {
        coordinator?.stop()
        coordinator = nil
        started = false
        stopTracking()
        immersiveOpen = false
        wantsImmersive = false
        metrics = nil
        status = "Disconnected"
    }

    func recenter() {
        coordinator?.recenter()
        status = "Recenter requested"
    }

    func immersiveDidOpen() {
        immersiveOpen = true
        startTracking()
        status = "In VR"
    }

    func immersiveDidClose() {
        immersiveOpen = false
        stopTracking()
        if started { status = "Immersive space closed; connection is still active" }
    }
}
