import XCTest
@testable import VRMCore

final class ConformanceVectorTests: XCTestCase {
    private func data(_ name: String) throws -> Data {
        if let url = Bundle.module.url(forResource: name, withExtension: "bin", subdirectory: "Fixtures") {
            return try Data(contentsOf: url)
        }
        if let url = Bundle.module.url(forResource: name, withExtension: "bin") {
            return try Data(contentsOf: url)
        }
        throw XCTSkip("vector \(name).bin missing")
    }

    func testHelloVectorReEncodes() throws {
        let bytes = try data("hello")
        let (header, message) = try ControlMessage.decode(bytes)
        XCTAssertEqual(header.type, .hello)
        XCTAssertEqual(try message.encoded(sessionId: header.sessionId, sequence: header.sequence), bytes)
    }

    func testWelcomeVectorReEncodes() throws {
        let bytes = try data("welcome")
        let (header, message) = try ControlMessage.decode(bytes)
        XCTAssertEqual(header.type, .welcome)
        XCTAssertEqual(header.sessionId, 0x1234)
        XCTAssertEqual(try message.encoded(sessionId: header.sessionId, sequence: header.sequence), bytes)
    }

    func testStreamConfigVectorReEncodes() throws {
        let bytes = try data("stream_config")
        let (header, message) = try ControlMessage.decode(bytes)
        guard case .streamConfig(let config) = message else {
            return XCTFail("wrong type")
        }
        XCTAssertEqual(config.videoWidth, 1280)
        XCTAssertEqual(config.eyeWidth, 640)
        XCTAssertEqual(try message.encoded(sessionId: header.sessionId, sequence: header.sequence), bytes)
    }

    func testFrameMetaVectorDecodes() throws {
        let bytes = try data("frame_meta")
        let (header, payload) = try MediaHeader.parseDatagram(bytes)
        XCTAssertEqual(header.type, .frameMeta)
        let meta = try FrameMeta.decodePayload(payload)
        XCTAssertEqual(meta.frameId, 42)
        XCTAssertEqual(meta.clientHeadTimestampNs, 777)
        XCTAssertEqual(try meta.encodePayload(), payload)
    }

    func testIntentVectorDecodes() throws {
        let bytes = try data("intent")
        let (header, payload) = try MediaHeader.parseDatagram(bytes)
        XCTAssertEqual(header.type, .input)
        let decoded = try InputPayload.decodePayload(payload)
        guard case .intent(let intent) = decoded else {
            return XCTFail("wrong input subtype")
        }
        XCTAssertEqual(intent.hand, .right)
        XCTAssertEqual(intent.trigger, 0.75, accuracy: 0.001)
        XCTAssertEqual(intent.grip, 0.25, accuracy: 0.001)
        XCTAssertEqual(intent.buttons, [.triggerClick, .a, .gripTouch])
        XCTAssertEqual(try decoded.encodePayload(), payload)
    }

    func testVideoFragmentVectorDecodes() throws {
        let bytes = try data("video_fragment")
        let (header, payload) = try MediaHeader.parseDatagram(bytes)
        XCTAssertEqual(header.type, .video)
        XCTAssertTrue(header.flags.contains(.keyframe))
        XCTAssertEqual(header.frameId, 42)
        XCTAssertFalse(payload.isEmpty)
    }
}
