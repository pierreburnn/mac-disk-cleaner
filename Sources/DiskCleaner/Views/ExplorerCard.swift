// ExplorerCard.swift – Explorer panel with treemap
import SwiftUI
import DiskCleanerCore

struct ExplorerCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Explorer")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text("Your home folder, sized by space used. Click a tile to open it.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                SegmentedControl(selection: $model.displayMode)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Divider
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
                .padding(.horizontal, 0)

            // Breadcrumb row
            BreadcrumbRow()
                .environmentObject(model)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

            // Treemap
            if model.isScanning {
                scanningOverlay()
            } else if let node = model.currentNode {
                TreemapView(node: node)
                    .environmentObject(model)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else {
                Spacer()
                Text("No data")
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Spacer()
            }

            // Legend
            LegendRow()
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func scanningOverlay() -> some View {
        VStack(spacing: 8) {
            Spacer()
            if let progress = model.scanProgress {
                Text("Scanning: \(progress.filesScanned) files")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Text(ByteFormatter.format(progress.bytesScanned))
                    .font(Theme.monoFont(size: 13))
                    .foregroundColor(Theme.textSecondary)
                Text(progress.currentPath)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Starting scan…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Segmented Control (custom-drawn)

struct SegmentedControl: View {
    @Binding var selection: DisplayMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DisplayMode.allCases, id: \.self) { mode in
                segmentButton(mode)
            }
        }
        .background(Theme.segmentTrack)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .frame(height: 28)
    }

    @ViewBuilder
    private func segmentButton(_ mode: DisplayMode) -> some View {
        let isSelected = selection == mode
        Text(mode.rawValue)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.segmentSelected)
                            .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                    }
                }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selection = mode
            }
    }
}

// MARK: - Breadcrumb

struct BreadcrumbRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            // Home link
            Button(action: { model.navigateToRoot() }) {
                Text("~ Home")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.plain)

            // Breadcrumb components
            ForEach(Array(model.breadcrumb.enumerated()), id: \.offset) { index, node in
                Text(" › ")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
                Button(action: { model.navigateToBreadcrumb(at: index) }) {
                    Text(node.name)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Total size
            if let node = model.currentNode {
                Text(ByteFormatter.format(node.totalAllocatedSize))
                    .font(Theme.monoFont(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }
}

// MARK: - Legend

struct LegendRow: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(NodeCategory.allCases, id: \.self) { cat in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.legendColor(for: cat))
                        .frame(width: 10, height: 10)
                    Text(cat.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
    }
}
