// CleanupRules.swift – Rule definitions and detector producing [Recommendation]
import Foundation

/// Safety level of a cleanup recommendation.
public enum Safety: String, Sendable, Hashable {
    case safe
    case review
}

/// What kind of cleanup command to run.
public enum CleanupCommand: Sendable, Hashable {
    case removePaths
    case shell(String, fallbackRemove: Bool)
}

/// A cleanup recommendation.
public struct Recommendation: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let displayPath: String
    public let paths: [String]
    public let bytes: Int64
    public let safety: Safety
    public let detail: String
    public let command: CleanupCommand
    public let approximate: Bool

    public init(
        id: String,
        title: String,
        displayPath: String,
        paths: [String],
        bytes: Int64,
        safety: Safety,
        detail: String,
        command: CleanupCommand,
        approximate: Bool = false
    ) {
        self.id = id
        self.title = title
        self.displayPath = displayPath
        self.paths = paths
        self.bytes = bytes
        self.safety = safety
        self.detail = detail
        self.command = command
        self.approximate = approximate
    }

    public static func == (lhs: Recommendation, rhs: Recommendation) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Detects cleanup recommendations from a scanned file tree.
public struct RuleDetector: Sendable {

    public let minimumBytes: Int64

    public init(minimumBytes: Int64 = 1_000_000) {
        self.minimumBytes = minimumBytes
    }

    /// Detect all recommendations from a scanned tree.
    /// - Parameters:
    ///   - root: The root FileNode of the scanned home directory.
    ///   - home: The absolute path of the home directory (e.g., "/Users/pierre").
    ///   - now: The current date (injectable for tests).
    /// - Returns: Array of recommendations, split into safe and review groups, sorted by size desc within each group.
    public func detect(root: FileNode, home: String, now: Date = Date()) -> [Recommendation] {
        var recs: [Recommendation] = []

        let homePath = home.hasSuffix("/") ? String(home.dropLast()) : home

        // SAFE rules
        if let rec = detectNpmCache(root: root, home: homePath) {
            recs.append(rec)
        }
        if let rec = detectNextJsTurbo(root: root, home: homePath) {
            recs.append(rec)
        }
        if let rec = detectGradleCaches(root: root, home: homePath) {
            recs.append(rec)
        }
        if let rec = detectXcodeDerivedData(root: root, home: homePath) {
            recs.append(rec)
        }
        if let rec = detectUvPuppeteerCaches(root: root, home: homePath) {
            recs.append(rec)
        }
        if let rec = detectPipCache(root: root, home: homePath) {
            recs.append(rec)
        }
        if let rec = detectHomebrewCache(root: root, home: homePath) {
            recs.append(rec)
        }
        if let rec = detectYarnPnpmCaches(root: root, home: homePath) {
            recs.append(rec)
        }
        if let rec = detectCocoapodsCache(root: root, home: homePath) {
            recs.append(rec)
        }

        // REVIEW rules
        if let rec = detectAndroidSdk(root: root, home: homePath) {
            recs.append(rec)
        }
        if let rec = detectOllamaModels(root: root, home: homePath) {
            recs.append(rec)
        }
        recs.append(contentsOf: detectWorktrees(root: root, home: homePath))
        if let rec = detectIdleNodeModules(root: root, home: homePath, now: now) {
            recs.append(rec)
        }
        if let rec = detectIOSSimulators(root: root, home: homePath) {
            recs.append(rec)
        }
        if let rec = detectXcodeArchivesDeviceSupport(root: root, home: homePath) {
            recs.append(rec)
        }
        if let rec = detectHuggingFaceCache(root: root, home: homePath) {
            recs.append(rec)
        }
        if let rec = detectAppCaches(root: root, home: homePath) {
            recs.append(rec)
        }
        if let rec = detectTrash(root: root, home: homePath) {
            recs.append(rec)
        }

        // Filter by minimum size and sort
        recs = recs.filter { $0.bytes >= minimumBytes }
        let safe = recs.filter { $0.safety == .safe }.sorted { $0.bytes > $1.bytes }
        let review = recs.filter { $0.safety == .review }.sorted { $0.bytes > $1.bytes }
        return safe + review
    }

