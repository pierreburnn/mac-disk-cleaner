// ScannerTests.swift – Tests for DiskScanner scanning against FakeHome
import XCTest
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import DiskCleanerCore

final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }
    func increment() {
        lock.lock()
        _count += 1
        lock.unlock()
    }
}

final class ScannerTests: XCTestCase {

    func testScanFakeHomeTotalLogicalSize() async throws {
        let fakeHome = try FakeHome()
        try fakeHome.populateStandardTree()
        defer { fakeHome.tearDown() }

        let scanner = DiskScanner()
        let result = await scanner.scan(root: fakeHome.url, progress: { _ in })

        // Avoid flaky exact byte assertions; check total > sum of logical sizes * 0.9
        let minExpected = Int64(Double(fakeHome.totalLogicalBytes) * 0.9)
        XCTAssertGreaterThan(result.totalBytes, minExpected, "Total scanned bytes should exceed 90% of logical size sum")
        XCTAssertGreaterThan(result.fileCount, 0, "File count should be greater than 0")
    }

    func testSymlinksNotFollowed() async throws {
        let fakeHome = try FakeHome()
        try fakeHome.populateStandardTree()
        defer { fakeHome.tearDown() }

        let scanner = DiskScanner()
        let result = await scanner.scan(root: fakeHome.url, progress: { _ in })

        // 1. "usrlink" node exists, is not directory, and has no children
        let usrNode = result.root.findChild(at: "usrlink")
        XCTAssertNotNil(usrNode, "usrlink node should be present")
        if let usrNode = usrNode {
            XCTAssertFalse(usrNode.isDirectory, "usrlink should not be treated as a directory")
            XCTAssertTrue(usrNode.children.isEmpty, "No node under usrlink should have children")
        }

        // 2. "loop" node exists inside Desktop, and has no children
        let loopNode = result.root.findChild(at: "Desktop/loop")
        XCTAssertNotNil(loopNode, "loop node should be present")
        if let loopNode = loopNode {
            XCTAssertFalse(loopNode.isDirectory, "loop symlink should not be treated as a directory")
            XCTAssertTrue(loopNode.children.isEmpty, "No node under loop should have children")
        }

        // 3. Scanned total is much smaller than /usr (e.g. < 500 MB, whereas /usr is multiple GBs)
        XCTAssertLessThan(result.totalBytes, 500_000_000, "Fake home total should be much smaller than real /usr")
    }

    func testAllocatedSizeForOneByteFile() async throws {
        let fakeHome = try FakeHome()
        defer { fakeHome.tearDown() }

        try fakeHome.writeFile(relativePath: "single-byte.txt", byteCount: 1)

        let scanner = DiskScanner()
        let result = await scanner.scan(root: fakeHome.url, progress: { _ in })

        guard let oneByteNode = result.root.findChild(at: "single-byte.txt") else {
            XCTFail("single-byte.txt node was not found")
            return
        }

        // On block filesystems, allocated size is rounded to block size (e.g. 512, 4096) >= 1
        XCTAssertGreaterThanOrEqual(oneByteNode.allocatedSize, 1, "Allocated size for a 1-byte file should be >= 1")
    }

    func testPermissionDeniedDirectoryAppearsInDeniedPaths() async throws {
        #if canImport(Darwin)
        try XCTSkipIf(getuid() == 0, "Root user ignores POSIX permissions 000")
        #elseif canImport(Glibc)
        try XCTSkipIf(getuid() == 0, "Root user ignores POSIX permissions 000")
        #endif

        let fakeHome = try FakeHome()
        defer { fakeHome.tearDown() }

        let deniedURL = try fakeHome.createDirectory(relativePath: "RestrictedFolder")
        try fakeHome.setPermissions(0, at: "RestrictedFolder")

        let scanner = DiskScanner()
        let result = await scanner.scan(root: fakeHome.url, progress: { _ in })

        XCTAssertTrue(
            result.deniedPaths.contains(deniedURL.path),
            "Permission-denied directory \(deniedURL.path) should appear in deniedPaths: \(result.deniedPaths)"
        )
    }

    func testProgressCallbackCalled() async throws {
        let fakeHome = try FakeHome()
        try fakeHome.populateStandardTree()
        defer { fakeHome.tearDown() }

        let counter = ProgressCounter()
        let scanner = DiskScanner()

        _ = await scanner.scan(root: fakeHome.url) { progress in
            counter.increment()
            XCTAssertFalse(progress.currentPath.isEmpty)
        }

        XCTAssertGreaterThanOrEqual(counter.count, 1, "Progress callback should be invoked at least once")
    }
}
