import Foundation
import CoreVideo
import os
import VRMCore
import VRMCVideo

/// Orchestrates the control connection, UDP media/input, decode, gesture mapping, and
/// telemetry. The renderer reads `frameStore`; ARKit/synthetic tracking pushes snapshots
/// through `updateTracking`.
public final class SessionCoordinator: @unchecked Sendable {
    private let logger = Logger(subsystem: "dev.vrmc.app", category: "session")
    public struct Metrics: Sendable {
        public var state: String
        public var fps: Double
        public var framesReceived: UInt32
        public var framesDecoded: UInt32
        public var framesDropped: UInt32
        public var latencyP50Ms: Double
        public var latencyP95Ms: Double
        public var queueDepth: Int
        public var clockOffsetMs: Double
        public var locomotion: Bool
        public var tracking: String
    }

    public let frameStore: FrameStore
    private let host: String
    private let controlPort: UInt16
    private let inputPort: UInt16
    private let mediaPort: UInt16
    private let insecureDev: Bool
    private let onMetrics: @Sendable (Metrics) -> Void
    private let onStatus: @Sendable (String) -> Void

    private let lock = NSLock()
    private var control: TCPControlConnection?
    private var udp: UDPTransport?
    private var decoder: VideoDecoder?
    private var assembler = FrameAssembler()
    private var clock = ClockSyncEstimator()
    private var mapper = ControllerMapper()
    private var telemetry = TelemetryCounters()
    private var latency = LatencyTracker()
    private var frames = FrameCounters()
    private var sessionId: UInt32 = 0
    private var sequence: UInt64 = 0
    private var pingId: UInt32 = 0
    private var lastFramesDelta: UInt32 = 0
    private var lastMetricsAt = Timestamp.now()
    private var streaming = false
    private var ready = false
    private var running = false
    private var leftSnapshot: HandSnapshot?
    private var rightSnapshot: HandSnapshot?
    private var headPose = Pose.identity
    private var headQuality: TrackingQuality = .invalid
    private var pendingMeta: [UInt32: FrameMeta] = [:]
    private var lastDecodedFrameId: UInt32 = 0
    private var timers: [DispatchSourceTimer] = []
    private var reconnectAttempt = 0
    private var lastLocomotion = false
    private var lastTracking = "none"
    private let headHistory = HeadPoseHistory()
    private var calibration: TrackingCalibration?
    private var userHeight: Float = 1.62

    public init(
        frameStore: FrameStore,
        host: String,
        controlPort: UInt16 = ProtocolConstants.controlPort,
        mediaPort: UInt16 = ProtocolConstants.mediaPort,
        inputPort: UInt16 = ProtocolConstants.inputPort,
        insecureDev: Bool = true,
        onMetrics: @escaping @Sendable (Metrics) -> Void,
        onStatus: @escaping @Sendable (String) -> Void
    ) {
        self.frameStore = frameStore
        self.host = host
        self.controlPort = controlPort
        self.mediaPort = mediaPort
        self.inputPort = inputPort
        self.insecureDev = insecureDev
        self.onMetrics = onMetrics
        self.onStatus = onStatus
    }

    public var isStreaming: Bool {
        lock.lock(); defer { lock.unlock() }; return streaming
    }

    public func start() {
        lock.lock()
        if running { lock.unlock(); return }
        running = true
        lock.unlock()
        onStatus("Connecting to \(host)…")
        do {
            let udp = UDPTransport(
                host: host, inputPort: inputPort,
                onDatagram: { [weak self] header, payload in
                    self?.handleMedia(header, payload)
                },
                onFailure: { [weak self] error in
                    self?.handleFailure(error.map(String.init(describing:)))
                }
            )
            try udp.start()
            self.udp = udp

            let control = TCPControlConnection(
                host: host, port: controlPort,
                onMessage: { [weak self] header, message in
                    self?.handleControl(header, message)
                },
                onFailure: { [weak self] error in
                    self?.handleFailure(error.map(String.init(describing:)))
                }
            )
            try control.start()
            self.control = control
            try control.send(hello(), sessionId: 0)
            startTimers()
        } catch {
            handleFailure(String(describing: error))
        }
    }

    public func stop() {
        lock.lock()
        running = false
        let control = self.control
        let udp = self.udp
        let timers = self.timers
        self.control = nil
        self.udp = nil
        self.timers = []
        streaming = false
        ready = false
        lock.unlock()
        timers.forEach { $0.cancel() }
        control?.close()
        udp?.close()
        frameStore.clear()
        onStatus("Disconnected")
    }

