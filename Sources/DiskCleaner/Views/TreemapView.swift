// TreemapView.swift – Two-level squarified treemap with absolute positioning.
import SwiftUI
import AppKit
import DiskCleanerCore

// MARK: - Layout cache (avoid recomputing items during animation)

/// Caches `TreemapGeometry.items(for:in:)` results so that body
/// re-evaluations triggered by the zoom animation state don't re-run the
/// expensive layout algorithm. Keyed by (node identity, rounded size, treeRevision).
final class TreemapItemsCache {
    private struct Key: Hashable {
        let nodeID: ObjectIdentifier
        let roundedWidth: CGFloat
        let roundedHeight: CGFloat
        let revision: Int
    }
    private var storage: [Key: [TreemapTileItem]] = [:]

    /// Returns cached items or recomputes them.
    func get(for node: FileNode, in size: CGSize, revision rev: Int) -> [TreemapTileItem] {
        let rw = (size.width * 2).rounded(.down) / 2
        let rh = (size.height * 2).rounded(.down) / 2
        let key = Key(nodeID: ObjectIdentifier(node), roundedWidth: rw, roundedHeight: rh, revision: rev)
        if let cached = storage[key] {
            return cached
        }
        let result = TreemapGeometry.items(for: node, in: size)
        storage[key] = result
        return result
    }
}

/// Internal state for an in-flight zoom animation.
private struct ZoomActiveState {
    let id: UUID
    let direction: ZoomRequest.Direction
    let startRect: CGRect
    let endRect: CGRect
    let childItems: [TreemapTileItem]
    let parentItems: [TreemapTileItem]
    let category: NodeCategory
}

/// Scaled tiles overlay conforming to Animatable so that SwiftUI interpolates
/// `progress` smoothly on each frame.
private struct ZoomingTileOverlay: View, Animatable {
    var progress: CGFloat
    let zoom: ZoomActiveState
    let fullBounds: CGRect

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = min(max(progress, 0), 1)
        let currentFrame = ZoomGeometry.frame(from: zoom.startRect, to: zoom.endRect, progress: p)

        if zoom.direction == .zoomIn {
            // During zoom-in:
            // Underneath: parent tiles are drawn.
            // On top: growing folder tile background and scaled children fading in from 0.6 to 1 opacity.
            let contentOpacity = 0.6 + 0.4 * Double(p)

            ZStack(alignment: .topLeading) {
                if !zoom.parentItems.isEmpty {
                    ForEach(zoom.parentItems) { item in
                        TreemapTile(item: item)
                            .frame(width: max(0, item.rect.width), height: max(0, item.rect.height))
                            .position(x: item.rect.midX, y: item.rect.midY)
                    }
                }

                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .fill(Theme.tileFill(for: zoom.category))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                            .strokeBorder(Theme.tileBorder(for: zoom.category), lineWidth: 1)
                    )
                    .frame(width: max(0, currentFrame.width), height: max(0, currentFrame.height))
                    .position(x: currentFrame.midX, y: currentFrame.midY)

                ForEach(zoom.childItems) { item in
                    let mappedRect = ZoomGeometry.map(item.rect, from: fullBounds, into: currentFrame)
                    if mappedRect.width >= 1 && mappedRect.height >= 1 {
                        let mappedItem = TreemapTileItem(
                            id: "anim-\(item.id)",
                            node: item.node,
                            parent: item.parent,
                            rect: mappedRect,
                            level: item.level,
                            showsChildren: item.showsChildren,
                            aggregateBytes: item.aggregateBytes,
                            aggregateCount: item.aggregateCount
                        )
                        TreemapTile(item: mappedItem)
                            .frame(width: mappedRect.width, height: mappedRect.height)
                            .position(x: mappedRect.midX, y: mappedRect.midY)
                    }
                }
                .opacity(contentOpacity)
            }
            .allowsHitTesting(false)
        } else {
            // During zoom-out:
            // Previous child layout shrinks into destRect and fades out from 1 to 0 opacity.
            let overlayOpacity = max(0, 1.0 - Double(p))

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .fill(Theme.tileFill(for: zoom.category))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                            .strokeBorder(Theme.tileBorder(for: zoom.category), lineWidth: 1)
                    )
                    .frame(width: max(0, currentFrame.width), height: max(0, currentFrame.height))
                    .position(x: currentFrame.midX, y: currentFrame.midY)

                ForEach(zoom.childItems) { item in
                    let mappedRect = ZoomGeometry.map(item.rect, from: fullBounds, into: currentFrame)
                    if mappedRect.width >= 1 && mappedRect.height >= 1 {
                        let mappedItem = TreemapTileItem(
                            id: "anim-out-\(item.id)",
                            node: item.node,
                            parent: item.parent,
                            rect: mappedRect,
                            level: item.level,
                            showsChildren: item.showsChildren,
                            aggregateBytes: item.aggregateBytes,
                            aggregateCount: item.aggregateCount
                        )
                        TreemapTile(item: mappedItem)
                            .frame(width: mappedRect.width, height: mappedRect.height)
                            .position(x: mappedRect.midX, y: mappedRect.midY)
                    }
                }
            }
            .opacity(overlayOpacity)
            .allowsHitTesting(false)
        }
    }
}