    // MARK: - Cleanable paths set (for treemap overlay)

    /// Returns a set of absolute paths that are covered by some recommendation.
    public func cleanablePaths(from recommendations: [Recommendation]) -> Set<String> {
        var paths = Set<String>()
        for rec in recommendations {
            for p in rec.paths {
                paths.insert(p)
            }
        }
        return paths
    }

    // MARK: - SAFE detectors

    private func detectNpmCache(root: FileNode, home: String) -> Recommendation? {
        guard let npm = root.findChild(at: ".npm") else { return nil }
        let size = npm.totalAllocatedSize
        guard size > 0 else { return nil }
        return Recommendation(
            id: "npm-cache",
            title: "npm cache",
            displayPath: "~/.npm",
            paths: ["\(home)/.npm"],
            bytes: size,
            safety: .safe,
            detail: "Local npm package cache. Safely cleared; npm re-downloads packages as needed.",
            command: .shell(
                "if command -v npm >/dev/null; then npm cache clean --force; else rm -rf \"$HOME\"/.npm/_cacache; fi",
                fallbackRemove: true
            )
        )
    }

    private func detectNextJsTurbo(root: FileNode, home: String) -> Recommendation? {
        var foundPaths: [String] = []
        var totalSize: Int64 = 0
        var parentDirs: Set<String> = []

        collectNextTurbo(node: root, home: home, parentDirs: &parentDirs, foundPaths: &foundPaths, totalSize: &totalSize, depth: 0)

        guard totalSize > 0, !foundPaths.isEmpty else { return nil }

        // Build display path
        let displayPath: String
        if parentDirs.count == 1, let parent = parentDirs.first {
            displayPath = "~/\(parent)/*/.next, .turbo"
        } else {
            let sorted = parentDirs.sorted()
            displayPath = "~/\(sorted.first ?? "")/*/.next, .turbo"
        }

        return Recommendation(
            id: "nextjs-turbo",
            title: "Next.js & Turbo build output",
            displayPath: displayPath,
            paths: foundPaths,
            bytes: totalSize,
            safety: .safe,
            detail: "Build output from Next.js and Turborepo. Regenerated automatically on next build.",
            command: .removePaths
        )
    }

    private func collectNextTurbo(
        node: FileNode,
        home: String,
        parentDirs: inout Set<String>,
        foundPaths: inout [String],
        totalSize: inout Int64,
        depth: Int
    ) {
        guard node.isDirectory else { return }
        for child in node.children {
            if child.isDirectory && (child.name == ".next" || child.name == ".turbo") {
                // Skip if inside node_modules
                let relPath = String(child.url.path.dropFirst(home.count + 1))
                if relPath.contains("node_modules") { continue }
                foundPaths.append(child.url.path)
                totalSize += child.totalAllocatedSize
                // Find the top-level parent dir
                let components = relPath.split(separator: "/")
                if let first = components.first {
                    parentDirs.insert(String(first))
                }
            }
            if child.isDirectory && child.name != "node_modules" && child.name != ".next" && child.name != ".turbo" {
                collectNextTurbo(node: child, home: home, parentDirs: &parentDirs, foundPaths: &foundPaths, totalSize: &totalSize, depth: depth + 1)
            }
        }
    }

