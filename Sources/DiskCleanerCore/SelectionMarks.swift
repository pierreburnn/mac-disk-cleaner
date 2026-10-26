// SelectionMarks.swift – Maps treemap items to the selected paths they represent.
import Foundation

/// Describes how a treemap item relates to the selection.
public struct SelectionMark: Equatable, Sendable {
    /// True when the item's own node path is directly selected.
    public let direct: Bool
    /// Number of selected paths hidden inside this item (not drawn as their own tile).
    public let hiddenCount: Int
    /// Total count of selected paths represented by this item.
    public var total: Int { (direct ? 1 : 0) + hiddenCount }

    public init(direct: Bool, hiddenCount: Int) {
        self.direct = direct
        self.hiddenCount = hiddenCount
    }
}

public typealias Mark = SelectionMark

public enum SelectionMarks {
    /// Maps each item id to a `SelectionMark` describing which selected paths it represents.
    ///
    /// - An item whose node path equals a selected path gets `direct = true`.
    /// - A selected path that is not drawn as its own item is attributed to the DEEPEST
    ///   drawn item whose node path contains it (using `SelectionPlanner.isSameOrInside`),
    ///   including the "other" bucket of the right parent when applicable.
    /// - Selected paths outside the displayed node are ignored (not visible at this level).
    public static func marks(
        items: [TreemapTileItem],
        selectedPaths: [String],
        displayedNodePath: String? = nil
    ) -> [String: SelectionMark] {
        guard !items.isEmpty, !selectedPaths.isEmpty else { return [:] }

        // Determine displayed root path if not provided
        let rootPath: String
        if let path = displayedNodePath {
            rootPath = path
        } else if let topWithNode = items.first(where: { $0.level == .top && $0.node != nil })?.node {
            rootPath = topWithNode.url.deletingLastPathComponent().path
        } else if let innerWithParent = items.first(where: { $0.parent != nil })?.parent {
            rootPath = innerWithParent.url.deletingLastPathComponent().path
        } else {
            return [:]
        }

        // 1. Filter selectedPaths to only those inside rootPath.
        let relevant = selectedPaths.filter {
            SelectionPlanner.isSameOrInside($0, rootPath)
        }
        guard !relevant.isEmpty else { return [:] }

        // 2. Classify items
        struct NodeItem {
            let id: String
            let path: String
        }
        struct OtherItem {
            let id: String
            let parentPath: String
            let level: TreemapTileItem.Level
        }

        var nodeItems: [NodeItem] = []
        var otherItems: [OtherItem] = []

        for item in items {
            if let node = item.node {
                nodeItems.append(NodeItem(id: item.id, path: node.url.path))
            } else if let parent = item.parent {
                otherItems.append(OtherItem(id: item.id, parentPath: parent.url.path, level: item.level))
            } else if item.level == .top {
                // Top-level other bucket
                otherItems.append(OtherItem(id: item.id, parentPath: rootPath, level: .top))
            }
        }

        var directMap: [String: Bool] = [:]
        var hiddenMap: [String: Int] = [:]

        for selectedPath in relevant {
            // (a) Exact match on a drawn item with a node -> direct mark
            if let exact = nodeItems.first(where: { $0.path == selectedPath }) {
                directMap[exact.id] = true
                continue
            }

            // (b) Find deepest candidate that contains selectedPath
            // Candidates: (id: String, depth: Int)
            var candidates: [(id: String, depth: Int)] = []

            // Candidate from drawn items with a node
            for ni in nodeItems {
                if SelectionPlanner.isSameOrInside(selectedPath, ni.path) {
                    candidates.append((id: ni.id, depth: ni.path.count))
                }
            }

            // Candidate from other buckets
            for oi in otherItems {
                guard SelectionPlanner.isSameOrInside(selectedPath, oi.parentPath) else { continue }
                if oi.level == .inner {
                    // Inner other bucket belongs to oi.parentPath.
                    // It is eligible only if selectedPath is NOT covered by any drawn child of oi.parentPath.
                    let coveredByChild = nodeItems.contains { ni in
                        SelectionPlanner.isSameOrInside(ni.path, oi.parentPath)
                            && ni.path != oi.parentPath
                            && SelectionPlanner.isSameOrInside(selectedPath, ni.path)
                    }
                    if !coveredByChild {
                        // Depth is deeper than parentPath
                        candidates.append((id: oi.id, depth: oi.parentPath.count + 1))
                    }
                } else if oi.level == .top {
                    // Top-level other bucket belongs to rootPath.
                    // It is eligible only if selectedPath is NOT covered by any drawn top tile.
                    let coveredByTop = nodeItems.contains { ni in
                        SelectionPlanner.isSameOrInside(selectedPath, ni.path)
                    }
                    if !coveredByTop {
                        candidates.append((id: oi.id, depth: oi.parentPath.count + 1))
                    }
                }
            }

            if let best = candidates.max(by: { $0.depth < $1.depth }) {
                hiddenMap[best.id, default: 0] += 1
            }
        }

        // Build result dictionary
        var result: [String: SelectionMark] = [:]
        let allIDs = Set(directMap.keys).union(hiddenMap.keys)
        for id in allIDs {
            result[id] = SelectionMark(
                direct: directMap[id] ?? false,
                hiddenCount: hiddenMap[id] ?? 0
            )
        }
        return result
    }

    /// Maps each item id to the number of selected paths it represents.
    public static func selectionMarks(
        items: [TreemapTileItem],
        selectedPaths: [String],
        displayedNodePath: String? = nil
    ) -> [String: Int] {
        let m = marks(items: items, selectedPaths: selectedPaths, displayedNodePath: displayedNodePath)
        return m.mapValues(\.total)
    }

    /// How many selected paths are represented (visible) at this level.
    public static func visibleCount(
        items: [TreemapTileItem],
        selectedPaths: [String],
        displayedNodePath: String? = nil
    ) -> Int {
        let m = marks(items: items, selectedPaths: selectedPaths, displayedNodePath: displayedNodePath)
        return m.values.reduce(0) { $0 + $1.total }
    }
}
