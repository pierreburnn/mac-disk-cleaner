// StatsRow.swift – Top stats bar with 4 cells
import SwiftUI
import DiskCleanerCore

struct StatsRow: View {
    @EnvironmentObject var model: AppModel

    private var hasData: Bool { model.rootNode != nil }

    var body: some View {
        HStack(spacing: 0) {
            statCell(label: "Free after cleanup", dot: nil,
                     value: hasData ? Self.wholeGB(model.freeAfterCleanup) : "—",
                     trailing: hasData && model.selectedBytes > 0 ? ByteFormatter.formatSigned(model.selectedBytes) : nil,
                     trailingColor: Theme.safeGreen)
            divider
            statCell(label: "Safe to remove", dot: Theme.safeGreen,
                     value: hasData ? ByteFormatter.format(model.safeTotal) : "—",
                     trailing: hasData ? Self.items(model.safeRecommendations.count) : nil,
                     trailingColor: Theme.textSecondary)
            divider
            statCell(label: "Needs review", dot: Theme.reviewOrange,
                     value: hasData ? ByteFormatter.format(model.reviewTotal) : "—",
                     trailing: hasData ? Self.items(model.reviewRecommendations.count) : nil,
                     trailingColor: Theme.textSecondary)
            divider
            statCell(label: "Not scanned", dot: nil,
                     value: hasData ? Self.wholeGB(model.notScanned) : "—",
                     trailing: "system & apps",
                     trailingColor: Theme.textSecondary)
        }
        .frame(height: 76)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    static func items(_ n: Int) -> String { n == 1 ? "1 item" : "\(n) items" }

    /// "92 GB" – whole gigabytes for the headline free/not-scanned figures.
    static func wholeGB(_ bytes: Int64) -> String {
        if abs(bytes) < 10_000_000_000 { return ByteFormatter.format(bytes) }
        return "\(Int((Double(bytes) / 1_000_000_000).rounded())) GB"
    }

    private var divider: some View {
        Rectangle().fill(Theme.divider).frame(width: 1)
    }

    private func statCell(label: String, dot: Color?, value: String,
                          trailing: String?, trailingColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                if let dot {
                    Circle().fill(dot).frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(Theme.monoFont(size: 23, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                if let trailing {
                    Text(trailing)
                        .font(Theme.monoFont(size: 11.5))
                        .foregroundColor(trailingColor)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
