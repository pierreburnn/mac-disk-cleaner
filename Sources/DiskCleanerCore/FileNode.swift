// FileNode.swift – Tree node representing a file or directory
import Foundation

/// A node in the file-system tree.
public final class FileNode: Identifiable, @unchecked Sendable {
    public let id: String
    public let name: String
    public let url: URL
    public let isDirectory: Bool
    public var allocatedSize: Int64 { didSet { _total = -1 } }
    public var children: [FileNode] { didSet { _total = -1 } }
    private var _total: Int64 = -1
    public var modificationDate: Date?
    public var category: NodeCategory
    public var approximate: Bool
    /// Number of small files folded into this directory's own `allocatedSize`
    /// (the scanner merges tiny files to keep memory usage low).
    public var mergedFileCount: Int = 0

    /// Total allocated bytes (self + all descendants).
    public var totalAllocatedSize: Int64 {
        if _total >= 0 { return _total }
        let value: Int64 = isDirectory
            ? children.reduce(allocatedSize) { $0 + $1.totalAllocatedSize }
            : allocatedSize
        _total = value
        return value
    }

    /// Drop the memoised total (call after editing a descendant in place).
    public func invalidateTotal() { _total = -1 }

    /// Total file count (self if file, or sum of descendants).
    public var fileCount: Int {
        if isDirectory {
            return children.reduce(mergedFileCount) { $0 + $1.fileCount }
        }
        return 1
    }

    public init(
        name: String,
        url: URL,
        isDirectory: Bool,
        allocatedSize: Int64 = 0,
        children: [FileNode] = [],
        modificationDate: Date? = nil,
        category: NodeCategory = .devTools,
        approximate: Bool = false
    ) {
        self.id = url.path
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.allocatedSize = allocatedSize
        self.children = children
        self.modificationDate = modificationDate
        self.category = category
        self.approximate = approximate
    }

    /// Sort children recursively by total allocated size descending.
    public func sortChildrenBySize() {
        children.sort { $0.totalAllocatedSize > $1.totalAllocatedSize }
        for child in children {
            child.sortChildrenBySize()
        }
    }

    /// Find a child node by relative path components.
    public func findChild(at relativePath: String) -> FileNode? {
        let components = relativePath.split(separator: "/").map(String.init)
        var current: FileNode = self
        for component in components {
            guard let child = current.children.first(where: { $0.name == component }) else {
                return nil
            }
            current = child
        }
        return current
    }
}
