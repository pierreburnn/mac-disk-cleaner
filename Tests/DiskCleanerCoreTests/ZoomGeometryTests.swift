// ZoomGeometryTests.swift – Tests for Treemap pure geometry and ZoomGeometry animations
import XCTest
import Foundation
@testable import DiskCleanerCore

final class ZoomGeometryTests: XCTestCase {
    let testSizes: [CGSize] = [
        CGSize(width: 636, height: 470),
        CGSize(width: 1200, height: 800)
    ]

    func testZoomedLayoutCoversWholeArea() {
        let root = DemoData.makeTree()
        guard let desktop = root.children.first(where: { $0.name == "Desktop" }) else {
            return XCTFail("Desktop node not found")
        }
        let outerGap = TreemapGeometry.outerGap

        for size in testSizes {
            let W = size.width
            let H = size.height
            let items = TreemapGeometry.items(for: desktop, in: size)
            let topItems = items.filter { $0.level == .top }
            XCTAssertFalse(topItems.isEmpty, "Top-level items should not be empty for size \(size)")

            // 1. Every rect lies inside (0,0,W,H) with no overflow (tolerance 0.5)
            for item in topItems {
                let r = item.rect
                XCTAssertGreaterThanOrEqual(r.minX, -0.5, "Rect minX out of bounds for \(item.id)")
                XCTAssertGreaterThanOrEqual(r.minY, -0.5, "Rect minY out of bounds for \(item.id)")
                XCTAssertLessThanOrEqual(r.maxX, W + 0.5, "Rect maxX out of bounds for \(item.id)")
                XCTAssertLessThanOrEqual(r.maxY, H + 0.5, "Rect maxY out of bounds for \(item.id)")
            }

            // 2. The union bounding box spans from <= outerGap to >= W-outerGap and H-outerGap
            var unionRect = CGRect.null
            for item in topItems {
                unionRect = unionRect.union(item.rect)
            }
            XCTAssertLessThanOrEqual(unionRect.minX, outerGap + 0.5, "Union minX should be <= outerGap")
            XCTAssertLessThanOrEqual(unionRect.minY, outerGap + 0.5, "Union minY should be <= outerGap")
            XCTAssertGreaterThanOrEqual(unionRect.maxX, W - outerGap - 0.5, "Union maxX should be >= W - outerGap")
            XCTAssertGreaterThanOrEqual(unionRect.maxY, H - outerGap - 0.5, "Union maxY should be >= H - outerGap")

            // 3. The sum of the areas of the top-level rects, each expanded by outerGap on every side, is >= 98% of W*H
            let totalArea = W * H
            let expandedAreaSum = topItems.reduce(0.0) { sum, item in
                let r = item.rect
                let expanded = r.insetBy(dx: -outerGap, dy: -outerGap)
                return sum + expanded.width * expanded.height
            }
            XCTAssertGreaterThanOrEqual(expandedAreaSum, totalArea * 0.98, "Expanded top-level area should be >= 98% of total area")

            // 4. No two top-level rects overlap (intersection area < 1)
            for i in 0..<topItems.count {
                for j in (i + 1)..<topItems.count {
                    let r1 = topItems[i].rect
                    let r2 = topItems[j].rect
                    let intersection = r1.intersection(r2)
                    let area = intersection.isNull ? 0.0 : intersection.width * intersection.height
                    XCTAssertLessThan(area, 1.0, "Top items \(i) and \(j) overlap with area \(area)")
                }
            }
        }
    }

    func testAnimationFinalStateEqualsFinalLayout() {
        let root = DemoData.makeTree()
        guard let desktop = root.children.first(where: { $0.name == "Desktop" }) else {
            return XCTFail("Desktop node not found")
        }

        for size in testSizes {
            guard let startRect = ZoomGeometry.startRect(of: desktop, in: root, size: size) else {
                return XCTFail("startRect returned nil for size \(size)")
            }
            let bounds = CGRect(origin: .zero, size: size)
            let frameAtOne = ZoomGeometry.frame(from: startRect, to: bounds, progress: 1)
            XCTAssertEqual(frameAtOne.origin.x, bounds.origin.x, accuracy: 0.01)
            XCTAssertEqual(frameAtOne.origin.y, bounds.origin.y, accuracy: 0.01)
            XCTAssertEqual(frameAtOne.size.width, bounds.size.width, accuracy: 0.01)
            XCTAssertEqual(frameAtOne.size.height, bounds.size.height, accuracy: 0.01)

            let animChildren = ZoomGeometry.animatedChildren(of: desktop, bounds: size, startRect: startRect, progress: 1)
            let items = TreemapGeometry.items(for: desktop, in: size)
            XCTAssertEqual(animChildren.count, items.count)

            for (animRect, item) in zip(animChildren, items) {
                XCTAssertEqual(animRect.origin.x, item.rect.origin.x, accuracy: 0.01)
                XCTAssertEqual(animRect.origin.y, item.rect.origin.y, accuracy: 0.01)
                XCTAssertEqual(animRect.size.width, item.rect.size.width, accuracy: 0.01)
                XCTAssertEqual(animRect.size.height, item.rect.size.height, accuracy: 0.01)
            }
        }
    }

