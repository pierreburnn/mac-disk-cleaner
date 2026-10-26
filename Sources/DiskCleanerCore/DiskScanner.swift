// DiskScanner.swift – Real file-system scanner
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Progress update from the scanner.
public struct ScanProgress: Sendable {
    public let filesScanned: Int
    public let bytesScanned: Int64
    public let currentPath: String

    public init(filesScanned: Int, bytesScanned: Int64, currentPath: String) {
        self.filesScanned = filesScanned
        self.bytesScanned = bytesScanned
        self.currentPath = currentPath
    }
}

/// Result of a full scan.
public struct ScanResult: Sendable {
    public let root: FileNode
    public let totalBytes: Int64
    public let fileCount: Int
    public let deniedPaths: [String]
    public let needsFullDiskAccess: Bool

    public init(
        root: FileNode,
        totalBytes: Int64,
        fileCount: Int,
        deniedPaths: [String],
        needsFullDiskAccess: Bool
    ) {
        self.root = root
        self.totalBytes = totalBytes
        self.fileCount = fileCount
        self.deniedPaths = deniedPaths
        self.needsFullDiskAccess = needsFullDiskAccess
    }
}

/// Scans the file system to build a FileNode tree.
public final class DiskScanner: @unchecked Sendable {

    private let classifier: CategoryClassifier
    private var seenInodes: Set<UInt64> = []
    private let inodeLock = NSLock()

    public init() {
        self.classifier = CategoryClassifier()
    }

