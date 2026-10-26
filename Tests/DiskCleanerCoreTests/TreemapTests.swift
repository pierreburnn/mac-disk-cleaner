// TreemapTests.swift – Tests for TreemapLayout squarified algorithm
import XCTest
import Foundation
@testable import DiskCleanerCore

final class TreemapTests: XCTestCase {

    func testLayoutSquarifiedProperties() {
        let sizes = [6.0, 6.0, 4.0, 3.0, 2.0, 2.0, 1.0]
        let container = TMRect(x: 0, y: 0, width: 600, height: 400)
        let rects = TreemapLayout.layout(sizes: sizes, in: container)

        // 1. Count equal
        XCTAssertEqual(rects.count, sizes.count, "Result count should match input sizes count")

        // 2. Each rect inside bounds (tolerance 0.001)
        for (i, r) in rects.enumerated() {
            XCTAssertGreaterThanOrEqual(r.minX, container.minX - 0.001, "Rect \(i) minX out of bounds")
            XCTAssertGreaterThanOrEqual(r.minY, container.minY - 0.001, "Rect \(i) minY out of bounds")
            XCTAssertLessThanOrEqual(r.maxX, container.maxX + 0.001, "Rect \(i) maxX out of bounds")
            XCTAssertLessThanOrEqual(r.maxY, container.maxY + 0.001, "Rect \(i) maxY out of bounds")
            XCTAssertGreaterThanOrEqual(r.width, 0, "Rect \(i) width must be non-negative")
            XCTAssertGreaterThanOrEqual(r.height, 0, "Rect \(i) height must be non-negative")
        }

        // 3. Sum of areas ≈ container area (1%)
        let totalContainerArea = container.area
        let sumArea = rects.reduce(0.0) { $0 + $1.area }
        XCTAssertEqual(sumArea, totalContainerArea, accuracy: totalContainerArea * 0.01, "Sum of areas should equal container area within 1%")

        // 4. Areas proportional to sizes (2%)
        let totalSize = sizes.reduce(0.0, +)
        for (i, s) in sizes.enumerated() {
            let expectedFraction = s / totalSize
            let actualFraction = rects[i].area / totalContainerArea
            XCTAssertEqual(actualFraction, expectedFraction, accuracy: 0.02, "Rect \(i) area fraction should be within 2% of size fraction")
        }

        // 5. No pairwise overlaps (intersection area < 0.01)
        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count {
                let r1 = rects[i]
                let r2 = rects[j]
                let overlapW = max(0.0, min(r1.maxX, r2.maxX) - max(r1.minX, r2.minX))
                let overlapH = max(0.0, min(r1.maxY, r2.maxY) - max(r1.minY, r2.minY))
                let overlapArea = overlapW * overlapH
                XCTAssertLessThan(overlapArea, 0.01, "Pair (\(i), \(j)) overlaps with area \(overlapArea)")
            }
        }
    }

    func testZeroAndNegativeSizesProduceZeroArea() {
        let container = TMRect(x: 0, y: 0, width: 400, height: 300)

        // Mixed with positives
        let sizes = [0.0, 10.0, -5.0, 0.0]
        let rects = TreemapLayout.layout(sizes: sizes, in: container)
        XCTAssertEqual(rects.count, sizes.count)
        XCTAssertEqual(rects[0].area, 0.0, accuracy: 0.0001)
        XCTAssertEqual(rects[2].area, 0.0, accuracy: 0.0001)
        XCTAssertEqual(rects[3].area, 0.0, accuracy: 0.0001)
        XCTAssertEqual(rects[1].area, container.area, accuracy: 0.001)

        // All zeros
        let allZero = [0.0, 0.0, 0.0]
        let allZeroRects = TreemapLayout.layout(sizes: allZero, in: container)
        XCTAssertEqual(allZeroRects.count, 3)
        for r in allZeroRects {
            XCTAssertEqual(r.area, 0.0, accuracy: 0.0001)
        }
    }

    func testSingleItemFillsRect() {
        let container = TMRect(x: 10, y: 20, width: 500, height: 300)
        let rects = TreemapLayout.layout(sizes: [42.0], in: container)

        XCTAssertEqual(rects.count, 1)
        XCTAssertEqual(rects[0].x, container.x, accuracy: 0.001)
        XCTAssertEqual(rects[0].y, container.y, accuracy: 0.001)
        XCTAssertEqual(rects[0].width, container.width, accuracy: 0.001)
        XCTAssertEqual(rects[0].height, container.height, accuracy: 0.001)
        XCTAssertEqual(rects[0].area, container.area, accuracy: 0.001)
    }

    func testEmptyInputProducesEmptyOutput() {
        let container = TMRect(x: 0, y: 0, width: 200, height: 200)
        let rects = TreemapLayout.layout(sizes: [], in: container)
        XCTAssertTrue(rects.isEmpty, "Empty input sizes should produce empty output rects")
    }

    func testLayoutChildrenOfFileNode() {
        let container = TMRect(x: 0, y: 0, width: 800, height: 600)
        let parentURL = URL(fileURLWithPath: "/Users/test")
        let child1 = FileNode(name: "A", url: parentURL.appendingPathComponent("A"), isDirectory: false, allocatedSize: 6_000_000)
        let child2 = FileNode(name: "B", url: parentURL.appendingPathComponent("B"), isDirectory: false, allocatedSize: 4_000_000)
        let root = FileNode(name: "root", url: parentURL, isDirectory: true, children: [child1, child2])

        let results = TreemapLayout.layoutChildren(of: root, in: container)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].node?.name, "A")
        XCTAssertEqual(results[1].node?.name, "B")
        XCTAssertGreaterThan(results[0].rect.area, 0)
        XCTAssertGreaterThan(results[1].rect.area, 0)
    }
}