    private func detectGradleCaches(root: FileNode, home: String) -> Recommendation? {
        guard let gradle = root.findChild(at: ".gradle") else { return nil }
        var paths: [String] = []
        var totalSize: Int64 = 0
        if let caches = gradle.children.first(where: { $0.name == "caches" }) {
            paths.append(caches.url.path)
            totalSize += caches.totalAllocatedSize
        }
        if let wrapper = gradle.findChild(at: "wrapper/dists") {
            paths.append(wrapper.url.path)
            totalSize += wrapper.totalAllocatedSize
        }
        // If no specific children found, use the whole .gradle dir size
        if paths.isEmpty {
            totalSize = gradle.totalAllocatedSize
            paths = ["\(home)/.gradle"]
        }
        guard totalSize > 0 else { return nil }
        return Recommendation(
            id: "gradle-caches",
            title: "Gradle caches",
            displayPath: "~/.gradle",
            paths: paths,
            bytes: totalSize,
            safety: .safe,
            detail: "Gradle build caches and wrapper distributions. Re-downloaded on next build.",
            command: .removePaths
        )
    }

    private func detectXcodeDerivedData(root: FileNode, home: String) -> Recommendation? {
        guard let dd = root.findChild(at: "Library/Developer/Xcode/DerivedData") else { return nil }
        let size = dd.totalAllocatedSize
        guard size > 0 else { return nil }
        return Recommendation(
            id: "xcode-deriveddata",
            title: "Xcode DerivedData",
            displayPath: "~/Library/Developer/Xcode",
            paths: [dd.url.path],
            bytes: size,
            safety: .safe,
            detail: "Xcode build intermediates and indexes. Rebuilt automatically when you next open a project.",
            command: .removePaths
        )
    }

    private func detectUvPuppeteerCaches(root: FileNode, home: String) -> Recommendation? {
        var paths: [String] = []
        var totalSize: Int64 = 0

        if let uv = root.findChild(at: ".cache/uv") {
            paths.append(uv.url.path)
            totalSize += uv.totalAllocatedSize
        }
        if let pupp = root.findChild(at: ".cache/puppeteer") {
            paths.append(pupp.url.path)
            totalSize += pupp.totalAllocatedSize
        }
        guard totalSize > 0 else { return nil }

        let displayParts = paths.map { p -> String in
            return "~" + p.dropFirst(home.count)
        }

        return Recommendation(
            id: "uv-puppeteer-caches",
            title: "uv & Puppeteer caches",
            displayPath: displayParts.joined(separator: ", "),
            paths: paths,
            bytes: totalSize,
            safety: .safe,
            detail: "Cached downloads for uv (Python) and Puppeteer (Chromium). Re-downloaded when needed.",
            command: .shell(
                "if command -v uv >/dev/null; then uv cache clean; else rm -rf \"$HOME\"/.cache/uv; fi\nrm -rf \"$HOME\"/.cache/puppeteer",
                fallbackRemove: true
            )
        )
    }

    private func detectPipCache(root: FileNode, home: String) -> Recommendation? {
        var paths: [String] = []
        var totalSize: Int64 = 0
        if let pip1 = root.findChild(at: "Library/Caches/pip") {
            paths.append(pip1.url.path)
            totalSize += pip1.totalAllocatedSize
        }
        if let pip2 = root.findChild(at: ".cache/pip") {
            paths.append(pip2.url.path)
            totalSize += pip2.totalAllocatedSize
        }
        guard totalSize > 0 else { return nil }
        return Recommendation(
            id: "pip-cache",
            title: "pip cache",
            displayPath: "~/Library/Caches/pip",
            paths: paths,
            bytes: totalSize,
            safety: .safe,
            detail: "Python pip download cache. Cleared safely; packages re-download as needed.",
            command: .shell(
                "if command -v pip3 >/dev/null; then pip3 cache purge; else rm -rf \"$HOME\"/Library/Caches/pip \"$HOME\"/.cache/pip; fi",
                fallbackRemove: true
            )
        )
    }