    /// Scan the given root URL (typically the home directory).
    /// - Parameters:
    ///   - root: The directory URL to scan.
    ///   - progress: Callback for progress updates (called on arbitrary queue, ~10/s).
    /// - Returns: A ScanResult with the file tree.
    public func scan(
        root: URL,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async -> ScanResult {
        let rootPath = root.path
        var rootStat = stat()
        guard lstat(rootPath, &rootStat) == 0 else {
            let emptyNode = FileNode(name: root.lastPathComponent, url: root, isDirectory: true)
            return ScanResult(root: emptyNode, totalBytes: 0, fileCount: 0, deniedPaths: [], needsFullDiskAccess: false)
        }
        let rootDev = rootStat.st_dev

        // Thread-safe counters
        let counter = ScanCounter()

        let rootNode = await scanDirectory(
            url: root,
            parentCategory: nil,
            homePath: rootPath,
            rootDev: rootDev,
            counter: counter,
            progress: progress,
            depth: 0
        )

        rootNode.sortChildrenBySize()

        let totalBytes = rootNode.totalAllocatedSize
        let fileCount = rootNode.fileCount
        let deniedPaths = counter.getDeniedPaths()

        let protectedDirs = ["Library/Mail", "Library/Safari", "Library/Messages", "Desktop", "Documents"]
        let needsFDA = protectedDirs.contains { dir in
            deniedPaths.contains { $0.hasSuffix("/\(dir)") || $0 == dir }
        }

        return ScanResult(
            root: rootNode,
            totalBytes: totalBytes,
            fileCount: fileCount,
            deniedPaths: deniedPaths,
            needsFullDiskAccess: needsFDA
        )
    }

    private func scanDirectory(
        url: URL,
        parentCategory: NodeCategory?,
        homePath: String,
        rootDev: dev_t,
        counter: ScanCounter,
        progress: @escaping @Sendable (ScanProgress) -> Void,
        depth: Int
    ) async -> FileNode {
        let relativePath: String
        let urlPath = url.path
        if urlPath.count > homePath.count + 1 {
            relativePath = String(urlPath.dropFirst(homePath.count + 1))
        } else if urlPath == homePath {
            relativePath = ""
        } else {
            relativePath = url.lastPathComponent
        }

        let category = relativePath.isEmpty
            ? NodeCategory.devTools
            : classifier.classify(relativePath: relativePath, isDirectory: true, parentCategory: parentCategory)

        let node = FileNode(
            name: url.lastPathComponent,
            url: url,
            isDirectory: true,
            allocatedSize: 0,
            children: [],
            category: category
        )

        let fm = FileManager.default
        let contents: [URL]
        do {
            let names = try fm.contentsOfDirectory(atPath: urlPath)
            contents = names.map { url.appendingPathComponent($0, isDirectory: false) }
        } catch {
            counter.addDeniedPath(url.path)
            return node
        }

        // For top 2 levels, parallelize with TaskGroup
        if depth < 2 {
            var children: [FileNode] = []
            await withTaskGroup(of: FileNode.self) { group in
                for itemURL in contents {
                    group.addTask { [self] in
                        return await self.processItem(
                            url: itemURL,
                            parentCategory: category,
                            homePath: homePath,
                            rootDev: rootDev,
                            counter: counter,
                            progress: progress,
                            depth: depth + 1
                        )
                    }
                }
                for await child in group {
                    children.append(child)
                }
            }
            node.children = children
        } else {
            // Synchronous recursion at deeper levels
            var children: [FileNode] = []
            for itemURL in contents {
                if Task.isCancelled { break }
                let child = await processItem(
                    url: itemURL,
                    parentCategory: category,
                    homePath: homePath,
                    rootDev: rootDev,
                    counter: counter,
                    progress: progress,
                    depth: depth + 1
                )
                children.append(child)
            }
            node.children = children
        }

        // Get modification date of the directory itself
        var dirStat = stat()
        if lstat(url.path, &dirStat) == 0 {
            node.modificationDate = Date(timeIntervalSince1970: Double(dirStat.st_mtime))
            node.allocatedSize += Int64(dirStat.st_blocks) * 512
        }

        // Memory control: fold small files (< 1 MB) into the directory's own size
        // when the directory has many entries or is deep in the tree. Keeps the
        // tree small enough for homes with millions of files (node_modules...).
        if depth >= 3 || node.children.count > 64 {
            let threshold: Int64 = 1_000_000
            var kept: [FileNode] = []
            kept.reserveCapacity(node.children.count)
            var newest: Date? = node.modificationDate
            for child in node.children {
                if !child.isDirectory && child.allocatedSize < threshold {
                    node.allocatedSize += child.allocatedSize
                    node.mergedFileCount += 1
                    if let d = child.modificationDate, newest == nil || d > newest! {
                        newest = d
                    }
                } else {
                    kept.append(child)
                }
            }
            node.children = kept
            node.modificationDate = newest
        }

        return node
    }

    private func processItem(
        url: URL,
        parentCategory: NodeCategory?,
        homePath: String,
        rootDev: dev_t,
        counter: ScanCounter,
        progress: @escaping @Sendable (ScanProgress) -> Void,
        depth: Int
    ) async -> FileNode {
        let path = url.path
        var st = stat()
        guard lstat(path, &st) == 0 else {
            // Can't stat - likely permission denied
            counter.addDeniedPath(path)
            return FileNode(name: url.lastPathComponent, url: url, isDirectory: false, allocatedSize: 0)
        }

        // Check for symlink - count its own small size, don't follow
        let isSymlink = (st.st_mode & S_IFMT) == S_IFLNK
        if isSymlink {
            let size = Int64(st.st_blocks) * 512
            let relativePath = makeRelative(path: path, homePath: homePath)
            let cat = classifier.classify(relativePath: relativePath, isDirectory: false, parentCategory: parentCategory)
            let symNode = FileNode(
                name: url.lastPathComponent,
                url: url,
                isDirectory: false,
                allocatedSize: size,
                category: cat
            )
            counter.addFile(bytes: size)
            counter.maybeReportProgress(path: path, progress: progress)
            return symNode
        }

        // Don't cross volume boundaries
        if st.st_dev != rootDev {
            return FileNode(name: url.lastPathComponent, url: url, isDirectory: false, allocatedSize: 0)
        }

        let isDir = (st.st_mode & S_IFMT) == S_IFDIR

        if isDir {
            return await scanDirectory(
                url: url,
                parentCategory: parentCategory,
                homePath: homePath,
                rootDev: rootDev,
                counter: counter,
                progress: progress,
                depth: depth
            )
        } else {
            // Regular file
            let allocatedSize = Int64(st.st_blocks) * 512

            // Hard link dedup: skip size for files with nlink > 1 that we've seen
            if st.st_nlink > 1 {
                let inode = st.st_ino
                let alreadySeen: Bool
                inodeLock.lock()
                if seenInodes.contains(inode) {
                    alreadySeen = true
                } else {
                    seenInodes.insert(inode)
                    alreadySeen = false
                }
                inodeLock.unlock()
                if alreadySeen {
                    // Count zero size for duplicate hard links
                    let relativePath = makeRelative(path: path, homePath: homePath)
                    let cat = classifier.classify(relativePath: relativePath, isDirectory: false, parentCategory: parentCategory)
                    let fNode = FileNode(
                        name: url.lastPathComponent,
                        url: url,
                        isDirectory: false,
                        allocatedSize: 0,
                        modificationDate: Date(timeIntervalSince1970: Double(st.st_mtime)),
                        category: cat
                    )
                    counter.addFile(bytes: 0)
                    counter.maybeReportProgress(path: path, progress: progress)
                    return fNode
                }
            }

            let relativePath = makeRelative(path: path, homePath: homePath)
            let cat = classifier.classify(relativePath: relativePath, isDirectory: false, parentCategory: parentCategory)
            let fNode = FileNode(
                name: url.lastPathComponent,
                url: url,
                isDirectory: false,
                allocatedSize: allocatedSize,
                modificationDate: Date(timeIntervalSince1970: Double(st.st_mtime)),
                category: cat
            )
            counter.addFile(bytes: allocatedSize)
            counter.maybeReportProgress(path: path, progress: progress)
            return fNode
        }
    }

    private func makeRelative(path: String, homePath: String) -> String {
        if path.hasPrefix(homePath + "/") {
            return String(path.dropFirst(homePath.count + 1))
        }
        return path
    }
}

/// Thread-safe counters for scan progress.
private final class ScanCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _filesScanned: Int = 0
    private var _bytesScanned: Int64 = 0
    private var _deniedPaths: [String] = []
    private var _lastReport: Date = .distantPast

    func addFile(bytes: Int64) {
        lock.lock()
        _filesScanned += 1
        _bytesScanned += bytes
        lock.unlock()
    }

    func addDeniedPath(_ path: String) {
        lock.lock()
        _deniedPaths.append(path)
        lock.unlock()
    }

    func getDeniedPaths() -> [String] {
        lock.lock()
        let result = _deniedPaths
        lock.unlock()
        return result
    }

    func maybeReportProgress(path: String, progress: @escaping @Sendable (ScanProgress) -> Void) {
        lock.lock()
        let now = Date()
        let shouldReport = now.timeIntervalSince(_lastReport) >= 0.1 // ~10 updates/s
        if shouldReport {
            _lastReport = now
        }
        let files = _filesScanned
        let bytes = _bytesScanned
        lock.unlock()

        if shouldReport {
            progress(ScanProgress(filesScanned: files, bytesScanned: bytes, currentPath: path))
        }
    }
}
