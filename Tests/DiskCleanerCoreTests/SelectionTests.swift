// SelectionTests.swift – Multi-selection, de-duplication, totals and batch Trash.
import XCTest
import Foundation
@testable import DiskCleanerCore

/// Records calls; fails for chosen paths.
private final class RecordingTrasher: TrashPerforming, @unchecked Sendable {
    var calls: [String] = []
    var failing: Set<String> = []
    func trashItem(at url: URL) throws -> URL? {
        if failing.contains(url.path) { throw CocoaError(.fileWriteNoPermission) }
        calls.append(url.path)
        return URL(fileURLWithPath: "/Users/pierre/.Trash/" + url.lastPathComponent)
    }
}

final class SelectionTests: XCTestCase {
    let home = "/Users/pierre"
    var policy: DeletionPolicy { DeletionPolicy(home: home) }

    private func file(_ rel: String, _ size: Int64) -> FileNode {
        FileNode(name: (rel as NSString).lastPathComponent, url: URL(fileURLWithPath: home + "/" + rel),
                 isDirectory: false, allocatedSize: size)
    }
    private func dir(_ rel: String, _ kids: [FileNode]) -> FileNode {
        FileNode(name: (rel as NSString).lastPathComponent,
                 url: URL(fileURLWithPath: rel.isEmpty ? home : home + "/" + rel),
                 isDirectory: true, children: kids)
    }

    /// ~ (1000+...) with Desktop/proj/{node_modules 300, src 50}, Desktop/notes 20,
    /// .npm 400, Library/Caches/pip 100.
    private func makeTree() -> FileNode {
        dir("", [
            dir("Desktop", [
                dir("Desktop/proj", [file("Desktop/proj/node_modules", 300), file("Desktop/proj/src", 50)]),
                file("Desktop/notes", 20),
            ]),
            file(".npm", 400),
            dir("Library", [dir("Library/Caches", [file("Library/Caches/pip", 100)])]),
        ])
    }

    private func rec(_ id: String, _ rels: [String], bytes: Int64 = 0) -> Recommendation {
        Recommendation(id: id, title: id, displayPath: "~/" + rels[0], paths: rels.map { home + "/" + $0 },
                       bytes: bytes, safety: .safe, detail: "", command: .removePaths)
    }

    // MARK: Multi-selection

    func testToggleAddsThenRemoves() {
        var sel = ExplorerSelection()
        XCTAssertTrue(sel.toggle("/Users/pierre/a"))
        XCTAssertTrue(sel.toggle("/Users/pierre/b"))
        XCTAssertEqual(sel.items.map(\.path), ["/Users/pierre/a", "/Users/pierre/b"])
        XCTAssertTrue(sel.items.allSatisfy(\.checked))
        XCTAssertFalse(sel.toggle("/Users/pierre/a"), "second click removes")
        XCTAssertEqual(sel.items.map(\.path), ["/Users/pierre/b"])
        XCTAssertFalse(sel.contains("/Users/pierre/a"))
    }

    func testUncheckKeepsItemButExcludesIt() {
        var sel = ExplorerSelection()
        sel.toggle("/x/a"); sel.toggle("/x/b")
        sel.setChecked("/x/a", false)
        XCTAssertEqual(sel.count, 2)
        XCTAssertEqual(sel.checkedPaths, ["/x/b"])
        sel.remove("/x/b")
        XCTAssertEqual(sel.checkedPaths, [])
        sel.clear()
        XCTAssertTrue(sel.isEmpty)
    }

    func testRemoveCovered() {
        var sel = ExplorerSelection()
        sel.toggle("/h/a/b"); sel.toggle("/h/c"); sel.toggle("/h/ab")
        sel.removeCovered(by: ["/h/a"])
        XCTAssertEqual(sel.items.map(\.path), ["/h/c", "/h/ab"])
    }

    // MARK: De-duplication

    func testDedupeParentChildAndDuplicates() {
        let out = SelectionPlanner.dedupe(["/h/a/b", "/h/a", "/h/a/", "/h/ab", "/h/a/b/c", "/h/x"])
        XCTAssertEqual(out, ["/h/a", "/h/ab", "/h/x"])
    }

    func testDedupeIsPrefixSafe() {
        XCTAssertTrue(SelectionPlanner.isSameOrInside("/h/a/b", "/h/a"))
        XCTAssertFalse(SelectionPlanner.isSameOrInside("/h/ab", "/h/a"))
        XCTAssertTrue(SelectionPlanner.isSameOrInside("/h/a", "/h/a"))
    }