    public func updateTracking(left: HandSnapshot?, right: HandSnapshot?, head: Pose, quality: TrackingQuality) {
        lock.lock()
        var calibratedNow = false
        if calibration == nil, quality == .tracked, head.isFinite {
            calibration = TrackingCalibration(head: head, userHeight: userHeight)
            calibratedNow = true
        }
        let transform = calibration
        lock.unlock()
        if calibratedNow { onStatus("Tracking origin calibrated") }
        let mappedHead = transform?.pose(head) ?? head
        let mappedLeft = left.map { transform?.hand($0) ?? $0 }
        let mappedRight = right.map { transform?.hand($0) ?? $0 }
        lock.lock()
        leftSnapshot = mappedLeft
        rightSnapshot = mappedRight
        headPose = mappedHead
        headQuality = quality
        lock.unlock()
    }

    public func recenter(userHeight: Float = 1.62) {
        lock.lock()
        self.userHeight = userHeight
        calibration = nil
        lock.unlock()
        onStatus("Recenter requested; tracking origin will be set from the next tracked head pose")
    }

    // MARK: - Handshake

    private func hello() -> ControlMessage {
        .hello(HelloMessage(
            clientVersion: "0.1.0",
            clientPlatform: "visionOS 27",
            requestedAuthMode: insecureDev ? .insecureDev : .pairingCode,
            capabilities: [.handSkeleton, .headPose, .reprojection, .telemetry]
        ))
    }

    private func handleControl(_ header: ControlHeader, _ message: ControlMessage) {
        lock.lock()
        if header.sessionId != 0 { sessionId = header.sessionId }
        lock.unlock()
        switch message {
        case .welcome(let welcome):
            lock.lock(); sessionId = welcome.sessionId; lock.unlock()
            onStatus("Authenticated with \(welcome.hostName)")
        case .authOK(let auth):
            if !auth.isSuccess {
                onStatus("Authentication failed: \(auth.detail)")
                return
            }
            onStatus("Authenticated")
        case .streamConfig(let config):
            do {
                try config.validate()
            } catch {
                onStatus("Invalid stream config: \(error)")
                return
            }
            frameStore.setConfig(config)
            let decoder = VideoDecoder(codec: config.codec) { [weak self] frame in
                self?.handleDecodedFrame(frame)
            }
            lock.lock()
            self.decoder = decoder
            assembler.reset()
            pendingMeta.removeAll()
            ready = true
            lock.unlock()
            try? send(.sessionState(SessionStateMessage(phase: .ready, detail: "client ready")))
            onStatus("Stream configured: \(config.videoWidth)×\(config.videoHeight) \(config.codec == .hevc ? "HEVC" : "H.264")")
        case .startStream(let start):
            lock.lock()
            streaming = true
            lastMetricsAt = .now()
            lastFramesDelta = 0
            lock.unlock()
            onStatus("Streaming from host (\(start.firstFrameId))")
        case .stopStream(let stop):
            lock.lock(); streaming = false; lock.unlock()
            onStatus("Stream stopped: \(stop.detail.isEmpty ? "reason \(stop.reason)" : stop.detail)")
        case .clockPong(let pong):
            let t3 = Timestamp.now().nanoseconds
            clock.add(ClockSample(t0: pong.t0, t1: pong.t1, t2: pong.t2, t3: t3))
        case .sessionState(let state):
            if state.phase == .degraded || state.phase == .error {
                onStatus(state.detail.isEmpty ? "Session degraded" : state.detail)
            }
        case .error(let error):
            onStatus("Host error: \(error.detail)")
        case .haptic:
            break
        default:
            break
        }
    }

    private func send(_ message: ControlMessage) throws {
        lock.lock()
        let control = self.control
        let session = self.sessionId
        lock.unlock()
        try control?.send(message, sessionId: session)
    }

    // MARK: - Media

    private func handleMedia(_ header: MediaHeader, _ payload: Data) {
        guard header.sessionId == 0 || header.sessionId == sessionId else { return }
        switch header.type {
        case .video:
            let result = assembler.ingest(header: header, payload: payload)
            if let frame = result.completed {
                telemetry.onFrameReceived(id: frame.frameId)
                frames.received &+= 1
                lock.lock()
                let decoder = self.decoder
                lock.unlock()
                do {
                    try decoder?.decode(accessUnit: frame.data, timestamp: Timestamp(nanoseconds: frame.timestampNs), frameId: frame.frameId)
                } catch {
                    logger.error("decode failed for frame \(frame.frameId, privacy: .public): \(String(describing: error), privacy: .public)")
                    telemetry.onFrameDropped()
                    frames.dropped &+= 1
                    requestIDR(lastFrameId: frame.frameId, reason: 1)
                }
            }
            if let entries = result.nack {
                telemetry.onNack()
                let nack = NackMessage(entries: entries)
                if let data = try? nack.encodePayload() {
                    sendMedia(type: .nack, payload: data)
                }
            }
            if result.requiresIDR {
                telemetry.onIDRRequest()
                requestIDR(lastFrameId: result.droppedFrameId ?? lastDecodedFrameId, reason: 2)
            }
            if let dropped = result.droppedFrameId {
                telemetry.onFrameDropped()
                frames.dropped &+= 1
                _ = dropped
            }

        case .frameMeta:
            if let meta = try? FrameMeta.decodePayload(payload) {
                lock.lock()
                pendingMeta[meta.frameId] = meta
                if pendingMeta.count > 16 {
                    let oldest = pendingMeta.keys.min() ?? meta.frameId
                    pendingMeta.removeValue(forKey: oldest)
                }
                lock.unlock()
            }
        case .nack, .idrRequest, .keepAlive, .audio, .input:
            break
        }
    }