struct TreemapView: View {
    let node: FileNode
    @EnvironmentObject var model: AppModel
    @Environment(\.isSnapshot) private var isSnapshot: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @State private var cache = TreemapItemsCache()

    // Zoom animation state
    @State private var activeZoom: ZoomActiveState?
    @State private var zoomProgress: CGFloat = 0
    @State private var tilesOpacity: Double = 1
    @State private var activeZoomID: UUID?

    var body: some View {
        GeometryReader { geo in
            let _ = model.treeRevision
            let items = cache.get(for: node, in: geo.size, revision: model.treeRevision)
            let isSnapshotZooming = isSnapshot && model.snapshotZoom != nil

            ZStack(alignment: .topLeading) {
                Color.clear

                // Base treemap tiles (hidden during snapshot zoom, or animated during live zoom)
                if !isSnapshotZooming {
                    ForEach(items) { item in
                        TreemapTile(item: item)
                            .frame(width: item.rect.width, height: item.rect.height)
                            .position(x: item.rect.midX, y: item.rect.midY)
                    }
                    .opacity(tilesOpacity)
                }

                // Snapshot static overlay
                if isSnapshot, let snap = model.snapshotZoom {
                    snapshotOverlay(snap: snap, size: geo.size)
                }

                // Live animation overlay
                if !isSnapshot, let zoom = activeZoom {
                    ZoomingTileOverlay(progress: zoomProgress, zoom: zoom, fullBounds: CGRect(origin: .zero, size: geo.size))
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

    // MARK: - Snapshot overlay

    @ViewBuilder
    private func snapshotOverlay(snap: (request: ZoomRequest, progress: CGFloat), size: CGSize) -> some View {
        let req = snap.request
        let parent = req.parent ?? model.rootNode
        let fullBounds = CGRect(origin: .zero, size: size)
        let startRect: CGRect
        let endRect: CGRect

        if req.direction == .zoomIn {
            if let parent, let calculated = ZoomGeometry.startRect(of: req.node, in: parent, size: size) {
                startRect = calculated
            } else if req.rect != .zero {
                startRect = req.rect
            } else {
                startRect = fullBounds
            }
            endRect = fullBounds
        } else {
            startRect = fullBounds
            endRect = (parent != nil ? ZoomGeometry.startRect(of: req.node, in: parent!, size: size) : nil)
                ?? (req.rect != .zero ? req.rect : fullBounds)
        }

        let childItems = cache.get(for: req.node, in: size, revision: model.treeRevision)
        let parentItems = parent != nil ? cache.get(for: parent!, in: size, revision: model.treeRevision) : []

        let zoomState = ZoomActiveState(
            id: req.id,
            direction: req.direction,
            startRect: startRect,
            endRect: endRect,
            childItems: childItems,
            parentItems: parentItems,
            category: req.node.category
        )
        ZoomingTileOverlay(progress: snap.progress, zoom: zoomState, fullBounds: fullBounds)
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

        switch request.direction {
        case .zoomIn:
            let parent = request.parent ?? model.rootNode
            let startRect: CGRect
            if let parent, let calculated = ZoomGeometry.startRect(of: request.node, in: parent, size: size) {
                startRect = calculated
            } else if request.rect != .zero {
                startRect = request.rect
            } else {
                startRect = bounds
            }
            let endRect = bounds
            let childItems = cache.get(for: request.node, in: size, revision: model.treeRevision)
            let parentItems = parent != nil ? cache.get(for: parent!, in: size, revision: model.treeRevision) : []

            activeZoom = ZoomActiveState(
                id: requestID,
                direction: .zoomIn,
                startRect: startRect,
                endRect: endRect,
                childItems: childItems,
                parentItems: parentItems,
                category: request.node.category
            )
            zoomProgress = 0
            tilesOpacity = 0

            withAnimation(.easeInOut(duration: 0.35)) {
                zoomProgress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard activeZoomID == requestID else { return }
                tilesOpacity = 1
                activeZoom = nil
                model.zoomRequest = nil
            }

        case .zoomOut:
            // Find the destination tile rect in the new layout
            let parent = node
            let destRect = ZoomGeometry.startRect(of: request.node, in: parent, size: size)
                ?? findTileRect(for: request.node, in: cache.get(for: parent, in: size, revision: model.treeRevision))
                ?? bounds

            let childItems = cache.get(for: request.node, in: size, revision: model.treeRevision)
            let parentItems = cache.get(for: parent, in: size, revision: model.treeRevision)

            activeZoom = ZoomActiveState(
                id: requestID,
                direction: .zoomOut,
                startRect: bounds,
                endRect: destRect,
                childItems: childItems,
                parentItems: parentItems,
                category: request.node.category
            )
            zoomProgress = 0
            tilesOpacity = 0

            withAnimation(.easeInOut(duration: 0.35)) {
                zoomProgress = 1
                tilesOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard activeZoomID == requestID else { return }
                tilesOpacity = 1
                activeZoom = nil
                model.zoomRequest = nil
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
