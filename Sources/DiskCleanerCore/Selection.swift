// Selection.swift – Combined selection (clicked tiles + ticked recommendations)
// and the batch "move to Trash" built on top of `DeletionPolicy`.
//
// Still only `TrashPerforming.trashItem` (recoverable). Nothing is deleted
// permanently, and the cleanup script generator is unchanged.
import Foundation

/// One line of the selection panel: a clicked tile or a ticked recommendation.
public struct SelectionEntry: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case tile, recommendation }
    public let id: String
    public let kind: Kind
    public let title: String
    public let paths: [String]
    /// Used only for paths that are not in the scanned tree.
    public let fallbackBytes: Int64

    public init(id: String, kind: Kind, title: String, paths: [String], fallbackBytes: Int64) {
        self.id = id
        self.kind = kind
        self.title = title
        self.paths = paths
        self.fallbackBytes = fallbackBytes
    }

    public static func tile(_ node: FileNode) -> SelectionEntry {
        SelectionEntry(id: "tile:" + node.url.path, kind: .tile, title: node.name,
                       paths: [node.url.path], fallbackBytes: max(0, node.totalAllocatedSize))
    }

    /// Same paths as the cleanup script uses (`Recommendation.paths`).
    public static func recommendation(_ rec: Recommendation) -> SelectionEntry {
        SelectionEntry(id: "rec:" + rec.id, kind: .recommendation, title: rec.title,
                       paths: rec.paths, fallbackBytes: max(0, rec.bytes))
    }
}

/// A path that will be moved to the Trash, after de-duplication.
public struct TrashTarget: Hashable, Sendable {
    public let path: String
    public let bytes: Int64
    /// Entries that asked for this path (or for a path inside it).
    public let entryIDs: [String]
}

public struct TrashPlan: Sendable {
    /// De-duplicated targets that pass the policy (lexically).
    public var targets: [TrashTarget] = []
    /// De-duplicated paths refused by the policy, with the reason.
    public var refused: [(path: String, refusal: DeletionRefusal, bytes: Int64)] = []
    /// Sum over every de-duplicated path (allowed + refused): "selected".
    public var selectedBytes: Int64 = 0
    /// Sum over the allowed targets only: what the Trash would receive.
    public var trashableBytes: Int64 { targets.reduce(0) { $0 + $1.bytes } }
    public var isEmpty: Bool { targets.isEmpty && refused.isEmpty }
}

public enum SelectionPlanner {
    /// `true` when `path` equals `ancestor` or lies inside it.
    public static func isSameOrInside(_ path: String, _ ancestor: String) -> Bool {
        path == ancestor || ancestor == "/" || path.hasPrefix(ancestor + "/")
    }

    /// Normalise, drop duplicates and every path contained in another one.
    /// Order of first appearance is kept.
    public static func dedupe(_ paths: [String]) -> [String] {
        let normalized = paths.filter { !$0.isEmpty }.map { $0.hasPrefix("/") ? DeletionPolicy.normalize($0) : $0 }
        // Shortest first so ancestors are seen before their descendants.
        let byLength = Set(normalized).sorted { ($0.count, $0) < ($1.count, $1) }
        var kept: [String] = []
        for p in byLength where !kept.contains(where: { isSameOrInside(p, $0) }) {
            kept.append(p)
        }
        let keptSet = Set(kept)
        var seen = Set<String>()
        return normalized.filter { keptSet.contains($0) && seen.insert($0).inserted }
    }

    /// Fast, prefix-guided lookup of the node whose path is `path` (no full scan).
    public static func node(atPath path: String, in root: FileNode) -> FileNode? {
        var current = root
        if current.url.path == path { return current }
        guard isSameOrInside(path, current.url.path) else { return nil }
        while true {
            guard let next = current.children.first(where: { isSameOrInside(path, $0.url.path) }) else { return nil }
            if next.url.path == path { return next }
            current = next
        }
    }

