// TreemapGeometry.swift – Pure geometry for squarified treemaps and zoom transitions
import Foundation

/// One rectangle to draw. Computed up-front so the view tree stays flat and
/// every tile is placed with `.position` in a top-leading coordinate space.
public struct TreemapTileItem: Identifiable, Sendable {
    public enum Level: Sendable { case top, inner }
    public let id: String
    public let node: FileNode?          // nil = "other" bucket (many tiny items)
    public let parent: FileNode?        // parent tile for inner items
    public let rect: CGRect
    public let level: Level
    public let showsChildren: Bool
    /// For the "other" bucket: bytes and item count it stands for.
    public var aggregateBytes: Int64
    public var aggregateCount: Int

    public init(
        id: String,
        node: FileNode?,
        parent: FileNode?,
        rect: CGRect,
        level: Level,
        showsChildren: Bool,
        aggregateBytes: Int64 = 0,
        aggregateCount: Int = 0
    ) {
        self.id = id
        self.node = node
        self.parent = parent
        self.rect = rect
        self.level = level
        self.showsChildren = showsChildren
        self.aggregateBytes = aggregateBytes
        self.aggregateCount = aggregateCount
    }
}

public enum TreemapGeometry {
    public static let outerGap: CGFloat = 3      // half of the 6 pt gap between top-level tiles
    public static let innerGap: CGFloat = 2      // half of the 4 pt gap between inner tiles
    public static let headerHeight: CGFloat = 25
    public static let innerPadding: CGFloat = 6

    public static func items(for node: FileNode, in size: CGSize) -> [TreemapTileItem] {
        guard size.width > 1, size.height > 1 else { return [] }
        var result: [TreemapTileItem] = []
        let outer = TMRect(x: 0, y: 0, width: Double(size.width), height: Double(size.height))
        let tops = TreemapLayout.layoutChildren(of: node, in: outer, minFraction: 0.002)
        let topAgg = aggregate(of: node, shown: tops.compactMap(\.node))
        for (i, top) in tops.enumerated() {
            let r = inset(top.rect, outerGap)
            guard r.width >= 2, r.height >= 2 else { continue }
            let child = top.node
            let canNest = child.map { $0.isDirectory && $0.children.count > 0 } ?? false
                && r.width > 70 && r.height > 56
            result.append(TreemapTileItem(id: "t\(i)-\(child?.id ?? "other")", node: child, parent: nil,
                                          rect: r, level: .top, showsChildren: canNest,
                                          aggregateBytes: child == nil ? topAgg.bytes : 0,
                                          aggregateCount: child == nil ? topAgg.count : 0))
            guard canNest, let child else { continue }
            let innerArea = TMRect(x: Double(r.minX + innerPadding - innerGap),
                                   y: Double(r.minY + headerHeight - innerGap),
                                   width: Double(r.width - 2 * (innerPadding - innerGap)),
                                   height: Double(r.height - headerHeight - innerPadding + 2 * innerGap))
            guard innerArea.width > 8, innerArea.height > 8 else { continue }
            let inners = TreemapLayout.layoutChildren(of: child, in: innerArea, minFraction: 0.004)
            let innerAgg = aggregate(of: child, shown: inners.compactMap(\.node))
            for (j, inner) in inners.enumerated() {
                let ir = inset(inner.rect, innerGap)
                // Skip hairline slivers: they read as stray stripes, not tiles.
                guard ir.width >= 6, ir.height >= 6 else { continue }
                result.append(TreemapTileItem(id: "t\(i)-\(j)-\(inner.node?.id ?? "other")", node: inner.node,
                                              parent: child, rect: ir, level: .inner, showsChildren: false,
                                              aggregateBytes: inner.node == nil ? innerAgg.bytes : 0,
                                              aggregateCount: inner.node == nil ? innerAgg.count : 0))
            }
        }
        return result
    }

    /// What the "other" bucket of `node` stands for, given the children drawn individually.
    public static func aggregate(of node: FileNode, shown: [FileNode]) -> (bytes: Int64, count: Int) {
        let shownBytes = shown.reduce(Int64(0)) { $0 + max(0, $1.totalAllocatedSize) }
        let bytes = max(0, node.totalAllocatedSize - shownBytes)
        let count = max(0, node.children.count - shown.count) + node.mergedFileCount
        return (bytes, count)
    }

    public static func inset(_ r: TMRect, _ d: CGFloat) -> CGRect {
        CGRect(x: CGFloat(r.x) + d, y: CGFloat(r.y) + d,
               width: max(0, CGFloat(r.width) - 2 * d), height: max(0, CGFloat(r.height) - 2 * d))
    }

    public static func insets(_ r: TMRect, _ d: CGFloat) -> CGRect {
        inset(r, d)
    }
}

public enum ZoomGeometry {
    /// Linear interpolation between start and end rects, progress clamped to 0...1.
    /// Easing is applied by the caller/animation.
    public static func frame(from start: CGRect, to end: CGRect, progress: CGFloat) -> CGRect {
        let p = min(max(progress, 0), 1)
        return CGRect(
            x: start.minX + (end.minX - start.minX) * p,
            y: start.minY + (end.minY - start.minY) * p,
            width: start.width + (end.width - start.width) * p,
            height: start.height + (end.height - start.height) * p
        )
    }

    /// Transforms a rect from `bounds` coordinate space into `frame` coordinate space:
    /// x' = frame.minX + (x - bounds.minX) * frame.width / bounds.width
    /// y' = frame.minY + (y - bounds.minY) * frame.height / bounds.height
    /// same for widths and heights.
    public static func map(_ rect: CGRect, from bounds: CGRect, into frame: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return frame }
        let scaleX = frame.width / bounds.width
        let scaleY = frame.height / bounds.height
        let x = frame.minX + (rect.minX - bounds.minX) * scaleX
        let y = frame.minY + (rect.minY - bounds.minY) * scaleY
        let width = rect.width * scaleX
        let height = rect.height * scaleY
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Returns the mapped rects of `TreemapGeometry.items(for: node, in: bounds)` at that progress.
    public static func animatedChildren(
        of node: FileNode,
        bounds: CGSize,
        startRect: CGRect,
        progress: CGFloat
    ) -> [CGRect] {
        let fullBounds = CGRect(origin: .zero, size: bounds)
        let currentFrame = frame(from: startRect, to: fullBounds, progress: progress)
        let items = TreemapGeometry.items(for: node, in: bounds)
        return items.map { map($0.rect, from: fullBounds, into: currentFrame) }
    }

    /// Returns the rect of the top-level tile for `child` in `TreemapGeometry.items(for: parent, in: size)`.
    public static func startRect(of child: FileNode, in parent: FileNode, size: CGSize) -> CGRect? {
        let items = TreemapGeometry.items(for: parent, in: size)
        if let exact = items.first(where: { $0.level == .top && ($0.node === child || $0.node?.id == child.id) }) {
            return exact.rect
        }
        // In case child is a descendant of a top-level node
        let childPath = child.url.path
        if let ancestor = items.first(where: { item in
            guard item.level == .top, let node = item.node else { return false }
            let p = node.url.path
            return childPath == p || childPath.hasPrefix(p.hasSuffix("/") ? p : p + "/")
        }) {
            return ancestor.rect
        }
        return nil
    }
}
