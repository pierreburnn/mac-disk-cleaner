// SelectionMarksTests.swift – Tests for SelectionMarks and selection outline attribution
import XCTest
import Foundation
@testable import DiskCleanerCore

final class SelectionMarksTests: XCTestCase {

    let root = DemoData.makeTree()
    let size = CGSize(width: 636, height: 470)

    func testDirectMarkForDrawnNode() {
        let items = TreemapGeometry.items(for: root, in: size)
        let oldSaasPath = "/Users/pierre/Desktop/old-saas"
        guard let oldSaasItem = items.first(where: { $0.node?.url.path == oldSaasPath }) else {
            XCTFail("Desktop/old-saas should be drawn in root treemap at 636x470")
            return
        }

        let marks = SelectionMarks.marks(items: items, selectedPaths: [oldSaasPath], displayedNodePath: root.url.path)
        XCTAssertEqual(marks[oldSaasItem.id]?.direct, true)
        XCTAssertEqual(marks[oldSaasItem.id]?.hiddenCount, 0)

        let counts = SelectionMarks.selectionMarks(items: items, selectedPaths: [oldSaasPath], displayedNodePath: root.url.path)
        XCTAssertEqual(counts[oldSaasItem.id], 1)
        XCTAssertEqual(SelectionMarks.visibleCount(items: items, selectedPaths: [oldSaasPath], displayedNodePath: root.url.path), 1)
    }

    func testInstallerDmgAttributedToDownloadsAsHidden() {
        let items = TreemapGeometry.items(for: root, in: size)
        let installerPath = "/Users/pierre/Downloads/installer.dmg"

        // Verify installer.dmg is NOT drawn as its own item at the root level
        XCTAssertFalse(items.contains(where: { $0.node?.url.path == installerPath }))

        // Find Downloads tile (or its bucket)
        guard let downloadsItem = items.first(where: {
            $0.node?.url.path == "/Users/pierre/Downloads" || $0.parent?.url.path == "/Users/pierre/Downloads"
        }) else {
            XCTFail("Downloads tile or its bucket should be present in root layout")
            return
        }

        let marks = SelectionMarks.marks(items: items, selectedPaths: [installerPath], displayedNodePath: root.url.path)
        let mark = marks[downloadsItem.id]
        XCTAssertNotNil(mark, "Downloads item should have received the mark for installer.dmg")
        XCTAssertEqual(mark?.direct, false)
        XCTAssertEqual(mark?.hiddenCount, 1)

        let counts = SelectionMarks.selectionMarks(items: items, selectedPaths: [installerPath], displayedNodePath: root.url.path)
        XCTAssertEqual(counts[downloadsItem.id], 1)
        XCTAssertEqual(SelectionMarks.visibleCount(items: items, selectedPaths: [installerPath], displayedNodePath: root.url.path), 1)
    }

    func testInvariantDirectPlusHiddenEqualsSelectedInsideDisplayedNode() {
        let items = TreemapGeometry.items(for: root, in: size)
        let selectedPaths = [
            "/Users/pierre/Desktop/old-saas",
            "/Users/pierre/Desktop/dotfiles",
            "/Users/pierre/Downloads/installer.dmg",
            "/Users/pierre/Downloads/dataset.zip",
            "/Users/pierre/Desktop/old-saas/src"
        ]

        let marks = SelectionMarks.marks(items: items, selectedPaths: selectedPaths, displayedNodePath: root.url.path)
        let sumDirect = marks.values.filter(\.direct).count
        let sumHidden = marks.values.reduce(0) { $0 + $1.hiddenCount }

        // All 5 paths are inside root, so direct + hidden must equal 5
        XCTAssertEqual(sumDirect + sumHidden, selectedPaths.count)
        XCTAssertEqual(SelectionMarks.visibleCount(items: items, selectedPaths: selectedPaths, displayedNodePath: root.url.path), selectedPaths.count)
    }

    func testSelectedPathOutsideDisplayedNodeIsIgnored() {
        let desktop = SelectionPlanner.node(atPath: "/Users/pierre/Desktop", in: root)!
        let desktopItems = TreemapGeometry.items(for: desktop, in: size)
        let selectedPaths = [
            "/Users/pierre/Desktop/old-saas",
            "/Users/pierre/Desktop/dotfiles",
            "/Users/pierre/Downloads/installer.dmg" // outside Desktop
        ]

        let marks = SelectionMarks.marks(items: desktopItems, selectedPaths: selectedPaths, displayedNodePath: desktop.url.path)
        let sumDirect = marks.values.filter(\.direct).count
        let sumHidden = marks.values.reduce(0) { $0 + $1.hiddenCount }

        // Only the 2 Desktop paths are inside the displayed node; Downloads/installer.dmg is ignored
        XCTAssertEqual(sumDirect + sumHidden, 2)
        XCTAssertEqual(SelectionMarks.visibleCount(items: desktopItems, selectedPaths: selectedPaths, displayedNodePath: desktop.url.path), 2)
    }

    func testTrashCountEqualsPlanTargetsCountForMixedBatch() {
        let policy = DeletionPolicy(home: "/Users/pierre")
        let oldSaas = SelectionPlanner.node(atPath: "/Users/pierre/Desktop/old-saas", in: root)!
        let dotfiles = SelectionPlanner.node(atPath: "/Users/pierre/Desktop/dotfiles", in: root)!

        let tileEntries = [
            SelectionEntry.tile(oldSaas),
            SelectionEntry.tile(dotfiles)
        ]
        let recs = DemoData.makeRecommendations()
        let recEntries = recs.prefix(3).map { SelectionEntry.recommendation($0) }
        let allEntries = tileEntries + Array(recEntries)

        let plan = SelectionPlanner.plan(entries: allEntries, root: root, policy: policy)
        let trashCount = plan.targets.count

        XCTAssertGreaterThan(trashCount, 0)
        XCTAssertEqual(trashCount, plan.targets.count)

        // Test the footer summary helper
        let summary = SelectionPlanner.footerSelectionSummary(itemCount: allEntries.count, targetCount: trashCount)
        if trashCount != allEntries.count {
            let expectedChemins = trashCount == 1 ? "1 chemin" : "\(trashCount) chemins"
            XCTAssertTrue(summary.contains(expectedChemins), "Summary '\(summary)' should contain '\(expectedChemins)'")
        } else {
            XCTAssertEqual(summary, "\(allEntries.count) items")
        }
    }
}
