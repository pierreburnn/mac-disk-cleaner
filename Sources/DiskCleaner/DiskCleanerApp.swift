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
        if let snapshotIdx = args.firstIndex(of: "--snapshot"),
           snapshotIdx + 1 < args.count {
            let outputDir = args[snapshotIdx + 1]
            handleSnapshot(outputDir: outputDir)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 720)
                .onAppear {
                    if shouldLoadDemo() {
                        model.loadDemo()
                    } else if model.rootNode == nil && !model.isScanning {
                        Task {
                            await model.startScan()
                        }
                    }
                }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Save Script…") {
                    saveScript()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }

    private func shouldLoadDemo() -> Bool {
        let args = CommandLine.arguments
        if args.contains("--demo") { return true }
        if ProcessInfo.processInfo.environment["DISK_CLEANER_DEMO"] == "1" { return true }
        return false
    }

    private func handleSnapshot(outputDir: String) {
        Task { @MainActor in
            let renderer = SnapshotRenderer()
            let paths = renderer.render(to: outputDir)
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

    private func saveScript() {
        #if canImport(AppKit)
        let script = model.generateScript()
        let panel = NSSavePanel()
        panel.title = "Save Cleanup Script"
        panel.nameFieldStringValue = "cleanup.sh"
        panel.allowedContentTypes = [.shellScript]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? script.write(to: url, atomically: true, encoding: .utf8)
                // Make executable
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: url.path
                )
            }
        }
        #endif
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
