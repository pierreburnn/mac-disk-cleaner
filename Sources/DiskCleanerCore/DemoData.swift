// DemoData.swift – Fake dataset reproducing the reference image
import Foundation

/// Provides demo data matching the reference screenshot.
public struct DemoData: Sendable {

    public static let homePath: String = "/Users/pierre"

    /// Build the demo FileNode tree (sizes reproduce the reference screenshot).
    public static func makeTree() -> FileNode {
        let home = URL(fileURLWithPath: homePath, isDirectory: true)
        let old = Date(timeIntervalSince1970: 1_700_000_000)   // Nov 2023 (idle projects)
        let recent = Date(timeIntervalSince1970: 1_790_000_000)

        func gb(_ n: Double) -> Int64 { Int64((n * 1_000_000_000).rounded()) }

        /// Leaf (file or opaque folder) of `size` GB.
        func f(_ name: String, _ size: Double, _ cat: NodeCategory, path: String? = nil,
               mod: Date? = nil, approx: Bool = false) -> (String) -> FileNode {
            return { parent in
                let url = URL(fileURLWithPath: parent + "/" + (path ?? name))
                return FileNode(name: name, url: url, isDirectory: true, allocatedSize: gb(size),
                                modificationDate: mod ?? recent, category: cat, approximate: approx)
            }
        }
        /// Directory with children.
        func d(_ name: String, _ cat: NodeCategory, path: String? = nil, approx: Bool = false,
               _ kids: [(String) -> FileNode]) -> (String) -> FileNode {
            return { parent in
                let rel = path ?? name
                let p = rel.isEmpty ? parent : parent + "/" + rel
                let url = URL(fileURLWithPath: p, isDirectory: true)
                return FileNode(name: name, url: url, isDirectory: true, allocatedSize: 0,
                                children: kids.map { $0(p) }, modificationDate: recent,
                                category: cat, approximate: approx)
            }
        }

        let cp = NodeCategory.codeProjects
        let pk = NodeCategory.packageCaches
        let dv = NodeCategory.devTools
        let doc = NodeCategory.documents
        let sdk = NodeCategory.sdks
        let ai = NodeCategory.aiModels

        func project(_ name: String, src: Double, next: Double = 0, turbo: Double = 0,
                     nodeModules: Double = 0, worktrees: Double = 0, idle: Bool = false) -> (String) -> FileNode {
            var kids: [(String) -> FileNode] = [f("src", src, cp, mod: idle ? old : recent)]
            if next > 0 { kids.append(f(".next", next, pk)) }
            if turbo > 0 { kids.append(f(".turbo", turbo, pk)) }
            if nodeModules > 0 { kids.append(f("node_modules", nodeModules, pk, mod: idle ? old : recent)) }
            if worktrees > 0 {
                kids.append(d(".claude", cp, [f("worktrees", worktrees, cp, approx: true)]))
            }
            return d(name, cp, kids)
        }

        let tree = d("Home", dv, path: "", [
            d("Desktop", cp, [
                project("atlas", src: 2.4, next: 4.0, turbo: 1.2, worktrees: 9.0),
                project("pebble", src: 4.6, next: 3.0, turbo: 0.6),
                project("side-quest", src: 2.1, next: 1.5, turbo: 0.6),
                project("orbit", src: 1.8, next: 1.4, nodeModules: 1.1, idle: true),
                project("old-saas", src: 0.6, nodeModules: 2.2, idle: true),
                project("sandbox", src: 0.3, nodeModules: 2.2, idle: true),
                project("pixel-lab", src: 0.3, nodeModules: 0.5),
                project("dotfiles", src: 0.7),
                project("notes-app", src: 0.2, nodeModules: 0.4),
                project("cli-tools", src: 0.4),
                project("playground", src: 0.2, nodeModules: 0.2, idle: true),
            ]),
            d("Library", dv, [
                f("Android SDK", 9.9, sdk, path: "Android"),
                f("Xcode DerivedData", 6.5, sdk, path: "Developer/Xcode/DerivedData"),
                f("Containers", 0.25, dv),
                f("Application Support", 0.2, dv),
                f("Caches", 0.15, dv),
                f("Logs", 0.1, dv),
            ]),
            d(".ollama", ai, [
                f("deepseek-coder-v2:16b", 8.3, ai, path: "models/deepseek-coder-v2", approx: true),
                f("llama3.1:8b", 4.6, ai, path: "models/llama3.1", approx: true),
                f("mistral:7b-instruct", 3.8, ai, path: "models/mistral", approx: true),
            ]),
            f(".npm", 13.4, pk),
            d(".android", sdk, [
                f("Emulator images", 7.3, sdk, path: "avd"),
            ]),
            d(".gradle", pk, [
                f("caches", 6.1, pk),
                f("wrapper", 0.5, pk),
            ]),
            d("Documents", doc, [
                f("Invoices", 1.6, doc), f("Design", 1.3, doc), f("Contracts", 1.0, doc),
                f("Scans", 0.7, doc), f("Notes", 0.5, doc), f("Archive", 0.4, doc),
            ]),
            f(".vscode", 4.0, dv),
            f("Other docs", 3.7, dv),
            d("Pictures", doc, [f("Photos Library", 3.2, doc)]),
            d("Downloads", doc, [
                f("installer.dmg", 0.8, doc), f("dataset.zip", 0.5, doc), f("video.mov", 0.4, doc),
                f("slides.key", 0.25, doc), f("photos.zip", 0.2, doc), f("report.pdf", 0.15, doc),
                f("music.zip", 0.1, doc), f("misc", 0.1, doc),
            ]),
            f(".cursor", 1.9, dv),
            d(".cache", pk, [f("uv", 1.6, pk), f("puppeteer", 1.4, pk), f("pre-commit", 0.04, pk)]),
            d("Music", doc, [f("Music Library", 2.2, doc)]),
            f(".docker", 1.6, dv),
            f(".minikube", 1.5, dv),
            f(".rustup", 1.3, dv),
            f("Movies", 1.0, doc),
            f(".bun", 0.5, pk),
            f("Applications", 0.46, dv),
        ])(homePath)

        _ = home
        tree.sortChildrenBySize()
        return tree
    }

