// ByteFormatterTests.swift – Tests for ByteFormatter formatting and parts splitting
import XCTest
import Foundation
@testable import DiskCleanerCore

final class ByteFormatterTests: XCTestCase {

    func testFormatZeroBytes() {
        XCTAssertEqual(ByteFormatter.format(0), "0 B")
        let p = ByteFormatter.parts(0)
        XCTAssertEqual(p.value, "0")
        XCTAssertEqual(p.unit, "B")
    }

    func testFormatBytes() {
        XCTAssertEqual(ByteFormatter.format(1), "1 B")
        XCTAssertEqual(ByteFormatter.format(500), "500 B")
        XCTAssertEqual(ByteFormatter.format(999), "999 B")
    }

    func testFormatKilobytes() {
        // Int(kb) truncation/flooring as per ByteFormatter implementation
        XCTAssertEqual(ByteFormatter.format(1_000), "1 KB")
        XCTAssertEqual(ByteFormatter.format(500_000), "500 KB")
        XCTAssertEqual(ByteFormatter.format(999_999), "999 KB")
    }

    func testFormatMegabytes() {
        XCTAssertEqual(ByteFormatter.format(1_000_000), "1 MB")
        XCTAssertEqual(ByteFormatter.format(500_000_000), "500 MB")
        XCTAssertEqual(ByteFormatter.format(999_999_999), "999 MB")
    }

    func testFormatGigabytes() {
        // Under 100 GB formats with 1 decimal place: "13.4 GB"
        XCTAssertEqual(ByteFormatter.format(13_400_000_000), "13.4 GB")
        XCTAssertEqual(ByteFormatter.format(1_000_000_000), "1.0 GB")
        XCTAssertEqual(ByteFormatter.format(99_900_000_000), "99.9 GB")

        // 100 GB and above formats with 0 decimal places: "135 GB"
        XCTAssertEqual(ByteFormatter.format(135_000_000_000), "135 GB")
    }

    func testFormatTerabytes() {
        // 1.0 TB-ish: 1_000_000_000_000 bytes
        XCTAssertEqual(ByteFormatter.format(1_000_000_000_000), "1.0 TB")
        XCTAssertEqual(ByteFormatter.format(2_500_000_000_000), "2.5 TB")
    }

    func testPartsSplitsValueAndUnit() {
        let p0 = ByteFormatter.parts(0)
        XCTAssertEqual(p0.value, "0")
        XCTAssertEqual(p0.unit, "B")

        let pKB = ByteFormatter.parts(42_000)
        XCTAssertEqual(pKB.value, "42")
        XCTAssertEqual(pKB.unit, "KB")

        let pMB = ByteFormatter.parts(250_000_000)
        XCTAssertEqual(pMB.value, "250")
        XCTAssertEqual(pMB.unit, "MB")

        let pGB = ByteFormatter.parts(13_400_000_000)
        XCTAssertEqual(pGB.value, "13.4")
        XCTAssertEqual(pGB.unit, "GB")

        let pTB = ByteFormatter.parts(1_000_000_000_000)
        XCTAssertEqual(pTB.value, "1.0")
        XCTAssertEqual(pTB.unit, "TB")
    }

    func testFormatSigned() {
        XCTAssertEqual(ByteFormatter.formatSigned(52_500_000_000), "+52.5 GB")
        XCTAssertEqual(ByteFormatter.formatSigned(-500_000), "-500 KB")
        XCTAssertEqual(ByteFormatter.formatSigned(0), "0 B")
    }
}