    private func handleDecodedFrame(_ frame: DecodedVideoFrame) {
        lock.lock()
        let meta = pendingMeta.removeValue(forKey: frame.frameId)
        let config = frameStore.currentConfig()
        let clockEstimate = clock.latest
        let now = Timestamp.now()
        let capturedClientPose = meta.flatMap { meta in
            meta.clientHeadTimestampNs == 0 ? nil : headHistory.pose(at: Timestamp(nanoseconds: meta.clientHeadTimestampNs))
        }
        let captureHead = capturedClientPose ?? headPose
        let captureHost = frame.timestamp.nanoseconds
        lastDecodedFrameId = frame.frameId
        lock.unlock()
        frameStore.store(
            pixelBuffer: frame.pixelBuffer,
            timestamp: frame.timestamp,
            frameId: frame.frameId,
            captureHead: captureHead,
            capturedAtHostNs: captureHost
        )
        telemetry.onFrameDecoded()
        frames.decoded &+= 1
        if let hostNs = UInt64(exactly: Int64(bitPattern: frame.timestamp.nanoseconds)),
           let clientNs = clock.hostToClient(hostNs) {
            let latencyMs = Double(Int64(bitPattern: now.nanoseconds &- clientNs)) / 1_000_000
            if latencyMs > 0 && latencyMs < 2_000 {
                latency.record(.network, milliseconds: latencyMs)
            }
        }
        _ = config
        _ = clockEstimate
    }

    private func requestIDR(lastFrameId: UInt32, reason: UInt8) {
        let message = IdrRequestMessage(lastFrameId: lastFrameId, reason: reason, clientTimeNs: Timestamp.now().nanoseconds)
        if let payload = try? message.encodePayload() {
            sendMedia(type: .idrRequest, payload: payload)
        }
    }

    private func sendMedia(type: MediaPacketType, payload: Data) {
        lock.lock()
        let udp = self.udp
        let sequence = self.sequence
        self.sequence &+= 1
        let session = self.sessionId
        lock.unlock()
        guard let udp else { return }
        let header = MediaHeader(
            type: type, flags: [.plaintext], fragmentIndex: 0, fragmentCount: 1,
            payloadLength: UInt16(min(payload.count, ProtocolConstants.maxMediaPayload)),
            sessionId: session, frameId: 0, packetSequence: sequence,
            timestampNs: Timestamp.now().nanoseconds
        )
        if let data = try? header.datagram(payload: payload) {
            try? udp.send(data, port: mediaPort)
        }
    }

    // MARK: - Timers/input

