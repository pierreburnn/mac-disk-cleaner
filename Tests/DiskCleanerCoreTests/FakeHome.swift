// FakeHome.swift – Helper to build isolated temporary directory trees for tests
import Foundation
import XCTest
@testable import DiskCleanerCore

public final class FakeHome {
    public let url: URL
    public var path: String { url.path }
    private let fm = FileManager.default
    private var chmodPathsToRestore: [String] = []

    /// Approximate total logical bytes written by `populateStandardTree()`.
    public var totalLogicalBytes: Int64 = 0

    public init() throws {
        let uniqueID = UUID().uuidString
        let tempBase = fm.temporaryDirectory.appendingPathComponent("DiskCleanerFakeHome-\(uniqueID)", isDirectory: true)
        try fm.createDirectory(at: tempBase, withIntermediateDirectories: true)
        self.url = tempBase
    }

    /// Tear down the fake home directory, restoring permissions beforehand to allow clean removal.
    public func tearDown() {
        for path in chmodPathsToRestore {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }
        chmodPathsToRestore.removeAll()

        restorePermissionsRecursively(at: url)
        try? fm.removeItem(at: url)
    }

    private func restorePermissionsRecursively(at dirURL: URL) {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dirURL.path)
        if let enumerator = fm.enumerator(at: dirURL, includingPropertiesForKeys: nil) {
            for case let itemURL as URL in enumerator {
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: itemURL.path)
            }
        }
    }

    /// Write a file with a specified byte count and optional modification date.
    @discardableResult
    public func writeFile(relativePath: String, byteCount: Int, modificationDate: Date? = nil) throws -> URL {
        let fileURL = url.appendingPathComponent(relativePath)
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(count: byteCount)
        try data.write(to: fileURL)
        if let modDate = modificationDate {
            try fm.setAttributes([.modificationDate: modDate], ofItemAtPath: fileURL.path)
        }
        return fileURL
    }

    /// Create a directory with an optional modification date.
    @discardableResult
    public func createDirectory(relativePath: String, modificationDate: Date? = nil) throws -> URL {
        let dirURL = url.appendingPathComponent(relativePath)
        try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        if let modDate = modificationDate {
            try fm.setAttributes([.modificationDate: modDate], ofItemAtPath: dirURL.path)
        }
        return dirURL
    }

    /// Set POSIX permissions on a path inside the fake home.
    public func setPermissions(_ perms: Int, at relativePath: String) throws {
        let targetURL = url.appendingPathComponent(relativePath)
        try fm.setAttributes([.posixPermissions: perms], ofItemAtPath: targetURL.path)
        chmodPathsToRestore.append(targetURL.path)
    }

    /// Set modification date on an existing file or directory.
    public func setModificationDate(_ date: Date, at relativePath: String) throws {
        let targetURL = url.appendingPathComponent(relativePath)
        try fm.setAttributes([.modificationDate: date], ofItemAtPath: targetURL.path)
    }

    /// Create a symbolic link at `relativePath` targeting `destination`.
    public func createSymlink(relativePath: String, destination: String) throws {
        let linkURL = url.appendingPathComponent(relativePath)
        try fm.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: linkURL.path, withDestinationPath: destination)
    }

    /// Populate the standard tree matching the project specification:
    /// - .npm/_cacache/content (3 MB)
    /// - .gradle/caches/modules (2 MB)
    /// - Library/Developer/Xcode/DerivedData/Foo (2 MB)
    /// - "Library/Developer/Xcode/iOS DeviceSupport/17.0" (2 MB)
    /// - .cache/uv (2 MB)
    /// - .cache/puppeteer (2 MB)
    /// - Desktop/webapp/package.json + Desktop/webapp/.next/cache (2 MB) + Desktop/webapp/.turbo (1.5 MB)
    /// - Desktop/oldproj/package.json + Desktop/oldproj/node_modules/lodash (2 MB) dated 90 days ago
    /// - Desktop/freshproj/package.json + node_modules (2 MB) dated now
    /// - .ollama/models/blobs (3 MB)
    /// - Desktop/atlas/.claude/worktrees/wt1/file (2 MB)
    /// - Library/Android/sdk (2 MB)
    /// - .android/avd (2 MB)
    /// - Documents/"My 'quoted' folder"/file (1 MB)
    /// - symlink "loop" -> "." inside Desktop
    /// - symlink "usrlink" -> /usr at home root
    public func populateStandardTree() throws {
        var bytesWritten: Int64 = 0

        func addFile(_ rel: String, _ count: Int, mod: Date? = nil) throws {
            try writeFile(relativePath: rel, byteCount: count, modificationDate: mod)
            bytesWritten += Int64(count)
        }

        // Caches & SDKs
        try addFile(".npm/_cacache/content", 3_000_000)
        try addFile(".gradle/caches/modules", 2_000_000)
        try addFile("Library/Developer/Xcode/DerivedData/Foo", 2_000_000)
        try addFile("Library/Developer/Xcode/iOS DeviceSupport/17.0", 2_000_000)
        try addFile(".cache/uv", 2_000_000)
        try addFile(".cache/puppeteer", 2_000_000)

        // Webapp project with .next and .turbo
        try addFile("Desktop/webapp/package.json", 100)
        try addFile("Desktop/webapp/.next/cache", 2_000_000)
        try addFile("Desktop/webapp/.turbo/cache", 1_500_000)

        // Old project dated 90 days ago
        let oldDate = Date().addingTimeInterval(-90 * 24 * 3600)
        try createDirectory(relativePath: "Desktop/oldproj")
        try addFile("Desktop/oldproj/package.json", 100, mod: oldDate)
        try createDirectory(relativePath: "Desktop/oldproj/node_modules")
        try addFile("Desktop/oldproj/node_modules/lodash", 2_000_000, mod: oldDate)
        // Ensure directories themselves have old modification dates
        try setModificationDate(oldDate, at: "Desktop/oldproj/node_modules")
        try setModificationDate(oldDate, at: "Desktop/oldproj")

        // Fresh project dated now
        let nowDate = Date()
        try createDirectory(relativePath: "Desktop/freshproj")
        try addFile("Desktop/freshproj/package.json", 100, mod: nowDate)
        try createDirectory(relativePath: "Desktop/freshproj/node_modules")
        try addFile("Desktop/freshproj/node_modules/lodash", 2_000_000, mod: nowDate)
        try setModificationDate(nowDate, at: "Desktop/freshproj/node_modules")
        try setModificationDate(nowDate, at: "Desktop/freshproj")

        // AI models
        try addFile(".ollama/models/blobs", 3_000_000)

        // Worktrees
        try addFile("Desktop/atlas/.claude/worktrees/wt1/file", 2_000_000)

        // Android
        try addFile("Library/Android/sdk", 2_000_000)
        try addFile(".android/avd", 2_000_000)

        // Quoted documents path
        try addFile("Documents/My 'quoted' folder/file", 1_000_000)

        // Symlinks
        try createSymlink(relativePath: "Desktop/loop", destination: ".")
        try createSymlink(relativePath: "usrlink", destination: "/usr")

        self.totalLogicalBytes = bytesWritten
    }
}
