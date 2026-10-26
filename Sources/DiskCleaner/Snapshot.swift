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
        return paths
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