    private func detectHomebrewCache(root: FileNode, home: String) -> Recommendation? {
        guard let brew = root.findChild(at: "Library/Caches/Homebrew") else { return nil }
        let size = brew.totalAllocatedSize
        guard size > 0 else { return nil }
        return Recommendation(
            id: "homebrew-cache",
            title: "Homebrew cache",
            displayPath: "~/Library/Caches/Homebrew",
            paths: [brew.url.path],
            bytes: size,
            safety: .safe,
            detail: "Homebrew download cache. Cleared safely with brew cleanup.",
            command: .shell(
                "if command -v brew >/dev/null; then brew cleanup -s; else rm -rf \"$HOME\"/Library/Caches/Homebrew; fi",
                fallbackRemove: true
            )
        )
    }

    private func detectYarnPnpmCaches(root: FileNode, home: String) -> Recommendation? {
        var paths: [String] = []
        var totalSize: Int64 = 0

        let yarnPnpmPaths: [(String)] = [
            "Library/Caches/Yarn",
            ".yarn/berry/cache",
            "Library/pnpm/store",
            ".pnpm-store",
            ".cache/yarn"
        ]
        for rel in yarnPnpmPaths {
            if let node = root.findChild(at: rel) {
                paths.append(node.url.path)
                totalSize += node.totalAllocatedSize
            }
        }
        guard totalSize > 0 else { return nil }
        return Recommendation(
            id: "yarn-pnpm-caches",
            title: "Yarn & pnpm caches",
            displayPath: "~/Library/Caches/Yarn",
            paths: paths,
            bytes: totalSize,
            safety: .safe,
            detail: "Yarn and pnpm package caches. Re-downloaded when needed.",
            command: .removePaths
        )
    }

    private func detectCocoapodsCache(root: FileNode, home: String) -> Recommendation? {
        guard let pods = root.findChild(at: "Library/Caches/CocoaPods") else { return nil }
        let size = pods.totalAllocatedSize
        guard size > 0 else { return nil }
        return Recommendation(
            id: "cocoapods-cache",
            title: "CocoaPods cache",
            displayPath: "~/Library/Caches/CocoaPods",
            paths: [pods.url.path],
            bytes: size,
            safety: .safe,
            detail: "CocoaPods spec and download cache. Safely cleared.",
            command: .shell(
                "if command -v pod >/dev/null; then pod cache clean --all; else rm -rf \"$HOME\"/Library/Caches/CocoaPods; fi",
                fallbackRemove: true
            )
        )
    }

    // MARK: - REVIEW detectors

    private func detectAndroidSdk(root: FileNode, home: String) -> Recommendation? {
        var paths: [String] = []
        var totalSize: Int64 = 0
        if let android = root.findChild(at: "Library/Android") {
            paths.append(android.url.path)
            totalSize += android.totalAllocatedSize
        }
        if let dotAndroid = root.findChild(at: ".android") {
            paths.append(dotAndroid.url.path)
            totalSize += dotAndroid.totalAllocatedSize
        }
        guard totalSize > 0 else { return nil }
        return Recommendation(
            id: "android-sdk",
            title: "Android SDK & emulators",
            displayPath: "~/Library/Android, ~/.android",
            paths: paths,
            bytes: totalSize,
            safety: .review,
            detail: "Android SDK, AVD images, and emulator data. Remove if you no longer do Android development.",
            command: .removePaths
        )
    }

    private func detectOllamaModels(root: FileNode, home: String) -> Recommendation? {
        guard let models = root.findChild(at: ".ollama/models") else {
            // Try .ollama as a whole
            guard let ollama = root.findChild(at: ".ollama") else { return nil }
            let size = ollama.totalAllocatedSize
            guard size > 0 else { return nil }
            return Recommendation(
                id: "ollama-models",
                title: "Ollama models",
                displayPath: "~/.ollama/models",
                paths: ["\(home)/.ollama/models"],
                bytes: size,
                safety: .review,
                detail: "Downloaded LLM models for Ollama. Use 'ollama rm <model>' to selectively remove models.",
                command: .shell("# Remove individual models with: ollama rm <model-name>\nrm -rf \"$HOME\"/.ollama/models", fallbackRemove: false)
            )
        }
        let size = models.totalAllocatedSize
        guard size > 0 else { return nil }
        return Recommendation(
            id: "ollama-models",
            title: "Ollama models",
            displayPath: "~/.ollama/models",
            paths: [models.url.path],
            bytes: size,
            safety: .review,
            detail: "Downloaded LLM models for Ollama. Use 'ollama rm <model>' to selectively remove models.",
            command: .shell("# Remove individual models with: ollama rm <model-name>\nrm -rf \"$HOME\"/.ollama/models", fallbackRemove: false)
        )
    }

