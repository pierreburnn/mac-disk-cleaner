// DeletionTests.swift – Tests for DeletionPolicy, FileTreeEditor, and Trash integration.
import XCTest
import Foundation
@testable import DiskCleanerCore

// MARK: - Mock Trasher

final class MockTrasher: TrashPerforming, @unchecked Sendable {
    var trashedURLs: [URL] = []
    var errorToThrow: Error?
    var moveDestination: URL?

    init(errorToThrow: Error? = nil, moveDestination: URL? = nil) {
        self.errorToThrow = errorToThrow
        self.moveDestination = moveDestination
    }

    func trashItem(at url: URL) throws -> URL? {
        if let error = errorToThrow {
            throw error
        }
        trashedURLs.append(url)
        if let destination = moveDestination {
            let target = destination.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
        return url.deletingLastPathComponent().appendingPathComponent(".Trash/\(url.lastPathComponent)")
    }
}

private struct MockError: Error, Equatable {
    let message: String
}

// MARK: - Test Suite

final class DeletionTests: XCTestCase {

    private var tempDirectoriesToCleanUp: [URL] = []

    override func tearDown() {
        for url in tempDirectoriesToCleanUp {
            try? FileManager.default.removeItem(at: url)
        }
        tempDirectoriesToCleanUp.removeAll()
        super.tearDown()
    }

    private func createUniqueTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent("DeletionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectoriesToCleanUp.append(tempDir)
        return tempDir
    }

    // MARK: - 1. Refused Paths

    func testRefusalForOutsidePaths() {
        let policy = DeletionPolicy(home: "/Users/pierre")

        XCTAssertEqual(policy.refusal(forPath: "/"), .outsideHome)
        XCTAssertEqual(policy.refusal(forPath: "/etc/passwd"), .outsideHome)
        XCTAssertEqual(policy.refusal(forPath: "/Users/other/x"), .outsideHome)
        XCTAssertEqual(policy.refusal(forPath: "/Users/pierre/../other/x"), .outsideHome)
        XCTAssertEqual(policy.refusal(forPath: "/Users/pierreX/a"), .outsideHome)
    }

    func testRefusalForHomeDirectory() {
        let policy = DeletionPolicy(home: "/Users/pierre")

        XCTAssertEqual(policy.refusal(forPath: "/Users/pierre"), .isHome)
        XCTAssertEqual(policy.refusal(forPath: "/Users/pierre/"), .isHome)
    }

    func testRefusalForRelativeAndEmptyPaths() {
        let policy = DeletionPolicy(home: "/Users/pierre")

        XCTAssertEqual(policy.refusal(forPath: "Desktop/x"), .notAbsolute)
        XCTAssertEqual(policy.refusal(forPath: ""), .emptyPath)
    }

    // MARK: - 2. Protected Top-Level Folders

    func testRefusalForProtectedTopLevelFolders() {
        let policy = DeletionPolicy(home: "/Users/pierre")
        let protectedExcludingTrash = DeletionPolicy.protectedTopLevel.subtracting([".Trash"])

        for folderName in protectedExcludingTrash {
            let path = "/Users/pierre/\(folderName)"
            XCTAssertEqual(
                policy.refusal(forPath: path),
                .protectedFolder(folderName),
                "Expected top-level protected folder '\(folderName)' to be refused with .protectedFolder"
            )
        }
    }

    func testAllowedSubpathsInsideProtectedFolders() {
        let policy = DeletionPolicy(home: "/Users/pierre")

        XCTAssertNil(policy.refusal(forPath: "/Users/pierre/Library/Caches/foo"))
        XCTAssertNil(policy.refusal(forPath: "/Users/pierre/Desktop/project"))
        XCTAssertNil(policy.refusal(forPath: "/Users/pierre/Documents/a.pdf"))
    }

    // MARK: - 3. .Trash and Hidden Folders

    func testTrashFolderAndInsideTrashRefusal() {
        let policy = DeletionPolicy(home: "/Users/pierre")

        XCTAssertEqual(policy.refusal(forPath: "/Users/pierre/.Trash"), .protectedFolder(".Trash"))
        XCTAssertEqual(policy.refusal(forPath: "/Users/pierre/.Trash/old"), .insideTrash)
        XCTAssertNil(policy.refusal(forPath: "/Users/pierre/.npm"))
    }

    // MARK: - 4. Normalization

    func testNormalizePath() {
        XCTAssertEqual(DeletionPolicy.normalize("/a//b/./c/../d/"), "/a/b/d")
        XCTAssertEqual(DeletionPolicy.normalize("/"), "/")
        XCTAssertEqual(DeletionPolicy.normalize("///a///b///"), "/a/b")
        XCTAssertEqual(DeletionPolicy.normalize("/a/b/c/.."), "/a/b")
        XCTAssertEqual(DeletionPolicy.normalize("/a/b/../../c"), "/c")
        XCTAssertEqual(DeletionPolicy.normalize("/../../a"), "/a")
    }

