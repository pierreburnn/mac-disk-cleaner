// TreemapView.swift – Two-level squarified treemap with absolute positioning.
import SwiftUI
import AppKit
import DiskCleanerCore

/// One rectangle to draw. Computed up-front so the view tree stays flat and
/// every tile is placed with `.position` in a top-leading coordinate space.
struct TreemapTileItem: Identifiable {
    enum Level { case top, inner }
    let id: String
    let node: FileNode?          // nil = "other" bucket (many tiny items)
    let parent: FileNode?        // parent tile for inner items
    let rect: CGRect
    let level: Level
    let showsChildren: Bool
    /// For the "other" bucket: bytes and item count it stands for.
    var aggregateBytes: Int64 = 0
    var aggregateCount: Int = 0
}

enum TreemapGeometry {
    static let outerGap: CGFloat = 3      // half of the 6 pt gap between top-level tiles
    static let innerGap: CGFloat = 2      // half of the 4 pt gap between inner tiles
    static let headerHeight: CGFloat = 25
    static let innerPadding: CGFloat = 6

    static func items(for node: FileNode, in size: CGSize) -> [TreemapTileItem] {
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
    static func aggregate(of node: FileNode, shown: [FileNode]) -> (bytes: Int64, count: Int) {
        let shownBytes = shown.reduce(Int64(0)) { $0 + max(0, $1.totalAllocatedSize) }
        let bytes = max(0, node.totalAllocatedSize - shownBytes)
        let count = max(0, node.children.count - shown.count) + node.mergedFileCount
        return (bytes, count)
    }

    private static func inset(_ r: TMRect, _ d: CGFloat) -> CGRect {
        CGRect(x: CGFloat(r.x) + d, y: CGFloat(r.y) + d,
               width: max(0, CGFloat(r.width) - 2 * d), height: max(0, CGFloat(r.height) - 2 * d))
    }
}

struct TreemapView: View {
    let node: FileNode
    @EnvironmentObject var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let _ = model.treeRevision
            let items = TreemapGeometry.items(for: node, in: geo.size)
            ZStack(alignment: .topLeading) {
                // Clicking empty space (gaps, margins) clears the selection.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.select(nil) }
                ForEach(items) { item in
                    TreemapTile(item: item)
                        .frame(width: item.rect.width, height: item.rect.height)
                        .position(x: item.rect.midX, y: item.rect.midY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}

// MARK: - Tile

struct TreemapTile: View {
    let item: TreemapTileItem
    @EnvironmentObject var model: AppModel
    @State private var hovered = false

    private var isTop: Bool { item.level == .top }
    private var radius: CGFloat { isTop ? Theme.tileRadius : 4.5 }

    private var coverage: TileCoverage {
        guard let node = item.node else { return .none }
        return model.coverage(of: node)
    }

    private var category: NodeCategory {
        item.node?.category ?? item.parent?.category ?? .devTools
    }

    private enum Style { case normal, muted, safe, review }

    private var style: Style {
        let c = coverage
        if model.displayMode == .category {
            return c.kind != .none && c.selected ? .safe : .normal
        }
        switch c.kind {
        case .safe: return .safe
        case .review: return .review
        case .none: return .muted
        }
    }

    /// A top-level tile that only *contains* covered children keeps a neutral fill.
    private var fill: Color {
        let categoryFill = isTop ? Theme.tileFill(for: category) : Theme.innerTileFill(for: category)
        switch style {
        case .normal: return categoryFill
        case .safe: return model.displayMode == .category ? categoryFill : Theme.cleanupFill
        case .review: return Theme.reviewFill
        case .muted: return isTop ? Theme.mutedFill : Theme.mutedInnerFill
        }
    }

    private var border: Color {
        switch style {
        case .safe: return Theme.cleanableBorder
        case .review: return Theme.reviewBorder
        case .muted: return Theme.mutedBorder
        case .normal: return Theme.tileBorder(for: category)
        }
    }

    private var hatch: Color? {
        switch style {
        case .safe: return Theme.hatchGreen
        case .review: return coverage.selected ? Theme.hatchAmber : nil
        default: return nil
        }
    }

    private var textOpacity: Double { style == .muted ? 0.55 : 1 }

    var body: some View {
        let w = item.rect.width
        let h = item.rect.height
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
            if let hatch {
                HatchingPattern(color: hatch, spacing: isTop ? 7 : 6)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(hovered ? border.opacity(1) : border,
                              lineWidth: (style == .safe || style == .review) ? 1.2 : 1)
            if let node = item.node {
                labels(node: node, w: w, h: h).opacity(textOpacity)
            }
            if isSelected {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.selectionColor, lineWidth: 2)
                RoundedRectangle(cornerRadius: max(0, radius - 2), style: .continuous)
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                    .padding(2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        // Single click selects immediately (no waiting for a possible double
        // click); a double click then also enters the tile. Selecting first is
        // harmless because entering clears the selection.
        .gesture(TapGesture(count: 2).onEnded { enter() })
        .simultaneousGesture(TapGesture(count: 1).onEnded { select() })
        .help(helpText)
    }

    private var isSelected: Bool {
        switch model.tileSelection {
        case .node(let n)?: return item.node === n
        case .aggregate(let p, _, _)?: return item.node == nil && (item.parent ?? model.currentNode) === p
        default: return false
        }
    }

    private var helpText: String {
        if let n = item.node {
            let hint = (n.isDirectory && !n.children.isEmpty) ? " — double-clic pour entrer" : ""
            return "\(n.name) — \(ByteFormatter.format(n.totalAllocatedSize))\(hint)"
        }
        return "\(item.aggregateCount) petits éléments — \(ByteFormatter.format(item.aggregateBytes))"
    }

    @ViewBuilder
    private func labels(node: FileNode, w: CGFloat, h: CGFloat) -> some View {
        let size = (node.approximate ? "~" : "") + ByteFormatter.format(node.totalAllocatedSize)
        if isTop {
            VStack(alignment: .leading, spacing: 0) {
                if w > 44 && h > 18 {
                    let showHeaderSize = headerFits(name: node.name, size: size, width: w)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(node.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        Spacer(minLength: 0)
                        if showHeaderSize {
                            Text(size)
                                .font(Theme.monoFont(size: 11))
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
                if bigSizeVisible(w: w, h: h) {
                    Text(size)
                        .font(Theme.monoFont(size: 18, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 7)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if w > 56 && h > 26 {
                    Text(node.name)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textPrimary.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                        .padding(.top, 5)
                }
                Spacer(minLength: 0)
                if w > 58 && h > 44 {
                    Text(size)
                        .font(Theme.monoFont(size: h > 70 && w > 90 ? 15 : 12.5, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 5)
                }
            }
        }
    }

    /// The header size is only shown when the full name *and* the size fit;
    /// otherwise the name gets all the room (and truncates only if it must).
    private func headerFits(name: String, size: String, width: CGFloat) -> Bool {
        guard width > 80 else { return false }
        let available = width - 14 - 4 - 2
        return TextMetrics.width(name, size: 12, weight: .medium)
            + TextMetrics.width(size, size: 11, mono: true) <= available
    }

    /// Leaf top-level tiles (no nested children) show their size large, bottom-left.
    private func bigSizeVisible(w: CGFloat, h: CGFloat) -> Bool {
        !item.showsChildren && w > 70 && h > 56
    }

    private func select() {
        if let node = item.node {
            model.select(.node(node))
        } else if let container = item.parent ?? model.currentNode {
            model.select(.aggregate(parent: container, bytes: item.aggregateBytes, count: item.aggregateCount))
        }
    }

    private func enter() {
        guard let node = item.node else { return }
        if let parent = item.parent {
            model.navigateTo(node: node, via: parent)
        } else if node.isDirectory && !node.children.isEmpty {
            model.navigateTo(node: node)
        }
    }
}

// MARK: - Text measurement

enum TextMetrics {
    static func width(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, mono: Bool = false) -> CGFloat {
        let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                        : NSFont.systemFont(ofSize: size, weight: weight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

// MARK: - Hatching

struct HatchingPattern: View {
    var color: Color = Theme.hatchGreen
    var spacing: CGFloat = 7
    var lineWidth: CGFloat = 1.3

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let total = size.width + size.height
            var offset: CGFloat = -size.height
            while offset < total {
                path.move(to: CGPoint(x: offset, y: size.height))
                path.addLine(to: CGPoint(x: offset + size.height, y: 0))
                offset += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
    }
}
