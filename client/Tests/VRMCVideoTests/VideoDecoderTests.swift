import XCTest
import CoreMedia
@testable import VRMCVideo
@testable import VRMCore

final class VideoDecoderTests: XCTestCase {
    private func fixture() throws -> Data {
        let candidates = [
            Bundle.module.url(forResource: "test", withExtension: "h264", subdirectory: "Fixtures"),
            Bundle.module.url(forResource: "test", withExtension: "h264"),
        ].compactMap { $0 }
        guard let url = candidates.first else {
            throw XCTSkip("test.h264 fixture missing")
        }
        return try Data(contentsOf: url)
    }

    func testAnnexBParserFindsParameterSetsAndFrame() throws {
        let data = try fixture()
        let units = AnnexBParser.split(data, codec: .h264)
        XCTAssertFalse(units.isEmpty)
        XCTAssertTrue(units.contains { $0.type == 7 })
        XCTAssertTrue(units.contains { $0.type == 8 })
        XCTAssertTrue(units.contains { $0.type == 5 })
        let avcc = AnnexBParser.avcc(units)
        XCTAssertEqual(avcc.count, units.reduce(0) { $0 + 4 + $1.data.count })
    }

    func testVideoToolboxDecodesFixture() throws {
        let data = try fixture()
        let expectation = expectation(description: "decode")
        let decoder = VideoDecoder(codec: .h264) { frame in
            XCTAssertEqual(CVPixelBufferGetWidth(frame.pixelBuffer), 64)
            XCTAssertEqual(CVPixelBufferGetHeight(frame.pixelBuffer), 64)
            expectation.fulfill()
        }
        try decoder.decode(accessUnit: data, timestamp: Timestamp(nanoseconds: 1_000_000_000), frameId: 1)
        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(decoder.dimensions?.width, 64)
        XCTAssertEqual(decoder.dimensions?.height, 64)
        decoder.reset()
    }
}
