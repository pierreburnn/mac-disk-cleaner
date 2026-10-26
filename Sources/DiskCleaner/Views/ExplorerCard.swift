// ExplorerCard.swift – Explorer panel with treemap
import SwiftUI
import DiskCleanerCore

struct ExplorerCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.isSnapshot) var isSnapshot: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Explorer")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text("Your home folder, sized by space used. Click to select, double-click to open.")
                        .font(.system(size: 12.5))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if !model.isDemo && !isSnapshot {
                    RescanButton()
                }
                SegmentedControl(selection: $model.displayMode)
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, 12)

            Rectangle().fill(Theme.divider).frame(height: 1)

            BreadcrumbRow()
                .padding(.horizontal, 18)
                .frame(height: 38)

            Group {
                if model.isScanning {
                    scanningOverlay()
                } else if let node = model.currentNode {
                    TreemapView(node: node)
                } else {
                    Text("No data")
                        .foregroundColor(Theme.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                LegendRow()
                TrashButton()
            }
            .padding(.leading, 18)
            .padding(.trailing, 15)
            .frame(height: 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func scanningOverlay() -> some View {
        VStack(spacing: 8) {
            Spacer()
            if !isSnapshot {
                ProgressView().progressViewStyle(.linear).frame(width: 220)
            }
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
                let isSelected = selection == mode
                Text(mode.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: 70, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? Theme.segmentSelected : Color.clear)
                            .shadow(color: .black.opacity(isSelected ? 0.12 : 0), radius: 1.5, y: 0.5)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selection = mode }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.segmentTrack))
    }
}

struct RescanButton: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
            Text("Rescan").font(.system(size: 12))
        }
        .foregroundColor(model.isScanning ? Theme.textTertiary : Theme.textSecondary)
        .frame(height: 30)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !model.isScanning else { return }
            Task { await model.startScan() }
        }
        .help("Scan the home folder again")
    }
}

// MARK: - Breadcrumb

struct BreadcrumbRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            Text("~ Home")
                .font(.system(size: 12))
                .foregroundColor(model.breadcrumb.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                .onTapGesture { model.navigateToRoot() }
            ForEach(Array(model.breadcrumb.enumerated()), id: \.offset) { index, node in
                Text("  ›  ")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
                Text(node.name)
                    .font(.system(size: 12))
                    .foregroundColor(index == model.breadcrumb.count - 1 ? Theme.textSecondary : Theme.textPrimary)
                    .onTapGesture { model.navigateToBreadcrumb(at: index) }
            }
            Spacer(minLength: 16)
            if model.tileSelection != nil {
                SelectionInfo()
            } else if let message = model.lastTrashedMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.cleanableBorder)
                    .lineLimit(1)
            } else if let node = model.currentNode {
                Text(ByteFormatter.format(node.totalAllocatedSize))
                    .font(Theme.monoFont(size: 11.5))
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }
}

// MARK: - Legend

struct LegendRow: View {
    var body: some View {
        HStack(spacing: 18) {
            ForEach(NodeCategory.allCases, id: \.self) { cat in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.legendColor(for: cat))
                        .frame(width: 8, height: 8)
                    Text(cat.displayName)
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
