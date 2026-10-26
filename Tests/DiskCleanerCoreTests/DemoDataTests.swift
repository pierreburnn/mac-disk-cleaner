// DemoDataTests.swift – Tests for DemoData models, recommendations, and formatting
import XCTest
import Foundation
@testable import DiskCleanerCore

final class DemoDataTests: XCTestCase {

    func testDemoRecommendationsSafeGroup() {
        let recs = DemoData.makeRecommendations()
        let safeRecs = recs.filter { $0.safety == .safe }

        // safe total formats to "41.7 GB" with 5 items
        XCTAssertEqual(safeRecs.count, 5, "Safe recommendations should have 5 items")
        let safeTotal = safeRecs.reduce(Int64(0)) { $0 + $1.bytes }
        XCTAssertEqual(ByteFormatter.format(safeTotal), "41.7 GB", "Safe recommendations total should format to '41.7 GB'")
    }

    func testDemoRecommendationsReviewGroup() {
        let recs = DemoData.makeRecommendations()
        let reviewRecs = recs.filter { $0.safety == .review }

        // review "56.0 GB" with 7 items
        XCTAssertEqual(reviewRecs.count, 7, "Review recommendations should have 7 items")
        let reviewTotal = reviewRecs.reduce(Int64(0)) { $0 + $1.bytes }
        XCTAssertEqual(ByteFormatter.format(reviewTotal), "56.0 GB", "Review recommendations total should format to '56.0 GB'")
    }

    func testDemoDefaultSelectedTotal() {
        let recs = DemoData.makeRecommendations()
        let selectedIDs = DemoData.defaultSelectedIDs
        let selectedRecs = recs.filter { selectedIDs.contains($0.id) }

        // default selected total "52.5 GB" with 5 items
        XCTAssertEqual(selectedRecs.count, 5, "Default selected recommendations should have 5 items")
        let selectedTotal = selectedRecs.reduce(Int64(0)) { $0 + $1.bytes }
        XCTAssertEqual(ByteFormatter.format(selectedTotal), "52.5 GB", "Default selected total should format to '52.5 GB'")
    }

    func testDemoTreeTotalFormatting() {
        let tree = DemoData.makeTree()
        let totalBytes = tree.totalAllocatedSize

        // ByteFormatter uses %.0f for gb >= 100, so 135 GB formats to "135 GB" (not "135.0 GB")
        let formatted = ByteFormatter.format(totalBytes)
        XCTAssertEqual(formatted, "135 GB", "Tree total allocated bytes should format to '135 GB'")
    }

    func testDemoVolumeInfo() {
        let vol = DemoData.makeVolumeInfo()
        XCTAssertEqual(ByteFormatter.format(vol.availableCapacity), "39.5 GB")

        let scannedTotal: Int64 = 135_000_000_000 // 135 GB
        let notScanned = vol.notScanned(scannedTotal: scannedTotal)
        XCTAssertEqual(notScanned, 288_000_000_000) // 288 GB

        let cleanup52_5: Int64 = 52_500_000_000
        XCTAssertEqual(vol.freeAfterCleanup(selectedBytes: cleanup52_5), 92_000_000_000)
    }
}
