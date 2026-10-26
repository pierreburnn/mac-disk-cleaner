import XCTest
@testable import DiskCleanerCore

final class SmokeTests: XCTestCase {
    func testFormatterZero() {
        XCTAssertFalse(ByteFormatter.format(0).isEmpty)
    }
}
