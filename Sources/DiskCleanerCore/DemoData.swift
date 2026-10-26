// DemoData.swift – Fake dataset reproducing the reference image
import Foundation

/// Provides demo data matching the reference screenshot.
public struct DemoData: Sendable {

    public static let homePath: String = "/Users/pierre"

    /// Build the demo FileNode tree.
    public static func makeTree() -> FileNode {
        let home = URL(fileURLWithPath: homePath, isDirectory: true)

        func gb(_ n: Double) -> Int64 { Int64(n * 1_000_000_000) }
        func mb(_ n: Double) -> Int64 { Int64(n * 1_000_000) }

        func file(_ name: String, parent: URL, size: Int64, cat: NodeCategory, mod: Date? = nil, approx: Bool = false) -> FileNode {
            let url = parent.appendingPathComponent(name)
            return FileNode(name: name, url: url, isDirectory: false, allocatedSize: size, modificationDate: mod, category: cat, approximate: approx)
        }

        func dir(_ name: String, parent: URL, cat: NodeCategory, children: [FileNode], approx: Bool = false) -> FileNode {
            let url = parent.appendingPathComponent(name)
            let n = FileNode(name: name, url: url, isDirectory: true, allocatedSize: 0, children: children, category: cat, approximate: approx)
            return n
        }

        let oldDate = Date(timeIntervalSince1970: 1700000000) // ~Nov 2023

        // --- Desktop (41.5 GB, codeProjects) ---
        let desktopURL = home.appendingPathComponent("Desktop")

        // atlas (16.6 GB) - with worktrees
        let atlasURL = desktopURL.appendingPathComponent("atlas")
        let atlasWorktrees = dir("worktrees", parent: atlasURL.appendingPathComponent(".claude"), cat: .codeProjects, children: [
            file("wt1", parent: atlasURL.appendingPathComponent(".claude/worktrees"), size: gb(4.5), cat: .codeProjects),
            file("wt2", parent: atlasURL.appendingPathComponent(".claude/worktrees"), size: gb(4.5), cat: .codeProjects),
        ], approx: true)
        let atlasClaude = dir(".claude", parent: atlasURL, cat: .codeProjects, children: [atlasWorktrees])
        let atlasNext = dir(".next", parent: atlasURL, cat: .packageCaches, children: [
            file("cache", parent: atlasURL.appendingPathComponent(".next"), size: gb(3.5), cat: .packageCaches),
        ])
        let atlasTurbo = dir(".turbo", parent: atlasURL, cat: .packageCaches, children: [
            file("cache", parent: atlasURL.appendingPathComponent(".turbo"), size: gb(1.0), cat: .packageCaches),
        ])
        let atlasNodeModules = dir("node_modules", parent: atlasURL, cat: .packageCaches, children: [
            file("deps", parent: atlasURL.appendingPathComponent("node_modules"), size: gb(1.5), cat: .packageCaches),
        ])
        let atlasSrc = file("src", parent: atlasURL, size: gb(1.1), cat: .codeProjects)
        let atlas = dir("atlas", parent: desktopURL, cat: .codeProjects, children: [
            atlasClaude, atlasNext, atlasTurbo, atlasNodeModules, atlasSrc,
            file("package.json", parent: atlasURL, size: mb(1), cat: .codeProjects),
        ])

        // pebble (8.2 GB)
        let pebbleURL = desktopURL.appendingPathComponent("pebble")
        let pebbleNext = dir(".next", parent: pebbleURL, cat: .packageCaches, children: [
            file("cache", parent: pebbleURL.appendingPathComponent(".next"), size: gb(2.3), cat: .packageCaches),
        ])
        let pebbleTurbo = dir(".turbo", parent: pebbleURL, cat: .packageCaches, children: [
            file("cache", parent: pebbleURL.appendingPathComponent(".turbo"), size: gb(0.7), cat: .packageCaches),
        ])
        let pebbleNM = dir("node_modules", parent: pebbleURL, cat: .packageCaches, children: [
            file("deps", parent: pebbleURL.appendingPathComponent("node_modules"), size: gb(1.5), cat: .packageCaches),
        ])
        let pebble = dir("pebble", parent: desktopURL, cat: .codeProjects, children: [
            pebbleNext, pebbleTurbo, pebbleNM,
            file("src", parent: pebbleURL, size: gb(3.7), cat: .codeProjects),
            file("package.json", parent: pebbleURL, size: mb(1), cat: .codeProjects),
        ])

        // orbit (~3.2 GB)
        let orbitURL = desktopURL.appendingPathComponent("orbit")
        let orbitNext = dir(".next", parent: orbitURL, cat: .packageCaches, children: [
            file("cache", parent: orbitURL.appendingPathComponent(".next"), size: gb(1.2), cat: .packageCaches),
        ])
        let orbit = dir("orbit", parent: desktopURL, cat: .codeProjects, children: [
            orbitNext,
            file("src", parent: orbitURL, size: gb(2.0), cat: .codeProjects),
            file("package.json", parent: orbitURL, size: mb(1), cat: .codeProjects),
        ])

        // side-quest (4.2 GB)
        let sqURL = desktopURL.appendingPathComponent("side-quest")
        let sqNext = dir(".next", parent: sqURL, cat: .packageCaches, children: [
            file("cache", parent: sqURL.appendingPathComponent(".next"), size: gb(1.5), cat: .packageCaches),
        ])
        let sqTurbo = dir(".turbo", parent: sqURL, cat: .packageCaches, children: [
            file("cache", parent: sqURL.appendingPathComponent(".turbo"), size: gb(0.5), cat: .packageCaches),
        ])
        let sq = dir("side-quest", parent: desktopURL, cat: .codeProjects, children: [
            sqNext, sqTurbo,
            file("src", parent: sqURL, size: gb(2.2), cat: .codeProjects),
            file("package.json", parent: sqURL, size: mb(1), cat: .codeProjects),
        ])

        // old-saas (2.8 GB) - idle project with node_modules
        let oldSaasURL = desktopURL.appendingPathComponent("old-saas")
        let oldSaasNM = dir("node_modules", parent: oldSaasURL, cat: .packageCaches, children: [
            file("deps", parent: oldSaasURL.appendingPathComponent("node_modules"), size: gb(1.5), cat: .packageCaches),
        ])
        let oldSaas = dir("old-saas", parent: desktopURL, cat: .codeProjects, children: [
            oldSaasNM,
            file("src", parent: oldSaasURL, size: gb(1.3), cat: .codeProjects, mod: oldDate),
            file("package.json", parent: oldSaasURL, size: mb(1), cat: .codeProjects, mod: oldDate),
        ])

        // sandbox (~2.5 GB)
        let sandboxURL = desktopURL.appendingPathComponent("sandbox")
        let sandbox = dir("sandbox", parent: desktopURL, cat: .codeProjects, children: [
            file("data", parent: sandboxURL, size: gb(2.5), cat: .codeProjects),
        ])

        // Small projects (~0.5-1 GB each)
        func smallProj(_ name: String, size: Double) -> FileNode {
            let url = desktopURL.appendingPathComponent(name)
            return dir(name, parent: desktopURL, cat: .codeProjects, children: [
                file("src", parent: url, size: gb(size), cat: .codeProjects, mod: oldDate),
                file("package.json", parent: url, size: mb(1), cat: .codeProjects, mod: oldDate),
            ])
        }

        let proj1 = smallProj("widget-app", 0.8)
        let proj2 = smallProj("api-server", 0.7)
        let proj3 = smallProj("utils-lib", 0.6)
        let proj4 = smallProj("test-harness", 0.5)
        let proj5 = smallProj("demo-site", 0.4)

        let desktop = dir("Desktop", parent: home, cat: .codeProjects, children: [
            atlas, pebble, orbit, sq, oldSaas, sandbox, proj1, proj2, proj3, proj4, proj5
        ])

        // --- Library (17.1 GB, devTools) ---
        let libraryURL = home.appendingPathComponent("Library")

        let androidSDK = dir("Android", parent: libraryURL, cat: .sdks, children: [
            file("sdk-data", parent: libraryURL.appendingPathComponent("Android"), size: gb(9.9), cat: .sdks),
        ])

        let xcodeURL = libraryURL.appendingPathComponent("Developer/Xcode")
        let derivedData = dir("DerivedData", parent: xcodeURL, cat: .sdks, children: [
            file("Foo-abc", parent: xcodeURL.appendingPathComponent("DerivedData"), size: gb(3.2), cat: .sdks),
            file("Bar-def", parent: xcodeURL.appendingPathComponent("DerivedData"), size: gb(3.3), cat: .sdks),
        ])
        let xcode = dir("Xcode", parent: libraryURL.appendingPathComponent("Developer"), cat: .sdks, children: [
            derivedData,
        ])
        let developer = dir("Developer", parent: libraryURL, cat: .sdks, children: [
            xcode,
        ])

        let libOther1 = file("Preferences", parent: libraryURL, size: gb(0.3), cat: .devTools)
        let libOther2 = file("Application Support", parent: libraryURL, size: gb(0.4), cat: .devTools)

        let library = dir("Library", parent: home, cat: .devTools, children: [
            androidSDK, developer, libOther1, libOther2
        ])

        // --- .ollama (16.7 GB, aiModels) ---
        let ollamaURL = home.appendingPathComponent(".ollama")
        let ollamaModelsURL = ollamaURL.appendingPathComponent("models")
        let ollama = dir(".ollama", parent: home, cat: .aiModels, children: [
            dir("models", parent: ollamaURL, cat: .aiModels, children: [
                file("deepseek-coder-v2", parent: ollamaModelsURL, size: gb(8.3), cat: .aiModels, approx: true),
                file("llama3.1:8b", parent: ollamaModelsURL, size: gb(4.6), cat: .aiModels, approx: true),
                file("mistral:7b-instru...", parent: ollamaModelsURL, size: gb(3.8), cat: .aiModels, approx: true),
            ])
        ])

        // --- .npm (13.4 GB, packageCaches) ---
        let npmURL = home.appendingPathComponent(".npm")
        let npm = dir(".npm", parent: home, cat: .packageCaches, children: [
            file("_cacache", parent: npmURL, size: gb(13.4), cat: .packageCaches),
        ])

        // --- .android (7.3 GB, sdks) ---
        let dotAndroidURL = home.appendingPathComponent(".android")
        let dotAndroid = dir(".android", parent: home, cat: .sdks, children: [
            dir("Emulator images", parent: dotAndroidURL, cat: .sdks, children: [
                file("avd-data", parent: dotAndroidURL.appendingPathComponent("Emulator images"), size: gb(7.3), cat: .sdks),
            ])
        ])

        // --- .gradle (6.6 GB, packageCaches) ---
        let gradleURL = home.appendingPathComponent(".gradle")
        let gradle = dir(".gradle", parent: home, cat: .packageCaches, children: [
            dir("caches", parent: gradleURL, cat: .packageCaches, children: [
                file("cache-data", parent: gradleURL.appendingPathComponent("caches"), size: gb(6.1), cat: .packageCaches),
            ]),
            file("wrapper", parent: gradleURL, size: gb(0.5), cat: .packageCaches),
        ])

        // --- Documents (~6.5 GB, documents) ---
        let documentsURL = home.appendingPathComponent("Documents")
        let documents = dir("Documents", parent: home, cat: .documents, children: [
            file("projects", parent: documentsURL, size: gb(2.5), cat: .documents),
            file("reports", parent: documentsURL, size: gb(2.0), cat: .documents),
            file("archives", parent: documentsURL, size: gb(2.0), cat: .documents),
        ])

        // --- .vscode (~4.0 GB, devTools) ---
        let vscodeURL = home.appendingPathComponent(".vscode")
        let vscode = dir(".vscode", parent: home, cat: .devTools, children: [
            file("extensions", parent: vscodeURL, size: gb(4.0), cat: .devTools),
        ])

        // --- Other docs (~4.0 GB, devTools) ---
        let otherDocsURL = home.appendingPathComponent("Other docs")
        let otherDocs = dir("Other docs", parent: home, cat: .devTools, children: [
            file("misc", parent: otherDocsURL, size: gb(4.0), cat: .devTools),
        ])

        // --- Pictures (~5 GB, documents) ---
        let picturesURL = home.appendingPathComponent("Pictures")
        let pictures = dir("Pictures", parent: home, cat: .documents, children: [
            dir("Photos Library", parent: picturesURL, cat: .documents, children: [
                file("photos", parent: picturesURL.appendingPathComponent("Photos Library"), size: gb(5.0), cat: .documents),
            ])
        ])

        // --- Downloads (~3.5 GB, documents) ---
        let downloadsURL = home.appendingPathComponent("Downloads")
        let downloads = dir("Downloads", parent: home, cat: .documents, children: [
            file("installer.dmg", parent: downloadsURL, size: gb(1.5), cat: .documents),
            file("archive.zip", parent: downloadsURL, size: gb(1.0), cat: .documents),
            file("other", parent: downloadsURL, size: gb(1.0), cat: .documents),
        ])

        // --- .cursor (~2.5 GB, devTools) ---
        let cursorURL = home.appendingPathComponent(".cursor")
        let cursor = dir(".cursor", parent: home, cat: .devTools, children: [
            file("data", parent: cursorURL, size: gb(2.5), cat: .devTools),
        ])

        // --- .cache (~3.0 GB, packageCaches) ---
        let cacheURL = home.appendingPathComponent(".cache")
        let cache = dir(".cache", parent: home, cat: .packageCaches, children: [
            dir("uv", parent: cacheURL, cat: .packageCaches, children: [
                file("data", parent: cacheURL.appendingPathComponent("uv"), size: gb(2.0), cat: .packageCaches),
            ]),
            dir("puppeteer", parent: cacheURL, cat: .packageCaches, children: [
                file("chromium", parent: cacheURL.appendingPathComponent("puppeteer"), size: gb(1.0), cat: .packageCaches),
            ]),
        ])

        // --- Music (~2.5 GB, documents) ---
        let musicURL = home.appendingPathComponent("Music")
        let music = dir("Music", parent: home, cat: .documents, children: [
            file("library", parent: musicURL, size: gb(2.5), cat: .documents),
        ])

        // --- .minikube (~1.2 GB, devTools) ---
        let minikubeURL = home.appendingPathComponent(".minikube")
        let minikube = dir(".minikube", parent: home, cat: .devTools, children: [
            file("machines", parent: minikubeURL, size: gb(1.2), cat: .devTools),
        ])

        let root = FileNode(
            name: "Home",
            url: home,
            isDirectory: true,
            allocatedSize: 0,
            children: [
                desktop, library, ollama, npm, dotAndroid, gradle,
                documents, vscode, otherDocs, pictures, downloads,
                cursor, cache, music, minikube
            ],
            category: .devTools
        )

        root.sortChildrenBySize()
        return root
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
                paths: ["\(homePath)/.gradle/caches"],
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
                    "\(homePath)/Desktop/widget-app/node_modules",
                    "\(homePath)/Desktop/api-server/node_modules",
                    "\(homePath)/Desktop/utils-lib/node_modules",
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
