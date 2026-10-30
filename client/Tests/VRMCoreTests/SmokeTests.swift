import XCTest
@testable import VRMCore

final class SmokeTests: XCTestCase {
    func testVersionConstants() {
        XCTAssertEqual(ProtocolConstants.versionMajor, 1)
        XCTAssertEqual(HandJointName.count, 27)
    }
}
