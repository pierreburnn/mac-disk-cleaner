// Snapshot.swift – ImageRenderer-based PNG export for screenshots
import SwiftUI
import DiskCleanerCore

#if canImport(AppKit)
import AppKit
#endif

/// Renders demo screenshots as PNG files.
@MainActor
public struct SnapshotRenderer {

    public init() {}

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

        return paths
    }

    @available(macOS 13.0, *)
    private func renderSnapshot(model: AppModel, filename: String, outputDir: String) -> String? {
        let view = ContentView()
            .environmentObject(model)
            .environment(\.isSnapshot, true)
            .environment(\.colorScheme, .light)
            .frame(width: 1280, height: 820)

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
