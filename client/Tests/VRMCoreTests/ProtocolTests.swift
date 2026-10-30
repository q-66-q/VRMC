import XCTest
@testable import VRMCore

final class ProtocolTests: XCTestCase {
    private func roundTrip(_ message: ControlMessage, session: UInt32 = 42, sequence: UInt32 = 7) throws {
        let data = try message.encoded(sessionId: session, sequence: sequence, flags: .plaintext)
        let (header, decoded) = try ControlMessage.decode(data)
        XCTAssertEqual(header.sessionId, session)
        XCTAssertEqual(header.sequence, sequence)
        XCTAssertEqual(decoded, message)
        XCTAssertEqual(try decoded.encoded(sessionId: session, sequence: sequence, flags: .plaintext), data)
    }

    func testAllControlMessagesRoundTrip() throws {
        try roundTrip(.hello(HelloMessage(clientNonce: Data(repeating: 1, count: 16))))
        try roundTrip(.welcome(WelcomeMessage(
            sessionId: 42, serverNonce: Data(repeating: 2, count: 16),
            serverVersion: "0.1.0", hostName: "PC", salt: Data(repeating: 3, count: 16)
        )))
        try roundTrip(.authChallenge(AuthChallengeMessage(
            transcriptHash: Data(repeating: 4, count: 32),
            serverProof: Data(repeating: 5, count: 32)
        )))
        try roundTrip(.authResponse(AuthResponseMessage(clientProof: Data(repeating: 6, count: 32))))
        try roundTrip(.authOK(AuthOKMessage(status: 0)))
        try roundTrip(.streamConfig(StreamConfig()))
        try roundTrip(.startStream(StartStreamMessage(startHostTimeNs: 123, firstFrameId: 9)))
        try roundTrip(.stopStream(StopStreamMessage(reason: 1, detail: "done")))
        try roundTrip(.keyframeRequest(KeyframeRequestMessage(lastFrameId: 3, reason: 2, clientTimeNs: 9)))
        try roundTrip(.sessionState(SessionStateMessage(phase: .streaming, reason: 3, detail: "ok", flags: [.networkDegraded])))
        try roundTrip(.clockPing(ClockPingMessage(t0: 10, pingId: 4)))
        try roundTrip(.clockPong(ClockPongMessage(t0: 10, t1: 11, t2: 12, pingId: 4)))
        try roundTrip(.telemetryClient(ClientTelemetryMessage(framesReceived: 1, queueDepth: 2)))
        try roundTrip(.telemetryHost(HostTelemetryMessage(captured: 1, packetsSent: 2, bitrateKbps: 90_000, fpsX100: 9000)))
        try roundTrip(.setQuality(SetQualityMessage(maxBitrateKbps: 50_000)))
        try roundTrip(.inputConfig(InputConfigMessage(mappingProfile: "handmap-v1", predictionMs: 45)))
        try roundTrip(.haptic(HapticMessage(hand: .left, amplitude: 0.5)))
        try roundTrip(.heartbeat(HeartbeatMessage(hostTimeNs: 99, phase: .ready, flags: 1)))
        try roundTrip(.disconnect(DisconnectMessage(reason: 2, detail: "bye")))
        try roundTrip(.error(ErrorPayload(code: .badPacket, detail: "bad")))
        try roundTrip(.audioConfig(AudioConfigMessage()))
    }

    func testMalformedFramesRejected() throws {
        let data = try ControlMessage.hello(HelloMessage()).encoded(sessionId: 1, sequence: 1)
        XCTAssertThrowsError(try ControlMessage.decode(data.prefix(data.count - 1)))
        var badMagic = data
        badMagic[0] = 0
        XCTAssertThrowsError(try ControlMessage.decode(badMagic))
        var badLength = data
        badLength[16] = 0xFF
        badLength[17] = 0xFF
        badLength[18] = 0xFF
        badLength[19] = 0x7F
        XCTAssertThrowsError(try ControlMessage.decode(badLength))
    }