    func testNodeLookup() {
        let root = makeTree()
        XCTAssertEqual(SelectionPlanner.node(atPath: home + "/Desktop/proj/src", in: root)?.name, "src")
        XCTAssertNil(SelectionPlanner.node(atPath: home + "/Desktop/pro", in: root))
        XCTAssertTrue(SelectionPlanner.node(atPath: home, in: root) === root)
    }

    // MARK: Totals

    func testTotalDoesNotDoubleCountNestedPaths() {
        let root = makeTree()
        let entries = [
            SelectionEntry.tile(SelectionPlanner.node(atPath: home + "/Desktop/proj", in: root)!),           // 350
            SelectionEntry.tile(SelectionPlanner.node(atPath: home + "/Desktop/proj/node_modules", in: root)!), // inside
            SelectionEntry.recommendation(rec("nm", ["Desktop/proj/node_modules"], bytes: 300)),            // inside
            SelectionEntry.recommendation(rec("npm", [".npm"], bytes: 400)),
        ]
        let plan = SelectionPlanner.plan(entries: entries, root: root, policy: policy)
        XCTAssertEqual(plan.targets.map(\.path), [home + "/Desktop/proj", home + "/.npm"])
        XCTAssertEqual(plan.selectedBytes, 750)
        XCTAssertEqual(plan.trashableBytes, 750)
        XCTAssertEqual(Set(plan.targets[0].entryIDs),
                       ["tile:\(home)/Desktop/proj", "tile:\(home)/Desktop/proj/node_modules", "rec:nm"])
    }

    func testRecommendationWithChildInsideTileCountsOnce() {
        let root = makeTree()
        let entries = [
            SelectionEntry.recommendation(rec("multi", ["Desktop/proj/node_modules", "Library/Caches/pip"])),
            SelectionEntry.tile(SelectionPlanner.node(atPath: home + "/Desktop", in: root)!), // 370
        ]
        let plan = SelectionPlanner.plan(entries: entries, root: root, policy: policy)
        // ~/Desktop is protected: selected (counted once) but refused.
        XCTAssertEqual(plan.selectedBytes, 370 + 100)
        XCTAssertEqual(plan.targets.map(\.path), [home + "/Library/Caches/pip"])
        XCTAssertEqual(plan.refused.map(\.path), [home + "/Desktop"])
        XCTAssertEqual(plan.refused.first?.refusal, .protectedFolder("Desktop"))
        XCTAssertEqual(plan.trashableBytes, 100)
    }

    func testFallbackBytesForPathsNotInTree() {
        let root = makeTree()
        let plan = SelectionPlanner.plan(entries: [.recommendation(rec("gone", ["missing/a", "missing/b"], bytes: 1000))],
                                         root: root, policy: policy)
        XCTAssertEqual(plan.selectedBytes, 1000)
        XCTAssertEqual(plan.targets.count, 2)
    }

    // MARK: Batch Trash

    func testMixedBatchTilesAndRecommendations() {
        let root = makeTree()
        let before = root.totalAllocatedSize
        XCTAssertEqual(before, 870)
        let entries = [
            SelectionEntry.tile(SelectionPlanner.node(atPath: home + "/Desktop/notes", in: root)!),
            SelectionEntry.recommendation(rec("npm", [".npm"])),
            SelectionEntry.recommendation(rec("pip", ["Library/Caches/pip"])),
        ]
        let plan = SelectionPlanner.plan(entries: entries, root: root, policy: policy)
        let trasher = RecordingTrasher()
        let result = BatchTrasher.run(plan: plan, root: root, policy: policy, trasher: trasher, checkExistence: false)
        XCTAssertEqual(trasher.calls, [home + "/Desktop/notes", home + "/.npm", home + "/Library/Caches/pip"])
        XCTAssertEqual(result.trashed.count, 3)
        XCTAssertEqual(result.trashedBytes, 520)
        XCTAssertEqual(result.problemCount, 0)
        XCTAssertEqual(root.totalAllocatedSize, before - 520)
        XCTAssertNil(SelectionPlanner.node(atPath: home + "/.npm", in: root))
        XCTAssertEqual(SelectionPlanner.node(atPath: home + "/Library", in: root)?.totalAllocatedSize, 0)
    }