    private func detectWorktrees(root: FileNode, home: String) -> [Recommendation] {
        var recs: [Recommendation] = []
        collectWorktrees(node: root, home: home, recs: &recs, depth: 0)
        return recs
    }

    private func collectWorktrees(node: FileNode, home: String, recs: inout [Recommendation], depth: Int) {
        guard node.isDirectory, depth < 8 else { return }
        // Check for .claude/worktrees
        if let claude = node.children.first(where: { $0.name == ".claude" }),
           let worktrees = claude.children.first(where: { $0.name == "worktrees" }) {
            let size = worktrees.totalAllocatedSize
            if size > 0 {
                let relPath = String(node.url.path.dropFirst(home.count + 1))
                let projectName = node.name
                recs.append(Recommendation(
                    id: "worktrees-\(projectName)",
                    title: "\(projectName) worktrees",
                    displayPath: "~/\(relPath)/.claude/worktrees",
                    paths: [worktrees.url.path],
                    bytes: size,
                    safety: .review,
                    detail: "Claude Code worktrees for \(projectName). Remove if no longer needed; run 'git worktree prune' afterwards.",
                    command: .removePaths,
                    approximate: true
                ))
            }
        }
        for child in node.children where child.isDirectory {
            collectWorktrees(node: child, home: home, recs: &recs, depth: depth + 1)
        }
    }

    private func detectIdleNodeModules(root: FileNode, home: String, now: Date) -> Recommendation? {
        var idlePaths: [String] = []
        var totalSize: Int64 = 0
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 3600)

        collectIdleNodeModules(node: root, home: home, threshold: thirtyDaysAgo, idlePaths: &idlePaths, totalSize: &totalSize, depth: 0)