    func testMediaHeaderRoundTripAndReassembly() throws {
        let header = MediaHeader(
            type: .video, flags: [.plaintext, .keyframe],
            fragmentIndex: 1, fragmentCount: 2, payloadLength: 3,
            sessionId: 8, frameId: 10, packetSequence: 99, timestampNs: 1234
        )
        let datagram = try header.datagram(payload: Data([1, 2, 3]))
        let (decoded, payload) = try MediaHeader.parseDatagram(datagram)
        XCTAssertEqual(decoded.frameId, 10)
        XCTAssertEqual(payload, Data([1, 2, 3]))
        XCTAssertTrue(decoded.flags.contains(.keyframe))

        let assembler = FrameAssembler()
        let t0 = Timestamp(nanoseconds: 1_000_000_000)
        var result = assembler.ingest(
            header: MediaHeader(type: .video, flags: [.plaintext, .keyframe], fragmentIndex: 1, fragmentCount: 2, sessionId: 8, frameId: 10, timestampNs: 1234),
            payload: Data([3, 4]), now: t0
        )
        XCTAssertNil(result.completed)
        result = assembler.ingest(
            header: MediaHeader(type: .video, flags: [.plaintext], fragmentIndex: 0, fragmentCount: 2, sessionId: 8, frameId: 10, timestampNs: 1234),
            payload: Data([1, 2]), now: t0
        )
        XCTAssertEqual(result.completed?.data, Data([1, 2, 3, 4]))
        XCTAssertTrue(result.completed?.isKeyframe == true)
    }

    func testReassemblyLossNackAndTimeout() {
        let assembler = FrameAssembler(nackDelayMs: 10, dropDelayMs: 20)
        let t0 = Timestamp(nanoseconds: 1_000_000_000)
        _ = assembler.ingest(
            header: MediaHeader(type: .video, flags: [.plaintext], fragmentIndex: 0, fragmentCount: 2, sessionId: 1, frameId: 1),
            payload: Data([1]), now: t0
        )
        let nack = assembler.poll(now: t0.adding(milliseconds: 11))
        XCTAssertEqual(nack.nack?.count, 1)
        XCTAssertEqual(nack.nack?.first?.fragmentIndex, 1)
        let timeout = assembler.poll(now: t0.adding(milliseconds: 21))
        XCTAssertTrue(timeout.requiresIDR)
        XCTAssertEqual(timeout.droppedFrameId, 1)
    }

    func testInputPayloadsRoundTrip() throws {
        let timestamp = Timestamp(nanoseconds: 5_000_000_000)
        let hand = SyntheticHand.make(indexPinch: true, timestamp: timestamp)
        for payload in [
            InputPayload.head(HeadInput(sampleId: 5, pose: Pose(position: Vec3(1, 2, 3), orientation: .identity))),
            InputPayload.hand(HandInput(snapshot: hand)),
            InputPayload.intent(IntentInput(hand: .right, trigger: 1, buttons: [.triggerClick])),
        ] {
            let datagram = try payload.datagram(sessionId: 3, sequence: 7, timestampNs: timestamp.nanoseconds)
            let (header, decoded) = try InputPayload.parseDatagram(datagram)
            XCTAssertEqual(header.timestampNs, timestamp.nanoseconds)
            switch (payload, decoded) {
            case (.hand(let original), .hand(let parsed)):
                XCTAssertEqual(parsed.snapshot, original.snapshot)
                XCTAssertEqual(parsed.flags, original.flags)
            default:
                XCTAssertEqual(decoded, payload)
            }
        }
    }

    func testClockSyncKnownOffset() {
        let estimator = ClockSyncEstimator()
        let offset: Int64 = 5_000_000_000
        for index in 0..<16 {
            let t0: UInt64 = UInt64(index) * 1_000_000_000
            let t1 = UInt64(Int64(t0) + offset + 2_000_000)
            let t2 = t1 + 1_000_000
            let t3 = t0 + 5_000_000
            estimator.add(ClockSample(t0: t0, t1: t1, t2: t2, t3: t3))
        }
        let estimate = estimator.latest
        XCTAssertNotNil(estimate)
        XCTAssertEqual(estimate!.offset, offset, accuracy: 500_000)
        XCTAssertEqual(estimate!.roundTrip, 4_000_000, accuracy: 100_000)
        let host = estimator.clientToHost(10_000_000_000)
        XCTAssertEqual(Int64(host!), 15_000_000_000, accuracy: 1_000_000)
    }

    func testPredictionBounds() {
        let pose = Pose(position: Vec3(0, 1, 0), orientation: .identity)
        let velocity = PoseVelocity(linear: Vec3(1, 0, 0), angular: Vec3(0, 10, 0))
        let predicted = PosePredictor.predict(pose: pose, velocity: velocity, horizonSeconds: 1, maxHorizon: 0.05)
        XCTAssertEqual(predicted.position.x, 0.05, accuracy: 1e-5)
        XCTAssertLessThanOrEqual(predicted.orientation.yaw, 10 * 0.05 + 1e-4)
    }
}