    func testPartialRefusalAndErrorsAreReportedAndSkipped() {
        let root = makeTree()
        let entries = [
            SelectionEntry.tile(SelectionPlanner.node(atPath: home + "/Library", in: root)!),   // protected
            SelectionEntry.recommendation(rec("outside", ["../other/x"])),                      // outside home
            SelectionEntry.recommendation(rec("npm", [".npm"])),                                 // ok
            SelectionEntry.tile(SelectionPlanner.node(atPath: home + "/Desktop/proj/src", in: root)!), // will fail
            SelectionEntry(id: "home", kind: .tile, title: "~", paths: [home], fallbackBytes: 0), // ~ itself
        ]
        let plan = SelectionPlanner.plan(entries: entries, root: root, policy: policy)
        // ~ contains everything, so de-duplication keeps only ~ … which is refused.
        XCTAssertEqual(plan.targets.count, 0)
        XCTAssertEqual(plan.refused.map(\.refusal), [.outsideHome, .isHome])

        // Without ~: protected + outside refused, one failure, one success.
        let plan2 = SelectionPlanner.plan(entries: Array(entries.dropLast()), root: root, policy: policy)
        let trasher = RecordingTrasher()
        trasher.failing = [home + "/Desktop/proj/src"]
        let result = BatchTrasher.run(plan: plan2, root: root, policy: policy, trasher: trasher, checkExistence: false)
        XCTAssertEqual(trasher.calls, [home + "/.npm"], "refused paths never reach the trasher")
        XCTAssertEqual(result.trashed.map(\.path), [home + "/.npm"])
        XCTAssertEqual(Set(result.refused.map(\.path)), [home + "/Library", "/Users/other/x"])
        XCTAssertEqual(result.failed.map(\.path), [home + "/Desktop/proj/src"])
        XCTAssertEqual(result.problemCount, 3)
        XCTAssertNotNil(SelectionPlanner.node(atPath: home + "/Desktop/proj/src", in: root), "failed item stays in tree")
        XCTAssertEqual(root.totalAllocatedSize, 870 - 400)
    }

    func testBatchRechecksExistenceOnDisk() throws {
        let tmp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("SelectionTests-\(UUID().uuidString)")
        let h = tmp.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: h.appendingPathComponent("keep"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let p = DeletionPolicy(home: h.path)
        let plan = SelectionPlanner.plan(entries: [
            SelectionEntry(id: "a", kind: .tile, title: "keep", paths: [h.appendingPathComponent("keep").path], fallbackBytes: 1),
            SelectionEntry(id: "b", kind: .tile, title: "gone", paths: [h.appendingPathComponent("gone").path], fallbackBytes: 1),
        ], root: nil, policy: p)
        let trasher = RecordingTrasher()
        let result = BatchTrasher.run(plan: plan, root: nil, policy: p, trasher: trasher)
        XCTAssertEqual(trasher.calls, [h.appendingPathComponent("keep").path])
        XCTAssertEqual(result.refused.map(\.refusal), [.doesNotExist])
    }

    func testDemoTreeSelectionPlanUsesTreeSizes() {
        let root = DemoData.makeTree()
        let recs = DemoData.makeRecommendations()
        let policy = DeletionPolicy(home: DemoData.homePath)
        let npm = recs.first { $0.id == "npm-cache" }!
        let npmNode = SelectionPlanner.node(atPath: DemoData.homePath + "/.npm", in: root)!
        // Tile + recommendation for the same folder count once.
        let plan = SelectionPlanner.plan(entries: [.tile(npmNode), .recommendation(npm)], root: root, policy: policy)
        XCTAssertEqual(plan.selectedBytes, npmNode.totalAllocatedSize)
        XCTAssertEqual(plan.targets.count, 1)
    }

    func testFileManagerTrasherConformsToTrashPerforming() {
        let trasher: any TrashPerforming = FileManagerTrasher()
        #if !os(macOS)
        XCTAssertThrowsError(try trasher.trashItem(at: URL(fileURLWithPath: "/tmp/nonexistent")))
        #else
        _ = trasher
        #endif
    }

    func testEmptySelectionPlanIsEmpty() {
        let plan = SelectionPlanner.plan(entries: [], root: nil, policy: policy)
        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.selectedBytes, 0)
        XCTAssertEqual(plan.trashableBytes, 0)
        XCTAssertTrue(plan.targets.isEmpty)
        XCTAssertTrue(plan.refused.isEmpty)
    }
}