    private func startTimers() {
        let queue = DispatchQueue(label: "dev.vrmc.session", qos: .userInteractive)
        let inputTimer = DispatchSource.makeTimerSource(queue: queue)
        inputTimer.schedule(deadline: .now(), repeating: .milliseconds(11))
        inputTimer.setEventHandler { [weak self] in self?.sendInputTick() }
        inputTimer.resume()

        let pollTimer = DispatchSource.makeTimerSource(queue: queue)
        pollTimer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20))
        pollTimer.setEventHandler { [weak self] in self?.pollAssembler() }
        pollTimer.resume()

        let clockTimer = DispatchSource.makeTimerSource(queue: queue)
        clockTimer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
        clockTimer.setEventHandler { [weak self] in self?.sendClockPing() }
        clockTimer.resume()

        let keepaliveTimer = DispatchSource.makeTimerSource(queue: queue)
        keepaliveTimer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
        keepaliveTimer.setEventHandler { [weak self] in self?.sendKeepAlive() }
        keepaliveTimer.resume()

        let metricsTimer = DispatchSource.makeTimerSource(queue: queue)
        metricsTimer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
        metricsTimer.setEventHandler { [weak self] in self?.emitMetrics() }
        metricsTimer.resume()

        lock.lock()
        timers = [inputTimer, pollTimer, clockTimer, keepaliveTimer, metricsTimer]
        lock.unlock()
    }

    private func sendClockPing() {
        lock.lock()
        let running = self.running
        let ping = pingId
        pingId &+= 1
        lock.unlock()
        guard running else { return }
        try? send(.clockPing(ClockPingMessage(t0: Timestamp.now().nanoseconds, pingId: ping)))
    }

    private func sendKeepAlive() {
        lock.lock()
        let udp = self.udp
        let streaming = self.streaming
        let sequence = self.sequence
        lock.unlock()
        guard streaming, let udp else { return }
        let keepalive = KeepAliveMessage(clientTimeNs: Timestamp.now().nanoseconds, inputSequence: sequence)
        if let data = Optional(keepalive.encodePayload()) {
            let header = MediaHeader(
                type: .keepAlive, flags: [.plaintext], payloadLength: UInt16(data.count),
                sessionId: sessionId, packetSequence: sequence, timestampNs: Timestamp.now().nanoseconds
            )
            if let datagram = try? header.datagram(payload: data) {
                try? udp.send(datagram, port: inputPort)
            }
        }
    }

    private func sendInputTick() {
        lock.lock()
        guard running, streaming else { lock.unlock(); return }
        let left = leftSnapshot
        let right = rightSnapshot
        let head = headPose
        let headQuality = headQuality
        let session = sessionId
        var packetSequence = sequence
        sequence &+= 16
        let udp = self.udp
        lock.unlock()
        guard let udp else { return }
        let now = Timestamp.now()
        headHistory.record(head, at: now)

        let output = mapper.update(leftSnapshot: left, rightSnapshot: right, headPose: head, now: now)
        let headInput = HeadInput(
            quality: headQuality, sampleId: UInt32(now.nanoseconds / 1_000_000),
            pose: head
        )
        sendInput(.head(headInput), udp: udp, session: session, sequence: &packetSequence)
        if let left {
            sendInput(.hand(HandInput(snapshot: left)), udp: udp, session: session, sequence: &packetSequence)
        }
        if let right {
            sendInput(.hand(HandInput(snapshot: right)), udp: udp, session: session, sequence: &packetSequence)
        }
        sendInput(.intent(output.left), udp: udp, session: session, sequence: &packetSequence)
        sendInput(.intent(output.right), udp: udp, session: session, sequence: &packetSequence)
        telemetry.onInputSent()
        lock.lock()
        self.sequence = packetSequence
        self.lastLocomotion = output.locomotionActive
        self.lastTracking = (left != nil || right != nil) ? "hands" : "none"
        lock.unlock()
    }

    private func sendInput(_ payload: InputPayload, udp: UDPTransport, session: UInt32, sequence: inout UInt64) {
        guard let data = try? payload.datagram(sessionId: session, sequence: sequence, timestampNs: Timestamp.now().nanoseconds) else { return }
        sequence &+= 1
        try? udp.send(data, port: inputPort)
    }

    private func pollAssembler() {
        let result = assembler.poll()
        if let entries = result.nack {
            let nack = NackMessage(entries: entries)
            if let data = try? nack.encodePayload() { sendMedia(type: .nack, payload: data) }
        }
        if result.requiresIDR {
            requestIDR(lastFrameId: result.droppedFrameId ?? lastDecodedFrameId, reason: 3)
        }
    }

    private func emitMetrics() {
        let snapshot = telemetry.snapshot()
        let latencySummary = latency.summary(.network)
        let estimate = clock.latest
        let framesPerSecond: Double
        let now = Timestamp.now()
        let delta = snapshot.frames.received &- lastFramesDelta
        _ = now
        framesPerSecond = Double(delta)
        lastFramesDelta = snapshot.frames.received
        lastMetricsAt = now
        let metrics = Metrics(
            state: streaming ? "streaming" : ready ? "ready" : "connecting",
            fps: framesPerSecond,
            framesReceived: snapshot.frames.received,
            framesDecoded: snapshot.frames.decoded,
            framesDropped: snapshot.frames.dropped,
            latencyP50Ms: latencySummary.p50Ms,
            latencyP95Ms: latencySummary.p95Ms,
            queueDepth: Int(snapshot.frames.queueDepth),
            clockOffsetMs: estimate.map { Double($0.offset) / 1_000_000 } ?? 0,
            locomotion: lastLocomotion,
            tracking: lastTracking
        )
        onMetrics(metrics)
    }

    private func handleFailure(_ detail: String?) {
        lock.lock()
        streaming = false
        ready = false
        let wasRunning = running
        running = false
        let control = self.control
        let udp = self.udp
        let timers = self.timers
        self.control = nil
        self.udp = nil
        self.timers = []
        lock.unlock()
        timers.forEach { $0.cancel() }
        control?.close()
        udp?.close()
        frameStore.clear()
        onStatus("Connection lost: \(detail ?? "unknown")")
        guard wasRunning else { return }
        reconnectAttempt += 1
        let delay = min(5.0, pow(2.0, Double(min(reconnectAttempt, 3))) * 0.25)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.onStatus("Reconnecting…")
            self.start()
        }
    }
}