    /// Build the plan for the given entries.
    public static func plan(entries: [SelectionEntry], root: FileNode?, policy: DeletionPolicy) -> TrashPlan {
        var owners: [String: [String]] = [:]
        var fallback: [String: Int64] = [:]
        var all: [String] = []
        for entry in entries {
            let paths = entry.paths.map { $0.hasPrefix("/") ? DeletionPolicy.normalize($0) : $0 }
            for p in paths {
                all.append(p)
                owners[p, default: []].append(entry.id)
                // Spread an entry's own size over its paths when they are not in the tree.
                fallback[p] = max(fallback[p] ?? 0, entry.fallbackBytes / Int64(max(1, paths.count)))
            }
        }
        var plan = TrashPlan()
        for p in dedupe(all) {
            let bytes: Int64
            if let root, let n = node(atPath: p, in: root) {
                bytes = max(0, n.totalAllocatedSize)
            } else {
                bytes = fallback[p] ?? 0
            }
            plan.selectedBytes += bytes
            var ids: [String] = []
            for (q, o) in owners where isSameOrInside(q, p) { ids.append(contentsOf: o) }
            let uniqueIDs = Array(Set(ids)).sorted()
            if let refusal = policy.refusal(forPath: p) {
                plan.refused.append((p, refusal, bytes))
            } else {
                plan.targets.append(TrashTarget(path: p, bytes: bytes, entryIDs: uniqueIDs))
            }
        }
        return plan
    }

    /// Formats the panel footer selection count: "N items" or "N items · M chemins" if different.
    public static func footerSelectionSummary(itemCount: Int, targetCount: Int) -> String {
        let items = itemCount == 1 ? "1 item" : "\(itemCount) items"
        if targetCount > 0 && targetCount != itemCount {
            let chemins = targetCount == 1 ? "1 chemin" : "\(targetCount) chemins"
            return "\(items) · \(chemins)"
        }
        return items
    }
}

// MARK: - Batch move to Trash

public struct BatchTrashResult: Sendable {
    public var trashed: [(path: String, bytes: Int64)] = []
    public var refused: [(path: String, refusal: DeletionRefusal)] = []
    public var failed: [(path: String, message: String)] = []
    public var trashedBytes: Int64 { trashed.reduce(0) { $0 + $1.bytes } }
    public var problemCount: Int { refused.count + failed.count }
}

public enum BatchTrasher {
    /// Move every target to the Trash, one by one. Each path is re-checked
    /// (including symlinks and existence) right before it is moved; refused
    /// or failing paths are skipped and reported. The tree is updated in place.
    public static func run(plan: TrashPlan, root: FileNode?, policy: DeletionPolicy,
                           trasher: TrashPerforming, checkExistence: Bool = true) -> BatchTrashResult {
        var result = BatchTrashResult()
        for r in plan.refused { result.refused.append((r.path, r.refusal)) }
        for target in plan.targets {
            if let refusal = policy.refusal(forPath: target.path, checkExistence: checkExistence) {
                result.refused.append((target.path, refusal))
                continue
            }
            do {
                if let root, let node = SelectionPlanner.node(atPath: target.path, in: root), node !== root {
                    _ = try FileTreeEditor.trash(node: node, root: root, policy: policy,
                                                 trasher: trasher, checkExistence: checkExistence)
                } else {
                    _ = try trasher.trashItem(at: URL(fileURLWithPath: target.path))
                }
                result.trashed.append((target.path, target.bytes))
            } catch let refusal as DeletionRefusal {
                result.refused.append((target.path, refusal))
            } catch {
                result.failed.append((target.path, (error as NSError).localizedDescription))
            }
        }
        return result
    }
}

// MARK: - Manual (clicked) selection

/// Tiles clicked in the explorer, in click order. A click toggles membership;
/// each item can be unticked in the panel without being removed.
public struct ExplorerSelection: Sendable, Equatable {
    public struct Item: Sendable, Equatable, Identifiable {
        public let path: String
        public var checked: Bool
        public var id: String { path }
    }

    public private(set) var items: [Item] = []

    public init() {}

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }
    public var checkedPaths: [String] { items.filter(\.checked).map(\.path) }

    public func contains(_ path: String) -> Bool { items.contains { $0.path == path } }

    /// Add the path (checked) or, if already present, remove it.
    /// Returns `true` when the path is now selected.
    @discardableResult
    public mutating func toggle(_ path: String) -> Bool {
        if let i = items.firstIndex(where: { $0.path == path }) {
            items.remove(at: i)
            return false
        }
        items.append(Item(path: path, checked: true))
        return true
    }

    public mutating func setChecked(_ path: String, _ checked: Bool) {
        if let i = items.firstIndex(where: { $0.path == path }) { items[i].checked = checked }
    }

    public mutating func remove(_ path: String) { items.removeAll { $0.path == path } }

    /// Drop every item equal to or inside one of `paths` (e.g. after trashing).
    public mutating func removeCovered(by paths: [String]) {
        items.removeAll { item in paths.contains { SelectionPlanner.isSameOrInside(item.path, $0) } }
    }

    public mutating func clear() { items.removeAll() }
}
