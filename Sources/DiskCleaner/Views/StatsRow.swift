// StatsRow.swift – Top stats bar with 4 cells
import SwiftUI
import DiskCleanerCore

struct StatsRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            // Free after cleanup
            statCell(
                label: "Free after cleanup",
                dotColor: nil,
                value: model.rootNode != nil ? ByteFormatter.parts(model.freeAfterCleanup).value : "—",
                unit: model.rootNode != nil ? ByteFormatter.parts(model.freeAfterCleanup).unit : "",
                trailing: model.selectedBytes > 0 ? ByteFormatter.formatSigned(model.selectedBytes) : nil,
                trailingColor: Theme.safeGreen
            )

            cellDivider()

            // Safe to remove
            statCell(
                label: "Safe to remove",
                dotColor: Theme.safeGreen,
                value: model.rootNode != nil ? ByteFormatter.parts(model.safeTotal).value : "—",
                unit: model.rootNode != nil ? ByteFormatter.parts(model.safeTotal).unit : "",
                trailing: model.rootNode != nil ? "\(model.safeRecommendations.count) items" : nil,
                trailingColor: Theme.textSecondary
            )

            cellDivider()

            // Needs review
            statCell(
                label: "Needs review",
                dotColor: Theme.reviewOrange,
                value: model.rootNode != nil ? ByteFormatter.parts(model.reviewTotal).value : "—",
                unit: model.rootNode != nil ? ByteFormatter.parts(model.reviewTotal).unit : "",
                trailing: model.rootNode != nil ? "\(model.reviewRecommendations.count) items" : nil,
                trailingColor: Theme.textSecondary
            )

            cellDivider()

            // Not scanned
            statCell(
                label: "Not scanned",
                dotColor: nil,
                value: model.rootNode != nil ? ByteFormatter.parts(model.notScanned).value : "—",
                unit: model.rootNode != nil ? ByteFormatter.parts(model.notScanned).unit : "",
                trailing: "system & apps",
                trailingColor: Theme.textSecondary
            )
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statCell(
        label: String,
        dotColor: Color?,
        value: String,
        unit: String,
        trailing: String?,
        trailingColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let dot = dotColor {
                    Circle()
                        .fill(dot)
                        .frame(width: 7, height: 7)
                }
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(Theme.monoFont(size: 22, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                Text(unit)
                    .font(Theme.monoFont(size: 14, weight: .medium))
                    .foregroundColor(Theme.textSecondary)

                if let trail = trailing {
                    Text(trail)
                        .font(Theme.monoFont(size: 12))
                        .foregroundColor(trailingColor)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cellDivider() -> some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(width: 1)
            .padding(.vertical, 8)
    }
}
