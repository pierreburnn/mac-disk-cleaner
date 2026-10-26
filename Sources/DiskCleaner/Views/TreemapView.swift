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

// MARK: - Layout cache (avoid recomputing items during animation)

/// Caches the last `TreemapGeometry.items(for:in:)` result so that body
/// re-evaluations triggered by the zoom animation state don't re-run the
/// expensive layout algorithm.  Keyed by (node identity, rounded size,
/// treeRevision).
final class TreemapItemsCache {
    private var nodeID: ObjectIdentifier?
    private var roundedWidth: CGFloat = 0
    private var roundedHeight: CGFloat = 0
    private var revision: Int = -1
    private(set) var items: [TreemapTileItem] = []

    /// Returns cached items or recomputes them.
    func get(for node: FileNode, in size: CGSize, revision rev: Int) -> [TreemapTileItem] {
        let rw = (size.width * 2).rounded(.down) / 2
        let rh = (size.height * 2).rounded(.down) / 2
        let nid = ObjectIdentifier(node)
        if nid == nodeID, rw == roundedWidth, rh == roundedHeight, rev == revision {
            return items
        }
        let result = TreemapGeometry.items(for: node, in: size)
        nodeID = nid
        roundedWidth = rw
        roundedHeight = rh
        revision = rev
        items = result
        return result
    }
}

// MARK: - CGRect interpolation helper

private func interpolateRect(_ a: CGRect, _ b: CGRect, t: CGFloat) -> CGRect {
    CGRect(x: a.minX + (b.minX - a.minX) * t,
           y: a.minY + (b.minY - a.minY) * t,
           width: a.width + (b.width - a.width) * t,
           height: a.height + (b.height - a.height) * t)
}

struct TreemapView: View {
    let node: FileNode
    @EnvironmentObject var model: AppModel
    @Environment(\.isSnapshot) private var isSnapshot: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @State private var cache = TreemapItemsCache()

    // Zoom animation state
    @State private var zoomOverlay: ZoomOverlayState?
    @State private var tilesOpacity: Double = 1
    @State private var overlayOpacity: Double = 1
    @State private var overlayRect: CGRect = .zero
    @State private var activeZoomID: UUID?

    var body: some View {
        GeometryReader { geo in
            let _ = model.treeRevision
            let items = cache.get(for: node, in: geo.size, revision: model.treeRevision)
            // In snapshot mode with a zoom-in overlay in progress, hide the tiles.
            let snapshotHidesTiles: Bool = isSnapshot
                && model.snapshotZoom != nil
                && model.snapshotZoom!.request.direction == .zoomIn
                && model.snapshotZoom!.progress < 1
            let effectiveTilesOpacity = snapshotHidesTiles ? 0.0 : tilesOpacity
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(items) { item in
                    TreemapTile(item: item)
                        .frame(width: item.rect.width, height: item.rect.height)
                        .position(x: item.rect.midX, y: item.rect.midY)
                }
                .opacity(effectiveTilesOpacity)

                // Zoom overlay (animated or snapshot-static)
                if let overlay = effectiveOverlay(geo: geo) {
                    let r = overlay.rect
                    RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                        .fill(overlay.fill)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                                .strokeBorder(overlay.border, lineWidth: 1)
                        )
                        .overlay(alignment: .topLeading) {
                            Text(overlay.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.top, 6)
                        }
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                        .opacity(overlay.opacity)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .onChange(of: model.zoomRequest) { request in
                guard !isSnapshot else { return }
                guard let request = request else { return }
                handleZoomRequest(request, in: geo.size)
            }
            .onAppear {
                let sz = geo.size
                if sz != model.lastTreemapSize {
                    model.lastTreemapSize = sz
                }
                // Consume a pending zoom request (e.g. set before this view appeared)
                if !isSnapshot, let request = model.zoomRequest {
                    handleZoomRequest(request, in: geo.size)
                }
            }
        }
    }

    // MARK: - Snapshot / live overlay

