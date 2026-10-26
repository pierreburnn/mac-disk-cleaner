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
                model.toggleTile(pick)
                print("Real selection: \(pick.url.path) – enabled: \(model.canTrashSelection)")
                if let p = renderSnapshot(model: model, filename: "explorer-real-selected.png", outputDir: outputDir) { paths.append(p) }
                model.clearExplorerSelection()
            }
        }

        if ProcessInfo.processInfo.environment["DISK_CLEANER_TRASH_SELFTEST"] == "1" {
            guard await trashSelfTest(model: model) else { return [] }
        }
        return paths
    }

    /// End-to-end check of the real Trash flow on the CI runner: selects the
    /// two throw-away folders ~/DiskCleanerTrashSelfTest and ~/DiskCleanerTrashSelfTest2
    /// and the protected ~/Documents folder, verifies refusal and trashing.
    private func trashSelfTest(model: AppModel) async -> Bool {
        guard let root = model.rootNode else {
            fputs("Trash self-test: FAILED root node is nil\n", stderr)
            return false
        }
        guard let node1 = root.children.first(where: { $0.name == "DiskCleanerTrashSelfTest" }) else {
            fputs("Trash self-test: FAILED DiskCleanerTrashSelfTest not found in scan\n", stderr)
            return false
        }
        guard let node2 = root.children.first(where: { $0.name == "DiskCleanerTrashSelfTest2" }) else {
            fputs("Trash self-test: FAILED DiskCleanerTrashSelfTest2 not found in scan\n", stderr)
            return false
        }
        guard let docsNode = root.children.first(where: { $0.name == "Documents" }) else {
            fputs("Trash self-test: FAILED Documents folder not found in scan\n", stderr)
            return false
        }

        let before = root.totalAllocatedSize
        let size1 = node1.totalAllocatedSize
        let size2 = node2.totalAllocatedSize

        model.clearExplorerSelection()
        model.toggleTile(node1)
        model.toggleTile(node2)
        model.toggleTile(docsNode)
        model.selectedRecommendationIDs = []

        guard model.canTrashSelection else {
            fputs("Trash self-test: FAILED button disabled: \(model.trashDisabledReason ?? "unknown")\n", stderr)
            return false
        }

        model.requestTrashSelection()
        guard let pending = model.pendingPlan else {
            fputs("Trash self-test: FAILED pendingPlan is nil\n", stderr)
            return false
        }

        let targetPaths = Set(pending.plan.targets.map(\.path))
        guard pending.plan.targets.count == 2,
              targetPaths.contains(node1.url.path),
              targetPaths.contains(node2.url.path) else {
            fputs("Trash self-test: FAILED unexpected targets: \(pending.plan.targets.map(\.path))\n", stderr)
            return false
        }

        guard pending.plan.refused.contains(where: { $0.path == docsNode.url.path }) else {
            fputs("Trash self-test: FAILED Documents path not in refused\n", stderr)
            return false
        }

        model.confirmTrash()

        let gone1 = !FileManager.default.fileExists(atPath: node1.url.path)
        let gone2 = !FileManager.default.fileExists(atPath: node2.url.path)
        guard gone1 && gone2 else {
            fputs("Trash self-test: FAILED folders still exist on disk (gone1=\(gone1), gone2=\(gone2))\n", stderr)
            return false
        }

        let removed1 = !root.children.contains(where: { $0 === node1 || $0.id == node1.id })
        let removed2 = !root.children.contains(where: { $0 === node2 || $0.id == node2.id })
        guard removed1 && removed2 else {
            fputs("Trash self-test: FAILED folders still in tree (removed1=\(removed1), removed2=\(removed2))\n", stderr)
            return false
        }

        let docsOnDisk = FileManager.default.fileExists(atPath: docsNode.url.path)
        let docsInTree = root.children.contains(where: { $0 === docsNode || $0.id == docsNode.id })
        guard docsOnDisk && docsInTree else {
            fputs("Trash self-test: FAILED Documents was removed (docsOnDisk=\(docsOnDisk), docsInTree=\(docsInTree))\n", stderr)
            return false
        }

        let after = root.totalAllocatedSize
        let expectedDecrease = size1 + size2
        guard after == before - expectedDecrease else {
            fputs("Trash self-test: FAILED root total size mismatch: before=\(before) after=\(after) expected decrease=\(expectedDecrease)\n", stderr)
            return false
        }

        guard let report = model.trashReport else {
            fputs("Trash self-test: FAILED trashReport is nil\n", stderr)
            return false
        }

        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let inTrash = ((try? FileManager.default.contentsOfDirectory(atPath: trash.path)) ?? [])
            .contains { $0.hasPrefix("DiskCleanerTrashSelfTest") }

        print("Trash self-test: gone1=\(gone1) gone2=\(gone2) removed1=\(removed1) removed2=\(removed2) docsKept=\(docsOnDisk) inTrash=\(inTrash) total \(before) -> \(after) (decreased by \(expectedDecrease)) report=\"\(report.title)\"")

        // Wait for the recommendation refresh to land.
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        print("Trash self-test: OK")
        return true
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
            model.zoomRequest = nil  // clear zoom request from navigateTo
            if let path = renderSnapshot(model: model, filename: "explorer-desktop.png", outputDir: outputDir) {
                paths.append(path)
            }
            model.navigateToRoot()
            model.zoomRequest = nil
        }

        // Zoom animation snapshot: show the overlay mid-zoom into Desktop
        model.displayMode = .category
        if let root = model.rootNode,
           let desktop = root.children.first(where: { $0.name == "Desktop" }) {
            // Compute the treemap size deterministically; fall back to a
            // hard-coded estimate if lastTreemapSize was not populated by
            // a prior render pass (ImageRenderer may not run onAppear).
            let treemapSize: CGSize
            if model.lastTreemapSize.width > 1 {
                treemapSize = model.lastTreemapSize
            } else {
                treemapSize = CGSize(width: 768, height: 498)
            }
            // Find the Desktop tile rect in the root layout.
            let rootItems = TreemapGeometry.items(for: root, in: treemapSize)
            let desktopRect = rootItems.first(where: { $0.node === desktop })?.rect ?? CGRect(origin: .zero, size: treemapSize)

            model.navigateTo(node: desktop)
            model.zoomRequest = nil  // don't trigger live animation
            model.snapshotZoom = (
                request: ZoomRequest(direction: .zoomIn, rect: desktopRect, node: desktop),
                progress: 0.55
            )
            if let path = renderSnapshot(model: model, filename: "explorer-zoom.png", outputDir: outputDir) {
                paths.append(path)
            }
            model.snapshotZoom = nil
            model.navigateToRoot()
            model.zoomRequest = nil
        }

        // Selection + "Supprimer" (demo: the button is shown as for a real item;
        // nothing can actually be deleted in demo mode).
        model.previewTrashEnabled = true
        if let root = model.rootNode {
            var selectedTiles: [FileNode] = []
            if let desktop = root.children.first(where: { $0.name == "Desktop" }) {
                if let target1 = desktop.children.first(where: { $0.name == "old-saas" }) {
                    selectedTiles.append(target1)
                }
                if let target2 = desktop.children.first(where: { $0.name == "dotfiles" }) {
                    selectedTiles.append(target2)
                }
            }
            if let downloads = root.children.first(where: { $0.name == "Downloads" }) {
                if let target3 = downloads.children.first(where: { $0.name == "installer.dmg" }) {
                    selectedTiles.append(target3)
                }
            }
            for tile in selectedTiles {
                model.toggleTile(tile)
            }
            if let path = renderSnapshot(model: model, filename: "explorer-selected.png", outputDir: outputDir) {
                paths.append(path)
            }
            model.requestTrashSelection()
            if model.pendingPlan == nil {
                model.pendingPlan = PendingTrash(entries: model.selectionEntries, plan: model.selectionPlan)
            }
            if let path = renderSnapshot(model: model, filename: "explorer-confirm.png", outputDir: outputDir) {
                paths.append(path)
            }
            model.cancelTrash()
            model.clearExplorerSelection()
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
