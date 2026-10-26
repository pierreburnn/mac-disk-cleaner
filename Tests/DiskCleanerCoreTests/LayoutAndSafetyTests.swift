// LayoutAndSafetyTests.swift – Extra guarantees: treemap geometry on the demo
// tree, demo numbers shown in the UI, and "never touch anything unselected".
import XCTest
import Foundation
@testable import DiskCleanerCore

final class LayoutAndSafetyTests: XCTestCase {

    private func allNodes(_ n: FileNode) -> [FileNode] { [n] + n.children.flatMap(allNodes) }

    // MARK: Treemap

    func testDemoTreemapFillsAreaWithoutOverlap() {
        let tree = DemoData.makeTree()
        let box = TMRect(x: 0, y: 0, width: 747, height: 548)
        let items = TreemapLayout.layoutChildren(of: tree, in: box, minFraction: 0.002)
        XCTAssertFalse(items.isEmpty)
        let area = items.reduce(0.0) { $0 + $1.rect.area }
        XCTAssertEqual(area, box.area, accuracy: box.area * 0.001, "tiles must cover 100% of the treemap")
        for i in items.indices {
            let a = items[i].rect
            XCTAssertGreaterThanOrEqual(a.x, -0.001); XCTAssertGreaterThanOrEqual(a.y, -0.001)
            XCTAssertLessThanOrEqual(a.x + a.width, box.width + 0.001)
            XCTAssertLessThanOrEqual(a.y + a.height, box.height + 0.001)
            for j in items.indices where j > i {
                let b = items[j].rect
                let ow = max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x))
                let oh = max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
                XCTAssertLessThan(ow * oh, 0.01, "tiles \(i) and \(j) overlap")
            }
        }
    }

    func testDemoTreemapOrderMatchesReference() {
        let tree = DemoData.makeTree()
        let items = TreemapLayout.layoutChildren(of: tree, in: TMRect(x: 0, y: 0, width: 747, height: 548))
        func rect(_ name: String) -> TMRect? { items.first { $0.node?.name == name }?.rect }
        guard let desktop = rect("Desktop"), let library = rect("Library"),
              let ollama = rect(".ollama"), let npm = rect(".npm") else {
            return XCTFail("missing top-level tiles")
        }
        // Desktop top-left, Library below it, .ollama and .npm to the right.
        XCTAssertEqual(desktop.x, 0, accuracy: 0.5); XCTAssertEqual(desktop.y, 0, accuracy: 0.5)
        XCTAssertEqual(library.x, 0, accuracy: 0.5); XCTAssertGreaterThan(library.y, desktop.y)
        XCTAssertGreaterThan(ollama.x, desktop.x); XCTAssertEqual(ollama.y, 0, accuracy: 0.5)
        XCTAssertGreaterThan(npm.x, ollama.x)
    }

    func testNestedLayoutStaysInsideParent() {
        let tree = DemoData.makeTree()
        let desktop = tree.children.first { $0.name == "Desktop" }!
        let parent = TMRect(x: 10, y: 20, width: 300, height: 250)
        let items = TreemapLayout.layoutChildren(of: desktop, in: parent)
        let area = items.reduce(0.0) { $0 + $1.rect.area }
        XCTAssertEqual(area, parent.area, accuracy: parent.area * 0.001)
        for item in items {
            XCTAssertGreaterThanOrEqual(item.rect.x, parent.x - 0.001)
            XCTAssertGreaterThanOrEqual(item.rect.y, parent.y - 0.001)
            XCTAssertLessThanOrEqual(item.rect.x + item.rect.width, parent.x + parent.width + 0.001)
            XCTAssertLessThanOrEqual(item.rect.y + item.rect.height, parent.y + parent.height + 0.001)
        }
    }

    // MARK: Demo numbers (must match the reference design)

    func testDemoHeadlineNumbers() {
        let tree = DemoData.makeTree()
        XCTAssertEqual(ByteFormatter.format(tree.totalAllocatedSize), "135 GB")
        let desktop = tree.children.first { $0.name == "Desktop" }!
        XCTAssertEqual(ByteFormatter.format(desktop.totalAllocatedSize), "41.5 GB")
        let library = tree.children.first { $0.name == "Library" }!
        XCTAssertEqual(ByteFormatter.format(library.totalAllocatedSize), "17.1 GB")
        XCTAssertEqual(tree.children.first?.name, "Desktop", "largest folder first")

        let volume = DemoData.makeVolumeInfo()
        XCTAssertEqual(ByteFormatter.format(volume.notScanned(scannedTotal: tree.totalAllocatedSize)), "288 GB")
        let selected = DemoData.makeRecommendations()
            .filter { DemoData.defaultSelectedIDs.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.bytes }
        XCTAssertEqual(volume.freeAfterCleanup(selectedBytes: selected), 92_000_000_000)
    }

    func testDemoRecommendationPathsExistInTree() {
        let tree = DemoData.makeTree()
        let paths = Set(allNodes(tree).map { $0.url.path })
        for rec in DemoData.makeRecommendations() where rec.id != "trash" && rec.id != "ios-simulators"
            && rec.id != "huggingface-cache" {
            for p in rec.paths {
                let present = paths.contains(p) || paths.contains { $0.hasPrefix(p + "/") }
                XCTAssertTrue(present, "\(rec.id): \(p) is not in the demo tree")
            }
        }
    }

    // MARK: Script safety

    func testScriptOnlyRemovesSelectedPaths() throws {
        let home = "/Users/test user"
        let selected = Recommendation(
            id: "a", title: "A", displayPath: "~/a", paths: ["\(home)/Library/Caches/My App", "\(home)/it's here"],
            bytes: 10, safety: .safe, detail: "", command: .removePaths)
        let unselected = Recommendation(
            id: "b", title: "B", displayPath: "~/b", paths: ["\(home)/Documents"],
            bytes: 10, safety: .review, detail: "", command: .removePaths)
        _ = unselected
        let script = ScriptGenerator.makeScript(for: [selected], home: home)
        let rmLines = script.split(separator: "\n").filter { $0.contains("rm -rf") && !$0.hasPrefix("#") }
        XCTAssertEqual(rmLines.count, 2, "exactly one rm per selected path")
        XCTAssertFalse(script.contains("Documents"))
        XCTAssertTrue(rmLines.allSatisfy { $0.contains("\"$HOME\"/") }, "every rm is anchored to $HOME")
        XCTAssertTrue(rmLines.allSatisfy { $0.contains("-- ") }, "rm ends option parsing before the path")
        XCTAssertTrue(script.contains("'Library/Caches/My App'"), "spaces are quoted")
        XCTAssertTrue(script.contains(#"'it'\''s here'"#), "single quotes are escaped")
        XCTAssertFalse(script.contains("rm -rf /"), "never an absolute rm")
    }

    func testEmptySelectionProducesNoRemoval() {
        let script = ScriptGenerator.makeScript(for: [], home: "/Users/x")
        XCTAssertTrue(script.hasPrefix("#!/bin/bash"))
        XCTAssertTrue(script.contains("set -euo pipefail"))
        XCTAssertFalse(script.split(separator: "\n").contains { $0.contains("rm ") && !$0.hasPrefix("#") })
    }
}
