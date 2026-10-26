// ContentView.swift – Main content layout
import SwiftUI
import DiskCleanerCore
#if canImport(AppKit)
import AppKit
#endif

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.isSnapshot) var isSnapshot: Bool

    var body: some View {
        VStack(spacing: Theme.gap) {
            if model.needsFullDiskAccess && !isSnapshot {
                fullDiskAccessBanner()
            }
            StatsRow()
            HStack(alignment: .top, spacing: Theme.gap + 2) {
                ExplorerCard()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                RecommendationsPanel()
                    .frame(width: 384)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, Theme.padding)
        .padding(.top, Theme.padding)
        .padding(.bottom, Theme.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Text("Rescan")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .onTapGesture { Task { await model.startScan() } }
            FooterButton(title: "Open Full Disk Access settings", filled: true) {
                #if canImport(AppKit)
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
                #endif
            }
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
