// DiskCleanerApp.swift – Main app entry point
import SwiftUI
import DiskCleanerCore

#if canImport(AppKit)
import AppKit
#endif

@main
struct DiskCleanerApp: App {
    #if canImport(AppKit)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @StateObject private var model = AppModel()

    init() {
        // Handle --snapshot mode before UI loads
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--snapshot"), idx + 1 < args.count {
            SnapshotRenderer.isActive = true
            handleSnapshot(outputDir: args[idx + 1], real: false)
        } else if let idx = args.firstIndex(of: "--snapshot-real"), idx + 1 < args.count {
            SnapshotRenderer.isActive = true
            handleSnapshot(outputDir: args[idx + 1], real: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 720)
                .onAppear {
                    if SnapshotRenderer.isActive { return }
                    if shouldLoadDemo() {
                        model.loadDemo()
                    } else if model.rootNode == nil && !model.isScanning {
                        Task {
                            await model.startScan()
                        }
                    }
                }
        }
        .defaultSize(width: 1280, height: 860)
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Save Script…") {
                    model.saveScriptWithPanel()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Button("Supprimer la sélection (mettre à la Corbeille)…") {
                    model.requestTrashSelection()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!model.canTrashSelection)
                Button("Vider la sélection de l’explorateur") { model.clearExplorerSelection() }
                    .disabled(model.explorerSelection.isEmpty)
            }
        }
    }

    private func shouldLoadDemo() -> Bool {
        let args = CommandLine.arguments
        if args.contains("--demo") { return true }
        if ProcessInfo.processInfo.environment["DISK_CLEANER_DEMO"] == "1" { return true }
        return false
    }

    private func handleSnapshot(outputDir: String, real: Bool) {
        Task { @MainActor in
            let renderer = SnapshotRenderer()
            let paths = real ? await renderer.renderRealScan(to: outputDir) : renderer.render(to: outputDir)
            if paths.isEmpty {
                fputs("Error: No snapshots rendered\n", stderr)
                exit(1)
            }
            for path in paths {
                print(path)
            }
            exit(0)
        }
    }

}

#if canImport(AppKit)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
