// TreemapView.swift – Treemap visualization with nested tiles
import SwiftUI
import DiskCleanerCore

struct TreemapView: View {
    let node: FileNode
    @EnvironmentObject var model: AppModel
    @Environment(\.isSnapshot) var isSnapshot: Bool

    var body: some View {
        GeometryReader { geo in
            let rect = TMRect(x: 0, y: 0, width: Double(geo.size.width), height: Double(geo.size.height))
            let items = TreemapLayout.layoutChildren(of: node, in: rect, minFraction: 0.008)

            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    if let childNode = item.node {
                        TopLevelTile(
                            node: childNode,
                            rect: insetRect(item.rect, by: 3)
                        )
                        .environmentObject(model)
                        .environment(\.isSnapshot, isSnapshot)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func insetRect(_ r: TMRect, by amount: Double) -> TMRect {
        return TMRect(
            x: r.x + amount,
            y: r.y + amount,
            width: max(0, r.width - amount * 2),
            height: max(0, r.height - amount * 2)
        )
    }
}

// MARK: - Top-level tile

struct TopLevelTile: View {
    let node: FileNode
    let rect: TMRect
    @EnvironmentObject var model: AppModel
    @Environment(\.isSnapshot) var isSnapshot: Bool
    @State private var isHovered: Bool = false

    private var isCleanupMode: Bool {
        model.displayMode == .cleanup
    }

    private var isCleanable: Bool {
        model.isCleanable(node: node)
    }

    private var shouldDim: Bool {
        isCleanupMode && !isCleanable
    }

    private var fillColor: Color {
        if isCleanupMode && isCleanable {
            return Theme.cleanupFill
        }
        return Theme.tileFill(for: node.category)
    }

    private var borderColor: Color {
        if isCleanable {
            return Theme.cleanableBorder
        }
        return isHovered ? Theme.tileBorder(for: node.category).opacity(0.8) : Theme.tileBorder(for: node.category)
    }

    var body: some View {
        let w = CGFloat(rect.width)
        let h = CGFloat(rect.height)

        ZStack(alignment: .topLeading) {
            // Background
            RoundedRectangle(cornerRadius: Theme.tileRadius)
                .fill(fillColor)

            // Hatching for cleanable tiles
            if isCleanable {
                HatchingPattern()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius))
            }

            // Border
            RoundedRectangle(cornerRadius: Theme.tileRadius)
                .stroke(isCleanable ? Theme.cleanableBorder : borderColor, lineWidth: isCleanable ? 1.5 : 1)

            // Content
            VStack(alignment: .leading, spacing: 0) {
                // Header with name and size
                if w > 50 && h > 20 {
                    HStack(alignment: .top) {
                        Text(node.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        let sizeText = formatSize(node)
                        Text(sizeText)
                            .font(Theme.monoFont(size: 11))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                }

                // Inner children
                if node.isDirectory && !node.children.isEmpty && w > 60 && h > 50 {
                    let innerRect = TMRect(
                        x: 0, y: 0,
                        width: max(0, Double(w) - 12),
                        height: max(0, Double(h) - 26)
                    )
                    InnerTilesView(
                        node: node,
                        rect: innerRect,
                        isCleanupMode: isCleanupMode,
                        isParentCleanable: isCleanable
                    )
                    .environmentObject(model)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                } else if w > 50 && h > 40 {
                    // Leaf tile - show size big at bottom
                    Spacer()
                    let parts = ByteFormatter.parts(node.totalAllocatedSize)
                    let sizeFont = tileSizeFont(width: w, height: h)
                    Text("\(node.approximate ? "~" : "")\(parts.value) \(parts.unit)")
                        .font(Theme.monoFont(size: sizeFont, weight: .semibold))
                        .foregroundColor(Theme.textPrimary.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(width: w, height: h)
        .offset(x: CGFloat(rect.x), y: CGFloat(rect.y))
        .opacity(shouldDim ? 0.35 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isDirectory && !node.children.isEmpty {
                model.navigateTo(node: node)
            }
        }
        .onHover { hovering in
            if !isSnapshot {
                isHovered = hovering
            }
        }
    }

    private func formatSize(_ node: FileNode) -> String {
        let prefix = node.approximate ? "~" : ""
        return prefix + ByteFormatter.format(node.totalAllocatedSize)
    }

    private func tileSizeFont(width: CGFloat, height: CGFloat) -> CGFloat {
        let area = width * height
        if area > 30000 { return 18 }
        if area > 15000 { return 16 }
        if area > 8000 { return 14 }
        return 13
    }
}

// MARK: - Inner tiles (children within a top-level tile)

struct InnerTilesView: View {
    let node: FileNode
    let rect: TMRect
    let isCleanupMode: Bool
    let isParentCleanable: Bool
    @EnvironmentObject var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let innerRect = TMRect(x: 0, y: 0, width: Double(geo.size.width), height: Double(geo.size.height))
            let items = TreemapLayout.layoutChildren(of: node, in: innerRect, minFraction: 0.02)

            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    if let childNode = item.node {
                        InnerTile(
                            node: childNode,
                            rect: insetRect(item.rect, by: 1.5),
                            parentCategory: node.category,
                            isCleanupMode: isCleanupMode,
                            isParentCleanable: isParentCleanable
                        )
                        .environmentObject(model)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func insetRect(_ r: TMRect, by amount: Double) -> TMRect {
        TMRect(
            x: r.x + amount,
            y: r.y + amount,
            width: max(0, r.width - amount * 2),
            height: max(0, r.height - amount * 2)
        )
    }
}

struct InnerTile: View {
    let node: FileNode
    let rect: TMRect
    let parentCategory: NodeCategory
    let isCleanupMode: Bool
    let isParentCleanable: Bool
    @EnvironmentObject var model: AppModel

    private var isCleanable: Bool {
        model.isCleanable(node: node)
    }

    var body: some View {
        let w = CGFloat(rect.width)
        let h = CGFloat(rect.height)

        ZStack(alignment: .topLeading) {
            // Background
            RoundedRectangle(cornerRadius: 4)
                .fill(innerFill)

            // Hatching
            if isCleanable || isParentCleanable {
                HatchingPattern()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Border
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    (isCleanable || isParentCleanable) ? Theme.cleanableBorder.opacity(0.5) : Theme.tileBorder(for: node.category).opacity(0.6),
                    lineWidth: 0.5
                )

            // Content
            VStack(alignment: .leading, spacing: 0) {
                // Name at top
                if w > 40 && h > 18 {
                    Text(node.name)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundColor(Theme.textPrimary.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, 4)
                        .padding(.top, 3)
                }

                Spacer(minLength: 0)

                // Size at bottom
                if w > 45 && h > 35 {
                    let parts = ByteFormatter.parts(node.totalAllocatedSize)
                    let sizeFont = innerSizeFont(width: w, height: h)
                    Text("\(node.approximate ? "~" : "")\(parts.value) \(parts.unit)")
                        .font(Theme.monoFont(size: sizeFont, weight: .semibold))
                        .foregroundColor(Theme.textPrimary.opacity(0.55))
                        .padding(.leading, 4)
                        .padding(.bottom, 4)
                }
            }
        }
        .frame(width: w, height: h)
        .offset(x: CGFloat(rect.x), y: CGFloat(rect.y))
        .opacity(isCleanupMode && !isCleanable && !isParentCleanable ? 0.35 : 1.0)
    }

    private var innerFill: Color {
        if isCleanupMode && (isCleanable || isParentCleanable) {
            return Theme.cleanupFill.opacity(0.7)
        }
        return Theme.innerTileFill(for: node.category)
    }

    private func innerSizeFont(width: CGFloat, height: CGFloat) -> CGFloat {
        let area = width * height
        if area > 20000 { return 18 }
        if area > 10000 { return 16 }
        if area > 5000 { return 14 }
        return 13
    }
}

// MARK: - Diagonal hatching pattern

struct HatchingPattern: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 6
            let lineWidth: CGFloat = 1
            let color = Color(red: 0.204, green: 0.659, blue: 0.325).opacity(0.35)

            let maxDim = size.width + size.height

            var x: CGFloat = -size.height
            while x < maxDim {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(color), lineWidth: lineWidth)
                x += spacing
            }
        }
    }
}
