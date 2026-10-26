// Snapshot.swift – ImageRenderer-based PNG export for screenshots
import SwiftUI
import DiskCleanerCore

#if canImport(AppKit)
import AppKit
#endif

/// Renders demo screenshots as PNG files.
@MainActor
public struct SnapshotRenderer {

    /// True when the process was launched with --snapshot / --snapshot-real.
    public static var isActive = false

    public init() {}

    /// Scan the real home folder of the current user and render it.
    @available(macOS 13.0, *)
    public func renderRealScan(to outputDir: String) async -> [String] {
        let model = AppModel()
        let start = Date()
        await model.startScan()
        let elapsed = Date().timeIntervalSince(start)
        print(String(format: "Real scan: %@ in %d files, %.1fs, %d recommendations, %d unreadable paths",
                     ByteFormatter.format(model.rootNode?.totalAllocatedSize ?? 0),
                     model.rootNode?.fileCount ?? 0, elapsed,
                     model.recommendations.count, model.deniedPaths.count))
        for rec in model.recommendations {
            print("  [\(rec.safety.rawValue)] \(rec.title) – \(ByteFormatter.format(rec.bytes)) – \(rec.displayPath)")
        }
        model.displayMode = .category
        var paths: [String] = []
        if let p = renderSnapshot(model: model, filename: "explorer-real.png", outputDir: outputDir) { paths.append(p) }
        model.displayMode = .cleanup
        if let p = renderSnapshot(model: model, filename: "explorer-real-cleanup.png", outputDir: outputDir) { paths.append(p) }

        // A real, deletable selection: the button is genuinely enabled here.
        model.displayMode = .category
        if let root = model.rootNode {
            let candidates = root.children.flatMap { top -> [FileNode] in
                model.deletionPolicy.refusal(forPath: top.url.path) == nil ? [top] : top.children
            }.filter { model.deletionPolicy.refusal(forPath: $0.url.path) == nil && $0.totalAllocatedSize > 0 }
            if let pick = candidates.max(by: { $0.totalAllocatedSize < $1.totalAllocatedSize }) {
                model.select(.node(pick))
                print("Real selection: \(pick.url.path) – enabled: \(model.canTrashSelection)")
                if let p = renderSnapshot(model: model, filename: "explorer-real-selected.png", outputDir: outputDir) { paths.append(p) }
                model.select(nil)
            }
        }

        if ProcessInfo.processInfo.environment["DISK_CLEANER_TRASH_SELFTEST"] == "1" {
            guard await trashSelfTest(model: model) else { return [] }
        }
        return paths
    }

    /// End-to-end check of the real Trash flow on the CI runner: selects the
    /// throw-away folder ~/DiskCleanerTrashSelfTest (created by CI), confirms,
    /// and verifies it moved to the Trash and the tree was updated.
    private func trashSelfTest(model: AppModel) async -> Bool {
        guard let root = model.rootNode,
              let node = root.children.first(where: { $0.name == "DiskCleanerTrashSelfTest" }) else {
            fputs("Trash self-test: folder not found in scan\n", stderr); return false
        }
        let before = root.totalAllocatedSize
        let size = node.totalAllocatedSize
        model.select(.node(node))
        guard model.canTrashSelection else { fputs("Trash self-test: button disabled\n", stderr); return false }
        model.requestTrashSelection()
        guard model.pendingTrash === node else { fputs("Trash self-test: no confirmation\n", stderr); return false }
        model.confirmTrash()
        if let err = model.trashErrorMessage { fputs("Trash self-test: error \(err)\n", stderr); return false }
        let gone = !FileManager.default.fileExists(atPath: node.url.path)
        let removed = !root.children.contains { $0 === node }
        let after = root.totalAllocatedSize
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let inTrash = ((try? FileManager.default.contentsOfDirectory(atPath: trash.path)) ?? [])
            .contains { $0.hasPrefix("DiskCleanerTrashSelfTest") }
        print("Trash self-test: gone=\(gone) removedFromTree=\(removed) inTrash=\(inTrash) total \(before) -> \(after) (item \(size))")
        // Wait for the recommendation refresh to land.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        return gone && removed && after == before - size
    }

    /// Render demo screenshots to the specified output directory.
    /// - Parameter outputDir: Directory to write PNG files to.
    /// - Returns: Array of file paths written.
    @available(macOS 13.0, *)
    public func render(to outputDir: String) -> [String] {
        let model = AppModel()
        model.loadDemo()

        var paths: [String] = []

        // Category mode
        model.displayMode = .category
        if let path = renderSnapshot(model: model, filename: "explorer-category.png", outputDir: outputDir) {
            paths.append(path)
        }

        // Cleanup mode
        model.displayMode = .cleanup
        if let path = renderSnapshot(model: model, filename: "explorer-cleanup.png", outputDir: outputDir) {
            paths.append(path)
        }

        // Drill-down: click on "Desktop"
        model.displayMode = .category
        if let desktop = model.rootNode?.children.first(where: { $0.name == "Desktop" }) {
            model.navigateTo(node: desktop)
            if let path = renderSnapshot(model: model, filename: "explorer-desktop.png", outputDir: outputDir) {
                paths.append(path)
            }
            model.navigateToRoot()
        }

        // Selection + "Supprimer" (demo: the button is shown as for a real item;
        // nothing can actually be deleted in demo mode).
        model.previewTrashEnabled = true
        if let desktop = model.rootNode?.children.first(where: { $0.name == "Desktop" }),
           let target = desktop.children.first(where: { $0.name == "old-saas" }) {
            model.select(.node(target))
            if let path = renderSnapshot(model: model, filename: "explorer-selected.png", outputDir: outputDir) {
                paths.append(path)
            }
            model.pendingTrash = target
            if let path = renderSnapshot(model: model, filename: "explorer-confirm.png", outputDir: outputDir) {
                paths.append(path)
            }
            model.pendingTrash = nil
            model.select(nil)
        }
        model.previewTrashEnabled = false

        return paths
    }

    @available(macOS 13.0, *)
    private func renderSnapshot(model: AppModel, filename: String, outputDir: String) -> String? {
        let view = ContentView()
            .environmentObject(model)
            .environment(\.isSnapshot, true)
            .environment(\.colorScheme, .light)
            .frame(width: Theme.windowWidth, height: Theme.windowHeight)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0

        #if canImport(AppKit)
        guard let cgImage = renderer.cgImage else {
            fputs("Error: Failed to render \(filename)\n", stderr)
            return nil
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            fputs("Error: Failed to create PNG data for \(filename)\n", stderr)
            return nil
        }

        let fm = FileManager.default
        try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        let outputPath = (outputDir as NSString).appendingPathComponent(filename)
        do {
            try pngData.write(to: URL(fileURLWithPath: outputPath))
            return outputPath
        } catch {
            fputs("Error: Failed to write \(outputPath): \(error)\n", stderr)
            return nil
        }
        #else
        return nil
        #endif
    }
}