    /// Build demo recommendations matching the reference.
    public static func makeRecommendations() -> [Recommendation] {
        func gb(_ n: Double) -> Int64 { Int64(n * 1_000_000_000) }

        let safe: [Recommendation] = [
            Recommendation(
                id: "npm-cache",
                title: "npm cache",
                displayPath: "~/.npm",
                paths: ["\(homePath)/.npm"],
                bytes: gb(13.4),
                safety: .safe,
                detail: "Local npm package cache. Safely cleared; npm re-downloads packages as needed.",
                command: .shell("if command -v npm >/dev/null; then npm cache clean --force; else rm -rf \"$HOME\"/.npm/_cacache; fi", fallbackRemove: true)
            ),
            Recommendation(
                id: "nextjs-turbo",
                title: "Next.js & Turbo build output",
                displayPath: "~/Desktop/*/.next, .turbo",
                paths: [
                    "\(homePath)/Desktop/atlas/.next",
                    "\(homePath)/Desktop/atlas/.turbo",
                    "\(homePath)/Desktop/pebble/.next",
                    "\(homePath)/Desktop/pebble/.turbo",
                    "\(homePath)/Desktop/orbit/.next",
                    "\(homePath)/Desktop/side-quest/.next",
                    "\(homePath)/Desktop/side-quest/.turbo",
                ],
                bytes: gb(12.3),
                safety: .safe,
                detail: "Build output from Next.js and Turborepo. Regenerated automatically on next build.",
                command: .removePaths
            ),
            Recommendation(
                id: "gradle-caches",
                title: "Gradle caches",
                displayPath: "~/.gradle",
                paths: ["\(homePath)/.gradle/caches", "\(homePath)/.gradle/wrapper"],
                bytes: gb(6.6),
                safety: .safe,
                detail: "Gradle build caches and wrapper distributions. Re-downloaded on next build.",
                command: .removePaths
            ),
            Recommendation(
                id: "xcode-deriveddata",
                title: "Xcode DerivedData",
                displayPath: "~/Library/Developer/Xcode",
                paths: ["\(homePath)/Library/Developer/Xcode/DerivedData"],
                bytes: gb(6.4),
                safety: .safe,
                detail: "Xcode build intermediates and indexes. Rebuilt automatically when you next open a project.",
                command: .removePaths
            ),
            Recommendation(
                id: "uv-puppeteer-caches",
                title: "uv & Puppeteer caches",
                displayPath: "~/.cache/uv, ~/.cache/puppeteer",
                paths: ["\(homePath)/.cache/uv", "\(homePath)/.cache/puppeteer"],
                bytes: gb(3.0),
                safety: .safe,
                detail: "Cached downloads for uv (Python) and Puppeteer (Chromium). Re-downloaded when needed.",
                command: .shell("if command -v uv >/dev/null; then uv cache clean; else rm -rf \"$HOME\"/.cache/uv; fi\nrm -rf \"$HOME\"/.cache/puppeteer", fallbackRemove: true)
            ),
        ]

        let review: [Recommendation] = [
            Recommendation(
                id: "android-sdk",
                title: "Android SDK & emulators",
                displayPath: "~/Library/Android, ~/.android",
                paths: ["\(homePath)/Library/Android", "\(homePath)/.android"],
                bytes: gb(17.2),
                safety: .review,
                detail: "Android SDK, AVD images, and emulator data. Remove if you no longer do Android development.",
                command: .removePaths
            ),
            Recommendation(
                id: "ollama-models",
                title: "Ollama models",
                displayPath: "~/.ollama/models",
                paths: ["\(homePath)/.ollama/models"],
                bytes: gb(16.7),
                safety: .review,
                detail: "Downloaded LLM models for Ollama. Use 'ollama rm <model>' to selectively remove models.",
                command: .shell("# Remove individual models with: ollama rm <model-name>\nrm -rf \"$HOME\"/.ollama/models", fallbackRemove: false)
            ),
            Recommendation(
                id: "worktrees-atlas",
                title: "atlas worktrees",
                displayPath: "~/Desktop/atlas/.claude/worktrees",
                paths: ["\(homePath)/Desktop/atlas/.claude/worktrees"],
                bytes: gb(9.0),
                safety: .review,
                detail: "Claude Code worktrees for atlas. Remove if no longer needed; run 'git worktree prune' afterwards.",
                command: .removePaths,
                approximate: true
            ),
            Recommendation(
                id: "idle-node-modules",
                title: "node_modules in idle projects",
                displayPath: "~/…/node_modules",
                paths: [
                    "\(homePath)/Desktop/old-saas/node_modules",
                    "\(homePath)/Desktop/sandbox/node_modules",
                    "\(homePath)/Desktop/orbit/node_modules",
                    "\(homePath)/Desktop/playground/node_modules",
                ],
                bytes: gb(6.6),
                safety: .review,
                detail: "node_modules in projects not modified in the last 30 days. Run 'npm install' to restore.",
                command: .removePaths
            ),
            Recommendation(
                id: "ios-simulators",
                title: "iOS Simulators",
                displayPath: "~/Library/Developer/CoreSimulator",
                paths: ["\(homePath)/Library/Developer/CoreSimulator/Devices"],
                bytes: gb(3.1),
                safety: .review,
                detail: "iOS Simulator device data. Removes all simulator devices; re-created in Xcode as needed.",
                command: .shell("if command -v xcrun >/dev/null; then xcrun simctl delete all; fi", fallbackRemove: false)
            ),
            Recommendation(
                id: "huggingface-cache",
                title: "Hugging Face cache",
                displayPath: "~/.cache/huggingface",
                paths: ["\(homePath)/.cache/huggingface"],
                bytes: gb(2.0),
                safety: .review,
                detail: "Downloaded ML models and datasets from Hugging Face. Re-downloaded on next use.",
                command: .removePaths
            ),
            Recommendation(
                id: "trash",
                title: "Trash",
                displayPath: "~/.Trash",
                paths: ["\(homePath)/.Trash"],
                bytes: gb(1.4),
                safety: .review,
                detail: "Files in the Trash. Permanently deletes all trashed items.",
                command: .shell("find \"$HOME\"/.Trash -mindepth 1 -maxdepth 1 -exec rm -rf {} +", fallbackRemove: false)
            ),
        ]

        return safe + review
    }

    /// Demo selection: npm, nextjs-turbo, gradle, uv-puppeteer (safe), android-sdk (review)
    public static var defaultSelectedIDs: Set<String> {
        return ["npm-cache", "nextjs-turbo", "gradle-caches", "uv-puppeteer-caches", "android-sdk"]
    }

    /// Demo volume info.
    public static func makeVolumeInfo() -> VolumeInfo {
        func gb(_ n: Double) -> Int64 { Int64(n * 1_000_000_000) }
        // free=39.5, total such that notScanned=288
        // notScanned = (total - free) - scanned
        // 288 = (total - 39.5) - 135  →  total = 288 + 135 + 39.5 = 462.5
        return VolumeInfo(totalCapacity: gb(462.5), availableCapacity: gb(39.5))
    }
}
