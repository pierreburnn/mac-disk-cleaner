// ContentView.swift – Main content layout
import SwiftUI
import DiskCleanerCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.isSnapshot) var isSnapshot: Bool

    var body: some View {
        VStack(spacing: Theme.gap) {
            // Full Disk Access banner
            if model.needsFullDiskAccess && !isSnapshot {
                fullDiskAccessBanner()
            }

            // Stats row
            StatsRow()
                .environmentObject(model)

            // Main content: Explorer + Recommendations
            HStack(alignment: .top, spacing: Theme.gap) {
                ExplorerCard()
                    .environmentObject(model)
                    .environment(\.isSnapshot, isSnapshot)

                RecommendationsPanel()
                    .environmentObject(model)
                    .environment(\.isSnapshot, isSnapshot)
            }
        }
        .padding(Theme.padding)
        .background(Theme.background)
    }

    @ViewBuilder
    private func fullDiskAccessBanner() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14))
            Text("Some folders could not be read. Grant Full Disk Access for a complete scan.")
                .font(.system(size: 12))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Button("Open Settings") {
                #if canImport(AppKit)
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
                #endif
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.blue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.yellow.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