    // MARK: - 5. Symlink Escape

    func testSymlinkEscapeRefusal() throws {
        let tempDir = try createUniqueTempDirectory()
        let homeDir = tempDir.appendingPathComponent("home")
        let outsideDir = tempDir.appendingPathComponent("outside")

        try FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)

        let linkURL = homeDir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: outsideDir)

        let policy = DeletionPolicy(home: homeDir.path)

        // A path inside the symlink resolving outside home must be refused with .outsideHome
        let escapedFilePath = linkURL.appendingPathComponent("file").path
        XCTAssertEqual(policy.refusal(forPath: escapedFilePath), .outsideHome)

        // The symlink itself located directly in home must be allowed (nil)
        XCTAssertNil(policy.refusal(forPath: linkURL.path))
    }

    // MARK: - 6. Existence Checking

    func testCheckExistence() throws {
        let tempDir = try createUniqueTempDirectory()
        let homeDir = tempDir.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)

        let existingFileURL = homeDir.appendingPathComponent("present.txt")
        try "content".write(to: existingFileURL, atomically: true, encoding: .utf8)
        let missingFileURL = homeDir.appendingPathComponent("missing.txt")

        let policy = DeletionPolicy(home: homeDir.path)

        // Missing file: .doesNotExist when checkExistence is true, nil when false
        XCTAssertEqual(policy.refusal(forPath: missingFileURL.path, checkExistence: true), .doesNotExist)
        XCTAssertNil(policy.refusal(forPath: missingFileURL.path, checkExistence: false))

        // Existing file: nil regardless of checkExistence
        XCTAssertNil(policy.refusal(forPath: existingFileURL.path, checkExistence: true))
        XCTAssertNil(policy.refusal(forPath: existingFileURL.path, checkExistence: false))
    }

    // MARK: - 7. Remove Node Updates Ancestor Totals

    func testRemoveNodeUpdatesAncestorTotals() {
        // Hierarchy:
        // root (/h) [sum = 600]
        //   ├── a (/h/a) [sum = 500]
        //   │     ├── b (/h/a/b) [sum = 300]
        //   │     │     └── c (/h/a/b/c, 300) [file]
        //   │     └── d (/h/a/d, 200) [file]
        //   └── e (/h/e, 100) [file]
        let c = FileNode(name: "c", url: URL(fileURLWithPath: "/h/a/b/c"), isDirectory: false, allocatedSize: 300)
        let d = FileNode(name: "d", url: URL(fileURLWithPath: "/h/a/d"), isDirectory: false, allocatedSize: 200)
        let b = FileNode(name: "b", url: URL(fileURLWithPath: "/h/a/b"), isDirectory: true, allocatedSize: 0, children: [c])
        let a = FileNode(name: "a", url: URL(fileURLWithPath: "/h/a"), isDirectory: true, allocatedSize: 0, children: [b, d])
        let e = FileNode(name: "e", url: URL(fileURLWithPath: "/h/e"), isDirectory: false, allocatedSize: 100)
        let root = FileNode(name: "h", url: URL(fileURLWithPath: "/h"), isDirectory: true, allocatedSize: 0, children: [a, e])

        // Read root.totalAllocatedSize first to populate memo caches!
        XCTAssertEqual(root.totalAllocatedSize, 600)
        XCTAssertEqual(a.totalAllocatedSize, 500)
        XCTAssertEqual(b.totalAllocatedSize, 300)

        // Remove c
        let removed = FileTreeEditor.removeNode(withID: c.id, from: root)
        XCTAssertTrue(removed === c)

        // Assert b, a, root totals all dropped by 300 and c is gone
        XCTAssertEqual(b.totalAllocatedSize, 0, "b's total should drop by 300 (from 300 to 0)")
        XCTAssertEqual(a.totalAllocatedSize, 200, "a's total should drop by 300 (from 500 to 200)")
        XCTAssertEqual(root.totalAllocatedSize, 300, "root's total should drop by 300 (from 600 to 300)")

        XCTAssertFalse(b.children.contains(where: { $0 === c }))
        XCTAssertNil(FileTreeEditor.pathToNode(withID: c.id, in: root))
    }

    // MARK: - 8. Remove Node Unknown ID and Root

    func testRemoveNodeUnknownIDLeavesTotalsUnchanged() {
        let file = FileNode(name: "file", url: URL(fileURLWithPath: "/h/file"), isDirectory: false, allocatedSize: 250)
        let root = FileNode(name: "h", url: URL(fileURLWithPath: "/h"), isDirectory: true, allocatedSize: 0, children: [file])

        XCTAssertEqual(root.totalAllocatedSize, 250)

        let result = FileTreeEditor.removeNode(withID: "/h/nonexistent", from: root)
        XCTAssertNil(result)
        XCTAssertEqual(root.totalAllocatedSize, 250)
        XCTAssertEqual(root.children.count, 1)
    }

    func testRemoveRootNodeReturnsNil() {
        let file = FileNode(name: "file", url: URL(fileURLWithPath: "/h/file"), isDirectory: false, allocatedSize: 250)
        let root = FileNode(name: "h", url: URL(fileURLWithPath: "/h"), isDirectory: true, allocatedSize: 0, children: [file])

        XCTAssertEqual(root.totalAllocatedSize, 250)

        let result = FileTreeEditor.removeNode(withID: root.id, from: root)
        XCTAssertNil(result)
        XCTAssertEqual(root.totalAllocatedSize, 250)
        XCTAssertEqual(root.children.count, 1)
    }

    // MARK: - 9. Trash Operation with MockTrasher

    func testTrashSuccessCallsTrasherAndUpdatesTree() throws {
        let home = "/Users/pierre"
        let policy = DeletionPolicy(home: home)

        let file = FileNode(name: "file.txt", url: URL(fileURLWithPath: "\(home)/docs/file.txt"), isDirectory: false, allocatedSize: 400)
        let sibling = FileNode(name: "sibling.txt", url: URL(fileURLWithPath: "\(home)/docs/sibling.txt"), isDirectory: false, allocatedSize: 100)
        let docs = FileNode(name: "docs", url: URL(fileURLWithPath: "\(home)/docs"), isDirectory: true, allocatedSize: 0, children: [file, sibling])
        let root = FileNode(name: "pierre", url: URL(fileURLWithPath: home), isDirectory: true, allocatedSize: 0, children: [docs])

        XCTAssertEqual(root.totalAllocatedSize, 500)
        XCTAssertEqual(docs.totalAllocatedSize, 500)

        let trasher = MockTrasher()
        let resultingURL = try FileTreeEditor.trash(
            node: file,
            root: root,
            policy: policy,
            trasher: trasher,
            checkExistence: false
        )

        XCTAssertEqual(trasher.trashedURLs, [file.url])
        XCTAssertNotNil(resultingURL)

        // Node must be removed from the tree and totals updated
        XCTAssertFalse(docs.children.contains(where: { $0 === file }))
        XCTAssertNil(FileTreeEditor.pathToNode(withID: file.id, in: root))
        XCTAssertEqual(docs.totalAllocatedSize, 100)
        XCTAssertEqual(root.totalAllocatedSize, 100)
    }

    func testTrashErrorPropagatesAndLeavesTreeUnchanged() {
        let home = "/Users/pierre"
        let policy = DeletionPolicy(home: home)

        let file = FileNode(name: "file.txt", url: URL(fileURLWithPath: "\(home)/docs/file.txt"), isDirectory: false, allocatedSize: 400)
        let docs = FileNode(name: "docs", url: URL(fileURLWithPath: "\(home)/docs"), isDirectory: true, allocatedSize: 0, children: [file])
        let root = FileNode(name: "pierre", url: URL(fileURLWithPath: home), isDirectory: true, allocatedSize: 0, children: [docs])

        XCTAssertEqual(root.totalAllocatedSize, 400)

        let expectedError = MockError(message: "Permission denied or disk failure")
        let trasher = MockTrasher(errorToThrow: expectedError)

        XCTAssertThrowsError(
            try FileTreeEditor.trash(
                node: file,
                root: root,
                policy: policy,
                trasher: trasher,
                checkExistence: false
            )
        ) { error in
            XCTAssertEqual(error as? MockError, expectedError)
        }

        // Tree must be completely unchanged
        XCTAssertTrue(docs.children.contains(where: { $0 === file }))
        XCTAssertNotNil(FileTreeEditor.pathToNode(withID: file.id, in: root))
        XCTAssertEqual(docs.totalAllocatedSize, 400)
        XCTAssertEqual(root.totalAllocatedSize, 400)
    }

    func testTrashRefusalNeverCallsTrasher() {
        let home = "/Users/pierre"
        let policy = DeletionPolicy(home: home)

        let outsideFile = FileNode(
            name: "other.txt",
            url: URL(fileURLWithPath: "/Users/other/other.txt"),
            isDirectory: false,
            allocatedSize: 200
        )
        let docs = FileNode(name: "docs", url: URL(fileURLWithPath: "\(home)/docs"), isDirectory: true, allocatedSize: 0, children: [outsideFile])
        let root = FileNode(name: "pierre", url: URL(fileURLWithPath: home), isDirectory: true, allocatedSize: 0, children: [docs])

        let trasher = MockTrasher()

        XCTAssertThrowsError(
            try FileTreeEditor.trash(
                node: outsideFile,
                root: root,
                policy: policy,
                trasher: trasher,
                checkExistence: false
            )
        ) { error in
            XCTAssertEqual(error as? DeletionRefusal, .outsideHome)
        }

        // Trasher must NEVER be called
        XCTAssertTrue(trasher.trashedURLs.isEmpty)
        XCTAssertTrue(docs.children.contains(where: { $0 === outsideFile }))
        XCTAssertEqual(root.totalAllocatedSize, 200)
    }

    func testTrashUnattachedNodeThrowsNotARealItem() {
        let home = "/Users/pierre"
        let policy = DeletionPolicy(home: home)

        let unattachedFile = FileNode(
            name: "unattached.txt",
            url: URL(fileURLWithPath: "\(home)/docs/unattached.txt"),
            isDirectory: false,
            allocatedSize: 100
        )
        let root = FileNode(name: "pierre", url: URL(fileURLWithPath: home), isDirectory: true, allocatedSize: 0, children: [])

        let trasher = MockTrasher()

        XCTAssertThrowsError(
            try FileTreeEditor.trash(
                node: unattachedFile,
                root: root,
                policy: policy,
                trasher: trasher,
                checkExistence: false
            )
        ) { error in
            XCTAssertEqual(error as? DeletionRefusal, .notARealItem)
        }

        XCTAssertTrue(trasher.trashedURLs.isEmpty)
    }

    // MARK: - 10. Trash Real Item Moves Item into Trash Folder

    func testTrashRealItemMovesToTrashFolder() throws {
        let tempDir = try createUniqueTempDirectory()
        let homeDir = tempDir.appendingPathComponent("home")
        let trashDir = tempDir.appendingPathComponent("Trash")

        try FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)

        let projectDir = homeDir.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let fileURL = projectDir.appendingPathComponent("important.txt")
        let fileContent = "DiskCleaner Test Content: Move to Trash!"
        try fileContent.write(to: fileURL, atomically: true, encoding: .utf8)

        let fileNode = FileNode(name: "important.txt", url: fileURL, isDirectory: false, allocatedSize: Int64(fileContent.utf8.count))
        let projectNode = FileNode(name: "Project", url: projectDir, isDirectory: true, allocatedSize: 0, children: [fileNode])
        let rootNode = FileNode(name: "home", url: homeDir, isDirectory: true, allocatedSize: 0, children: [projectNode])

        XCTAssertEqual(rootNode.totalAllocatedSize, Int64(fileContent.utf8.count))

        let policy = DeletionPolicy(home: homeDir.path)
        let trasher = MockTrasher(moveDestination: trashDir)

        let resultingTrashURL = try FileTreeEditor.trash(
            node: fileNode,
            root: rootNode,
            policy: policy,
            trasher: trasher,
            checkExistence: true
        )

        let expectedTrashURL = trashDir.appendingPathComponent("important.txt")
        XCTAssertEqual(resultingTrashURL, expectedTrashURL)
        XCTAssertEqual(trasher.trashedURLs, [fileURL])

        // Assert file moved and not deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "Original file must not exist at original path")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedTrashURL.path), "Moved file must exist at Trash destination path")

        let movedContent = try String(contentsOf: expectedTrashURL, encoding: .utf8)
        XCTAssertEqual(movedContent, fileContent, "Item content must be preserved (moved, not deleted)")

        // Tree editing verified
        XCTAssertEqual(rootNode.totalAllocatedSize, 0)
        XCTAssertEqual(projectNode.totalAllocatedSize, 0)
        XCTAssertTrue(projectNode.children.isEmpty)
        XCTAssertNil(FileTreeEditor.pathToNode(withID: fileNode.id, in: rootNode))
    }

    // MARK: - Path Finding Helper

    func testPathToNode() {
        let child = FileNode(name: "child", url: URL(fileURLWithPath: "/root/dir/child"), isDirectory: false, allocatedSize: 50)
        let dir = FileNode(name: "dir", url: URL(fileURLWithPath: "/root/dir"), isDirectory: true, allocatedSize: 0, children: [child])
        let root = FileNode(name: "root", url: URL(fileURLWithPath: "/root"), isDirectory: true, allocatedSize: 0, children: [dir])

        let path = FileTreeEditor.pathToNode(withID: child.id, in: root)
        XCTAssertEqual(path?.map(\.id), [root.id, dir.id, child.id])

        let rootPath = FileTreeEditor.pathToNode(withID: root.id, in: root)
        XCTAssertEqual(rootPath?.map(\.id), [root.id])

        let unknownPath = FileTreeEditor.pathToNode(withID: "/root/dir/nonexistent", in: root)
        XCTAssertNil(unknownPath)
    }
}
