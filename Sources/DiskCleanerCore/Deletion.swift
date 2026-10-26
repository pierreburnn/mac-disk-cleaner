// Deletion.swift – Safe "move to Trash" support for a single treemap tile.
//
// The app never deletes permanently. A user-confirmed tile can only be moved
// to the Trash (recoverable) through `TrashPerforming`, after `DeletionPolicy`
// has accepted its path. The cleanup *script* feature is unrelated and unchanged.
import Foundation

// MARK: - Trash abstraction (injectable for tests)

public protocol TrashPerforming: Sendable {
    /// Move the item to the Trash. Returns the item's new URL inside the Trash, if known.
    func trashItem(at url: URL) throws -> URL?
}

/// Production implementation backed by `FileManager.trashItem` (recoverable).
public struct FileManagerTrasher: TrashPerforming {
    public init() {}

    public func trashItem(at url: URL) throws -> URL? {
        #if os(macOS)
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
        #else
        throw CocoaError(.featureUnsupported)
        #endif
    }
}

// MARK: - Policy

public enum DeletionRefusal: Error, Equatable, Sendable, CustomStringConvertible {
    case demoMode
    case notARealItem          // "Other" bucket / grouped small files
    case emptyPath
    case notAbsolute
    case outsideHome
    case isHome
    case protectedFolder(String)
    case insideTrash
    case doesNotExist

    public var description: String {
        switch self {
        case .demoMode: return "Deleting is disabled in demo mode."
        case .notARealItem: return "This tile groups several small items; it is not a single file or folder."
        case .emptyPath: return "No path."
        case .notAbsolute: return "Only absolute paths can be moved to the Trash."
        case .outsideHome: return "Only items inside your home folder can be moved to the Trash."
        case .isHome: return "Your home folder itself cannot be moved to the Trash."
        case .protectedFolder(let name):
            return "~/\(name) is a protected system folder. You can move items inside it to the Trash, but not the folder itself."
        case .insideTrash: return "This item is already in the Trash."
        case .doesNotExist: return "This item no longer exists on disk."
        }
    }
}

public struct DeletionPolicy: Sendable {
    /// Top-level folders of ~ whose *content* may be trashed, but not the folder itself.
    public static let protectedTopLevel: Set<String> = [
        "Library", "Desktop", "Documents", "Downloads", "Pictures", "Music", "Movies",
        "Applications", "Public", ".Trash",
    ]

    public let home: String
    private let resolvedHome: String

    public init(home: String) {
        let h = DeletionPolicy.normalize(home)
        self.home = h
        self.resolvedHome = DeletionPolicy.normalize(URL(fileURLWithPath: h).resolvingSymlinksInPath().path)
    }

    /// Validate a path purely lexically + by resolving symlinks of its parent
    /// directory (the item itself is not followed: trashing a symlink only
    /// trashes the link). Returns nil when the path may be trashed.
    public func refusal(forPath rawPath: String, checkExistence: Bool = false) -> DeletionRefusal? {
        guard !rawPath.isEmpty else { return .emptyPath }
        guard rawPath.hasPrefix("/") else { return .notAbsolute }
        let path = DeletionPolicy.normalize(rawPath)

        if let r = check(path, againstHome: home) { return r }

        // Guard against a symlinked parent that points outside of ~.
        let parent = (path as NSString).deletingLastPathComponent
        let resolvedParent = DeletionPolicy.normalize(URL(fileURLWithPath: parent).resolvingSymlinksInPath().path)
        let resolved = resolvedParent == "/" ? "/" + (path as NSString).lastPathComponent
                                             : resolvedParent + "/" + (path as NSString).lastPathComponent
        if let r = check(resolved, againstHome: resolvedHome) { return r }

        if checkExistence {
            var st = stat()
            if lstat(path, &st) != 0 { return .doesNotExist }
        }
        return nil
    }

    private func check(_ path: String, againstHome home: String) -> DeletionRefusal? {
        if path == home { return .isHome }
        guard path.hasPrefix(home + "/") else { return .outsideHome }
        let rel = String(path.dropFirst(home.count + 1))
        let components = rel.split(separator: "/").map(String.init)
        guard let first = components.first else { return .isHome }
        if components.count == 1 && DeletionPolicy.protectedTopLevel.contains(first) {
            return .protectedFolder(first)
        }
        if first == ".Trash" { return .insideTrash }
        return nil
    }

    /// Lexical normalisation: removes ".", "..", duplicate and trailing slashes.
    public static func normalize(_ path: String) -> String {
        var out: [Substring] = []
        for comp in path.split(separator: "/", omittingEmptySubsequences: true) {
            if comp == "." { continue }
            if comp == ".." { if !out.isEmpty { out.removeLast() }; continue }
            out.append(comp)
        }
        return "/" + out.joined(separator: "/")
    }
}

// MARK: - Tree editing

public enum FileTreeEditor {
    /// Chain of nodes from `root` down to the node with `id` (inclusive), or nil.
    public static func pathToNode(withID id: String, in root: FileNode) -> [FileNode]? {
        if root.id == id { return [root] }
        // Only descend into children whose path is a prefix of the target id.
        for child in root.children where id == child.id || id.hasPrefix(child.id + "/") || child.url.path == id {
            if let rest = pathToNode(withID: id, in: child) { return [root] + rest }
        }
        // Fallback (ids that are not path-shaped, e.g. demo nodes with display names).
        for child in root.children {
            if let rest = pathToNode(withID: id, in: child) { return [root] + rest }
        }
        return nil
    }

    /// Remove the node with `id` from the tree. Every ancestor's cached total is
    /// refreshed so sizes stay correct without a rescan. Returns the removed node.
    @discardableResult
    public static func removeNode(withID id: String, from root: FileNode) -> FileNode? {
        guard let chain = pathToNode(withID: id, in: root), chain.count >= 2 else { return nil }
        let target = chain[chain.count - 1]
        let parent = chain[chain.count - 2]
        parent.children.removeAll { $0 === target }
        // children didSet resets the parent's cache; reset the rest of the chain.
        for ancestor in chain.dropLast(2) { ancestor.invalidateTotal() }
        return target
    }

    /// Validate, move to the Trash through `trasher`, then update the tree.
    public static func trash(node: FileNode, root: FileNode, policy: DeletionPolicy,
                             trasher: TrashPerforming, checkExistence: Bool = true) throws -> URL? {
        if let refusal = policy.refusal(forPath: node.url.path, checkExistence: checkExistence) {
            throw refusal
        }
        guard node.id != root.id, pathToNode(withID: node.id, in: root) != nil else {
            throw DeletionRefusal.notARealItem
        }
        let resulting = try trasher.trashItem(at: node.url)
        removeNode(withID: node.id, from: root)
        return resulting
    }
}
