// RecommendationsPanel.swift – Right panel with cleanup recommendations
import SwiftUI
import DiskCleanerCore

struct RecommendationsPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.isSnapshot) var isSnapshot: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text("Recommendations")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text("Select items to build a cleanup script")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            // Recommendation list
            if isSnapshot {
                // VStack for snapshot rendering (ImageRenderer can't do ScrollView)
                VStack(spacing: 0) {
                    recommendationContent()
                }
                .clipped()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        recommendationContent()
                    }
                }
            }

            // Footer
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            footerView()
        }
        .frame(width: 330)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func recommendationContent() -> some View {
        // Safe group
        if !model.safeRecommendations.isEmpty {
            groupHeader(
                label: "Safe to remove",
                badgeBg: Theme.safeBadgeBg,
                badgeText: Theme.safeBadgeText,
                total: model.safeTotal
            )
            ForEach(model.safeRecommendations) { rec in
                RecommendationRow(recommendation: rec)
                    .environmentObject(model)
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)
                    .padding(.leading, 44)
            }
        }

        // Review group
        if !model.reviewRecommendations.isEmpty {
            groupHeader(
                label: "Review first",
                badgeBg: Theme.reviewBadgeBg,
                badgeText: Theme.reviewBadgeText,
                total: model.reviewTotal
            )
            ForEach(model.reviewRecommendations) { rec in
                RecommendationRow(recommendation: rec)
                    .environmentObject(model)
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)
                    .padding(.leading, 44)
            }
        }
    }

    @ViewBuilder
    private func groupHeader(label: String, badgeBg: Color, badgeText: Color, total: Int64) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(badgeText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(badgeBg)
                )

            Spacer()

            Text(ByteFormatter.format(total))
                .font(Theme.monoFont(size: 12))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func footerView() -> some View {
        VStack(spacing: 8) {
            // Selected summary
            HStack(spacing: 4) {
                let parts = ByteFormatter.parts(model.selectedBytes)
                Text(parts.value)
                    .font(Theme.monoFont(size: 14, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Text(parts.unit)
                    .font(Theme.monoFont(size: 12, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Text("selected · \(model.selectedCount) items")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
            }

            // Buttons
            HStack(spacing: 8) {
                // Select safe button
                Button(action: { model.selectAllSafe() }) {
                    Text("Select safe")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Theme.cardBorder, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)

                // Copy script button
                Button(action: { copyScript() }) {
                    ZStack {
                        Text(model.showCopiedFeedback ? "Copied!" : "Copy script")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.black)
                            )
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func copyScript() {
        #if canImport(AppKit)
        let script = model.generateScript()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(script, forType: .string)
        model.showCopiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            model.showCopiedFeedback = false
        }
        #endif
    }
}

// MARK: - Recommendation Row

struct RecommendationRow: View {
    let recommendation: Recommendation
    @EnvironmentObject var model: AppModel

    private var isSelected: Bool {
        model.selectedRecommendationIDs.contains(recommendation.id)
    }

    private var isExpanded: Bool {
        model.expandedRecommendationIDs.contains(recommendation.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                // Custom checkbox
                CustomCheckbox(isChecked: isSelected) {
                    model.toggleRecommendation(recommendation)
                }
                .padding(.top, 2)

                // Title and path
                VStack(alignment: .leading, spacing: 2) {
                    Text(recommendation.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Text(recommendation.displayPath)
                        .font(Theme.monoFont(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                // Size
                let sizeText: String = {
                    let prefix = recommendation.approximate ? "~" : ""
                    return prefix + ByteFormatter.format(recommendation.bytes)
                }()
                Text(sizeText)
                    .font(Theme.monoFont(size: 13))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)

                // Chevron
                Button(action: { model.toggleExpandRecommendation(recommendation) }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())

            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recommendation.detail)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(recommendation.paths, id: \.self) { path in
                        let displayPath = path.hasPrefix(model.homePath)
                            ? "~" + path.dropFirst(model.homePath.count)
                            : path
                        Text(displayPath)
                            .font(Theme.monoFont(size: 10))
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Custom Checkbox

struct CustomCheckbox: View {
    let isChecked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isChecked ? Color.black : Color.white)
                    .frame(width: 16, height: 16)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isChecked ? Color.clear : Theme.textTertiary, lineWidth: 1)
                    .frame(width: 16, height: 16)
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