        guard totalSize > 0, !idlePaths.isEmpty else { return nil }
        return Recommendation(
            id: "idle-node-modules",
            title: "node_modules in idle projects",
            displayPath: "~/…/node_modules",
            paths: idlePaths,
            bytes: totalSize,
            safety: .review,
            detail: "node_modules in projects not modified in the last 30 days. Run 'npm install' to restore.",
            command: .removePaths
        )
    }

    private func collectIdleNodeModules(
        node: FileNode,
        home: String,
        threshold: Date,
        idlePaths: inout [String],
        totalSize: inout Int64,
        depth: Int
    ) {
        guard node.isDirectory, depth < 10 else { return }
        for child in node.children {
            if child.name == "node_modules" && child.isDirectory {
                // Check if the parent project is idle
                let newestDate = newestModificationDate(in: node, excluding: "node_modules")
                if let newest = newestDate, newest < threshold {
                    idlePaths.append(child.url.path)
                    totalSize += child.totalAllocatedSize
                }
                // Don't recurse into node_modules
                continue
            }
            if child.isDirectory {
                collectIdleNodeModules(node: child, home: home, threshold: threshold, idlePaths: &idlePaths, totalSize: &totalSize, depth: depth + 1)
            }
        }
    }

    private func newestModificationDate(in node: FileNode, excluding name: String) -> Date? {
        var newest: Date? = nil
        for child in node.children where child.name != name {
            if let mod = child.modificationDate {
                if newest == nil || mod > newest! {
                    newest = mod
                }
            }
        }
        return newest
    }

    private func detectIOSSimulators(root: FileNode, home: String) -> Recommendation? {
        guard let devices = root.findChild(at: "Library/Developer/CoreSimulator/Devices") else { return nil }
        let size = devices.totalAllocatedSize
        guard size > 0 else { return nil }
        return Recommendation(
            id: "ios-simulators",
            title: "iOS Simulators",
            displayPath: "~/Library/Developer/CoreSimulator",
            paths: [devices.url.path],
            bytes: size,
            safety: .review,
            detail: "iOS Simulator device data. Removes all simulator devices; re-created in Xcode as needed.",
            command: .shell("if command -v xcrun >/dev/null; then xcrun simctl delete all; fi", fallbackRemove: false)
        )
    }

    private func detectXcodeArchivesDeviceSupport(root: FileNode, home: String) -> Recommendation? {
        var paths: [String] = []
        var totalSize: Int64 = 0
        if let archives = root.findChild(at: "Library/Developer/Xcode/Archives") {
            paths.append(archives.url.path)
            totalSize += archives.totalAllocatedSize
        }
        if let ds = root.findChild(at: "Library/Developer/Xcode/iOS DeviceSupport") {
            paths.append(ds.url.path)
            totalSize += ds.totalAllocatedSize
        }
        guard totalSize > 0 else { return nil }
        return Recommendation(
            id: "xcode-archives-devicesupport",
            title: "Xcode Archives & DeviceSupport",
            displayPath: "~/Library/Developer/Xcode/Archives",
            paths: paths,
            bytes: totalSize,
            safety: .review,
            detail: "Old Xcode app archives and iOS device support files. Remove if you don't need to debug on older iOS versions.",
            command: .removePaths
        )
    }

    private func detectHuggingFaceCache(root: FileNode, home: String) -> Recommendation? {
        guard let hf = root.findChild(at: ".cache/huggingface") else { return nil }
        let size = hf.totalAllocatedSize
        guard size > 0 else { return nil }
        return Recommendation(
            id: "huggingface-cache",
            title: "Hugging Face cache",
            displayPath: "~/.cache/huggingface",
            paths: [hf.url.path],
            bytes: size,
            safety: .review,
            detail: "Downloaded ML models and datasets from Hugging Face. Re-downloaded on next use.",
            command: .removePaths
        )
    }

    private func detectAppCaches(root: FileNode, home: String) -> Recommendation? {
        guard let libCaches = root.findChild(at: "Library/Caches") else { return nil }
        let coveredNames: Set<String> = [
            "pip", "Homebrew", "Yarn", "CocoaPods"
        ]
        var totalSize: Int64 = 0
        var paths: [String] = []
        for child in libCaches.children {
            if !coveredNames.contains(child.name) {
                totalSize += child.totalAllocatedSize
                paths.append(child.url.path)
            }
        }
        guard totalSize > 0 else { return nil }
        return Recommendation(
            id: "app-caches",
            title: "App caches",
            displayPath: "~/Library/Caches",
            paths: paths,
            bytes: totalSize,
            safety: .review,
            detail: "Application caches. Some apps may need to rebuild caches after removal.",
            command: .removePaths
        )
    }

    private func detectTrash(root: FileNode, home: String) -> Recommendation? {
        guard let trash = root.findChild(at: ".Trash") else { return nil }
        let size = trash.totalAllocatedSize
        guard size > 0 else { return nil }
        return Recommendation(
            id: "trash",
            title: "Trash",
            displayPath: "~/.Trash",
            paths: ["\(home)/.Trash"],
            bytes: size,
            safety: .review,
            detail: "Files in the Trash. Permanently deletes all trashed items.",
            command: .shell(
                "if [ -d \"$HOME\"/.Trash ]; then find \"$HOME\"/.Trash -mindepth 1 -maxdepth 1 -exec rm -rf {} +; fi",
                fallbackRemove: false
            )
        )
    }
}