    func testIntermediateFrameContainsChildren() {
        let root = DemoData.makeTree()
        guard let desktop = root.children.first(where: { $0.name == "Desktop" }) else {
            return XCTFail("Desktop node not found")
        }

        for size in testSizes {
            guard let startRect = ZoomGeometry.startRect(of: desktop, in: root, size: size) else {
                return XCTFail("startRect returned nil for size \(size)")
            }
            let bounds = CGRect(origin: .zero, size: size)
            let finalItems = TreemapGeometry.items(for: desktop, in: size)

            for progress in [CGFloat(0.25), CGFloat(0.55), CGFloat(0.8)] {
                let frame = ZoomGeometry.frame(from: startRect, to: bounds, progress: progress)
                let animatedChildren = ZoomGeometry.animatedChildren(of: desktop, bounds: size, startRect: startRect, progress: progress)

                // 1. animatedChildren is non-empty and has the same count as the final items
                XCTAssertFalse(animatedChildren.isEmpty)
                XCTAssertEqual(animatedChildren.count, finalItems.count)

                // 2. every rect is inside the interpolated frame (tolerance 0.5)
                for r in animatedChildren {
                    XCTAssertGreaterThanOrEqual(r.minX, frame.minX - 0.5, "minX out of interpolated frame")
                    XCTAssertGreaterThanOrEqual(r.minY, frame.minY - 0.5, "minY out of interpolated frame")
                    XCTAssertLessThanOrEqual(r.maxX, frame.maxX + 0.5, "maxX out of interpolated frame")
                    XCTAssertLessThanOrEqual(r.maxY, frame.maxY + 0.5, "maxY out of interpolated frame")
                }

                // 3. at least 3 rects have width > 10 and height > 10
                let largeCount = animatedChildren.filter { $0.width > 10 && $0.height > 10 }.count
                XCTAssertGreaterThanOrEqual(largeCount, 3, "Expected at least 3 rects with w>10 and h>10 at progress \(progress), got \(largeCount)")
            }
        }
    }

    func testStartRectMatchesParentLayout() {
        let root = DemoData.makeTree()
        guard let desktop = root.children.first(where: { $0.name == "Desktop" }) else {
            return XCTFail("Desktop node not found")
        }

        for size in testSizes {
            let startRect = ZoomGeometry.startRect(of: desktop, in: root, size: size)
            XCTAssertNotNil(startRect)
            let rootItems = TreemapGeometry.items(for: root, in: size)
            guard let desktopItem = rootItems.first(where: { $0.level == .top && $0.node?.name == "Desktop" }) else {
                return XCTFail("Desktop item not found in root items for size \(size)")
            }
            XCTAssertEqual(startRect!.origin.x, desktopItem.rect.origin.x, accuracy: 0.01)
            XCTAssertEqual(startRect!.origin.y, desktopItem.rect.origin.y, accuracy: 0.01)
            XCTAssertEqual(startRect!.size.width, desktopItem.rect.size.width, accuracy: 0.01)
            XCTAssertEqual(startRect!.size.height, desktopItem.rect.size.height, accuracy: 0.01)

            let bounds = CGRect(origin: .zero, size: size)
            let frameAtZero = ZoomGeometry.frame(from: startRect!, to: bounds, progress: 0)
            XCTAssertEqual(frameAtZero.origin.x, startRect!.origin.x, accuracy: 0.01)
            XCTAssertEqual(frameAtZero.origin.y, startRect!.origin.y, accuracy: 0.01)
            XCTAssertEqual(frameAtZero.size.width, startRect!.size.width, accuracy: 0.01)
            XCTAssertEqual(frameAtZero.size.height, startRect!.size.height, accuracy: 0.01)
        }
    }

    func testProgressClamping() {
        let start = CGRect(x: 10, y: 20, width: 100, height: 80)
        let end = CGRect(x: 0, y: 0, width: 800, height: 600)

        let frameNeg = ZoomGeometry.frame(from: start, to: end, progress: -1)
        let frameZero = ZoomGeometry.frame(from: start, to: end, progress: 0)
        XCTAssertEqual(frameNeg, frameZero)

        let frameTwo = ZoomGeometry.frame(from: start, to: end, progress: 2)
        let frameOne = ZoomGeometry.frame(from: start, to: end, progress: 1)
        XCTAssertEqual(frameTwo, frameOne)
    }
}