    /// In snapshot mode, use `model.snapshotZoom` to produce a static overlay.
    /// In live mode, use the animated `zoomOverlay` state.
    private func effectiveOverlay(geo: GeometryProxy) -> ZoomOverlayRendered? {
        if isSnapshot, let snap = model.snapshotZoom {
            let bounds = CGRect(origin: .zero, size: geo.size)
            let req = snap.request
            let cat = req.node.category
            let startRect: CGRect
            let endRect: CGRect
            if req.direction == .zoomIn {
                startRect = req.rect
                endRect = bounds
            } else {
                startRect = bounds
                endRect = req.rect == .zero ? bounds : req.rect
            }
            let r = interpolateRect(startRect, endRect, t: snap.progress)
            // Children hidden when progress < 1 for zoom-in
            if req.direction == .zoomIn, snap.progress < 1 {
                // We cannot set @State from here; the caller should handle tilesOpacity
                // For snapshot just render with opacity embedded
            }
            return ZoomOverlayRendered(
                rect: r,
                fill: Theme.tileFill(for: cat),
                border: Theme.tileBorder(for: cat),
                name: req.node.name,
                opacity: 1
            )
        }
        guard let overlay = zoomOverlay else { return nil }
        return ZoomOverlayRendered(
            rect: overlayRect,
            fill: overlay.fill,
            border: overlay.border,
            name: overlay.name,
            opacity: overlayOpacity
        )
    }

    // MARK: - Zoom animation

    private func handleZoomRequest(_ request: ZoomRequest, in size: CGSize) {
        let requestID = request.id
        activeZoomID = requestID

        if reduceMotion {
            // Quick cross-fade
            tilesOpacity = 0
            withAnimation(.easeOut(duration: 0.15)) {
                tilesOpacity = 1
            }
            model.zoomRequest = nil
            return
        }

        let bounds = CGRect(origin: .zero, size: size)
        let cat = request.node.category

        let overlay = ZoomOverlayState(
            fill: Theme.tileFill(for: cat),
            border: Theme.tileBorder(for: cat),
            name: request.node.name
        )

        switch request.direction {
        case .zoomIn:
            zoomOverlay = overlay
            overlayRect = request.rect
            overlayOpacity = 1
            tilesOpacity = 0

            withAnimation(.easeInOut(duration: 0.35)) {
                overlayRect = bounds
            }
            // After grow finishes, fade in children and fade out overlay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard activeZoomID == requestID else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    tilesOpacity = 1
                    overlayOpacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    guard activeZoomID == requestID else { return }
                    zoomOverlay = nil
                    overlayOpacity = 1
                    model.zoomRequest = nil
                }
            }

        case .zoomOut:
            // Find the destination tile rect in the new layout
            let items = cache.get(for: node, in: size, revision: model.treeRevision)
            let destRect = findTileRect(for: request.node, in: items) ?? bounds

            zoomOverlay = overlay
            overlayRect = bounds
            overlayOpacity = 1
            tilesOpacity = 0

            withAnimation(.easeInOut(duration: 0.35)) {
                overlayRect = destRect
                tilesOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard activeZoomID == requestID else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    overlayOpacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    guard activeZoomID == requestID else { return }
                    zoomOverlay = nil
                    overlayOpacity = 1
                    model.zoomRequest = nil
                }
            }
        }
    }

    /// Find the rect in `items` for `targetNode`, or its nearest drawn ancestor.
    private func findTileRect(for targetNode: FileNode, in items: [TreemapTileItem]) -> CGRect? {
        let targetPath = targetNode.url.path
        // Prefer the deepest match (exact node first, then ancestors)
        var bestMatch: CGRect?
        var bestDepth: Int = -1
        for item in items {
            guard let itemNode = item.node else { continue }
            let itemPath = itemNode.url.path
            if SelectionPlanner.isSameOrInside(targetPath, itemPath) {
                let depth = itemPath.count  // deeper path = more specific
                if depth > bestDepth {
                    bestDepth = depth
                    bestMatch = item.rect
                }
            }
        }
        return bestMatch
    }
}

/// Internal state for the zoom overlay tile.
private struct ZoomOverlayState {
    let fill: Color
    let border: Color
    let name: String
}

/// Resolved overlay for rendering.
private struct ZoomOverlayRendered {
    let rect: CGRect
    let fill: Color
    let border: Color
    let name: String
    let opacity: Double
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
        // Single click toggles the tile in the selection immediately (no waiting
        // for a possible double click). A double click toggles twice (net: no
        // change) and zooms into the tile.
        .gesture(TapGesture(count: 2).onEnded { enter() })
        .simultaneousGesture(TapGesture(count: 1).onEnded { select() })
        .help(helpText)
    }

    private var isSelected: Bool { model.isInSelection(item.node) }

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

    /// Single click: add to / remove from the multi-selection (real items only).
    private func select() {
        guard let node = item.node else { return }
        model.toggleTile(node)
    }

    /// Double click: zoom into the tile.
    private func enter() {
        guard let node = item.node else { return }
        model.zoomInto(node, via: item.parent, from: item.rect)
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
