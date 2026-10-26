// RecommendationsPanel.swift – Right panel with cleanup recommendations
import SwiftUI
import DiskCleanerCore
#if canImport(AppKit)
import AppKit
#endif

struct RecommendationsPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.isSnapshot) var isSnapshot: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Selection")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text("Clicked tiles and ticked recommendations")
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, 10)

            Rectangle().fill(Theme.divider).frame(height: 1)

            // Scrollable list; the footer below stays pinned.
            Group {
                if isSnapshot {
                    // ImageRenderer cannot draw a ScrollView; an overlay keeps the
                    // list from influencing the panel height (it is simply clipped).
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .top) {
                            VStack(spacing: 0) { listContent }
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .clipped()
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: 0) { listContent }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .layoutPriority(-1)

            Rectangle().fill(Theme.divider).frame(height: 1)
            footer
        }
        .frame(maxHeight: .infinity)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    @ViewBuilder
    private var listContent: some View {
        if !model.explorerSelection.isEmpty {
            let items = model.explorerItems
            groupHeader("Selected in explorer", bg: Theme.selectionBadgeBg, fg: Theme.selectionColor,
                        total: SelectionPlanner.plan(entries: items.filter { $0.item.checked }.compactMap { $0.node.map(SelectionEntry.tile) },
                                                     root: model.rootNode, policy: model.deletionPolicy).selectedBytes)
            ForEach(items, id: \.item.path) { pair in
                ExplorerSelectionRow(item: pair.item, node: pair.node)
                Rectangle().fill(Theme.divider).frame(height: 1)
            }
        }
        if model.recommendations.isEmpty && !model.isScanning {
            Text(model.rootNode == nil ? "Waiting for the scan…" : "Nothing worth cleaning was found. 🎉")
                .font(.system(size: 12.5))
                .foregroundColor(Theme.textSecondary)
                .padding(20)
        }
        if !model.safeRecommendations.isEmpty {
            groupHeader("Safe to remove", bg: Theme.safeBadgeBg, fg: Theme.safeBadgeText, total: model.safeTotal)
            ForEach(model.safeRecommendations) { rec in
                RecommendationRow(recommendation: rec)
                Rectangle().fill(Theme.divider).frame(height: 1)
            }
        }
        if !model.reviewRecommendations.isEmpty {
            groupHeader("Review first", bg: Theme.reviewBadgeBg, fg: Theme.reviewBadgeText, total: model.reviewTotal)
            ForEach(model.reviewRecommendations) { rec in
                RecommendationRow(recommendation: rec)
                Rectangle().fill(Theme.divider).frame(height: 1)
            }
        }
    }

    private func groupHeader(_ label: String, bg: Color, fg: Color, total: Int64) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(fg)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(bg))
                Spacer()
                Text(ByteFormatter.format(total))
                    .font(Theme.monoFont(size: 11.5))
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(ByteFormatter.format(model.selectedBytes))
                    .font(Theme.monoFont(size: 13, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Text("selected · \(SelectionPlanner.footerSelectionSummary(itemCount: model.selectedCount, targetCount: model.trashCount))")
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
            }
            HStack(spacing: 8) {
                FooterButton(title: "Select safe", filled: false) { model.selectAllSafe() }
                FooterButton(title: model.showCopiedFeedback ? "Copied ✓" : "Copy script", filled: true) {
                    copyScript()
                }
                .opacity(model.selectedCount == 0 ? 0.5 : 1)
                Spacer()
                if !isSnapshot {
                    Text("Save…")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .onTapGesture { model.saveScriptWithPanel() }
                        .help("Save the cleanup script to a file")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private func copyScript() {
        guard model.selectedCount > 0 else { return }
        #if canImport(AppKit)
        let script = model.generateScript()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(script, forType: .string)
        model.showCopiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { model.showCopiedFeedback = false }
        #endif
    }
}

struct FooterButton: View {
    let title: String
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Text(title)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(filled ? .white : Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(filled ? Color(white: 0.07) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(filled ? Color.clear : Color(white: 0.85), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

// MARK: - Explorer selection row

struct ExplorerSelectionRow: View {
    let item: ExplorerSelection.Item
    let node: FileNode?
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CustomCheckbox(isChecked: item.checked) { model.setTileChecked(item.path, !item.checked) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: (node?.isDirectory ?? true) ? "folder" : "doc")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textSecondary)
                    Text(node?.name ?? (item.path as NSString).lastPathComponent)
                        .font(.system(size: 13.5))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                }
                Text(model.displayPath(item.path))
                    .font(Theme.monoFont(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .contentShape(Rectangle())
            .onTapGesture { model.setTileChecked(item.path, !item.checked) }
            Spacer(minLength: 6)
            Text(node.map { ($0.approximate ? "~" : "") + ByteFormatter.format($0.totalAllocatedSize) } ?? "—")
                .font(Theme.monoFont(size: 13, weight: .medium))
                .foregroundColor(Theme.textPrimary.opacity(item.checked ? 0.85 : 0.45))
                .lineLimit(1)
                .fixedSize()
            Image(systemName: "xmark")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(Color(white: 0.55))
                .frame(width: 18, height: 30)
                .contentShape(Rectangle())
                .onTapGesture { model.removeTile(item.path) }
                .help("Retirer de la sélection")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 60)
    }
}

// MARK: - Recommendation Row

struct RecommendationRow: View {
    let recommendation: Recommendation
    @EnvironmentObject var model: AppModel

    private var isSelected: Bool { model.selectedRecommendationIDs.contains(recommendation.id) }
    private var isExpanded: Bool { model.expandedRecommendationIDs.contains(recommendation.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                CustomCheckbox(isChecked: isSelected) { model.toggleRecommendation(recommendation) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.title)
                        .font(.system(size: 13.5))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Text(recommendation.displayPath)
                        .font(Theme.monoFont(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .contentShape(Rectangle())
                .onTapGesture { model.toggleRecommendation(recommendation) }
                Spacer(minLength: 6)
                Text((recommendation.approximate ? "~" : "") + ByteFormatter.format(recommendation.bytes))
                    .font(Theme.monoFont(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Color(white: 0.62))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 18, height: 30)
                    .contentShape(Rectangle())
                    .onTapGesture { model.toggleExpandRecommendation(recommendation) }
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .frame(height: 60)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recommendation.detail)
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(recommendation.paths, id: \.self) { path in
                        HStack(spacing: 6) {
                            Text(path.hasPrefix(model.homePath) ? "~" + path.dropFirst(model.homePath.count) : path)
                                .font(Theme.monoFont(size: 10.5))
                                .foregroundColor(Theme.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if !model.isDemo {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(Theme.textTertiary)
                                    .onTapGesture { model.revealInFinder(path) }
                                    .help("Reveal in Finder")
                            }
                        }
                    }
                    if case .shell(let cmd, _) = recommendation.command {
                        Text("Uses: \(cmd)")
                            .font(Theme.monoFont(size: 10.5))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(.leading, 44)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
            }
        }
    }
}

// MARK: - Custom Checkbox

struct CustomCheckbox: View {
    let isChecked: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isChecked ? Color(white: 0.07) : Color.white)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(isChecked ? Color.clear : Color(white: 0.82), lineWidth: 1)
            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 16, height: 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}
