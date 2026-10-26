// AppModel.swift – Main application state
import SwiftUI
import DiskCleanerCore
#if canImport(AppKit)
import AppKit
#endif

/// Display mode for the treemap.
public enum DisplayMode: String, CaseIterable {
    case category = "Category"
    case cleanup = "Cleanup"
}

/// Environment key for snapshot mode.
private struct IsSnapshotKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    public var isSnapshot: Bool {
        get { self[IsSnapshotKey.self] }
        set { self[IsSnapshotKey.self] = newValue }
    }
}

/// Relationship between a treemap tile and the cleanup recommendations.
public struct TileCoverage: Equatable {
    public enum Kind { case none, safe, review }
    public var kind: Kind
    public var selected: Bool

    public static let none = TileCoverage(kind: .none, selected: false)

    public init(kind: Kind, selected: Bool) {
        self.kind = kind
        self.selected = selected
    }

    public init(safety: Safety, selected: Bool) {
        self.kind = safety == .safe ? .safe : .review
        self.selected = selected
    }
}

/// Main application state object.
@MainActor
public final class AppModel: ObservableObject {
    // MARK: - Published state
    @Published public var rootNode: FileNode?
    @Published public var recommendations: [Recommendation] = [] { didSet { coverageCache = [:]; planCache = nil } }
    @Published public var selectedRecommendationIDs: Set<String> = [] { didSet { coverageCache = [:]; planCache = nil } }
    @Published public var volumeInfo: VolumeInfo?
    @Published public var displayMode: DisplayMode = .category
    @Published public var breadcrumb: [FileNode] = []
    @Published public var isScanning: Bool = false
    @Published public var scanProgress: ScanProgress?
    @Published public var needsFullDiskAccess: Bool = false
    @Published public var deniedPaths: [String] = []
    @Published public var expandedRecommendationIDs: Set<String> = []
    @Published public var showCopiedFeedback: Bool = false
    @Published public var isDemo: Bool = false

    // Treemap selection & move-to-Trash
    /// Tiles clicked in the explorer (multi-selection, click toggles).
    @Published public var explorerSelection = ExplorerSelection() { didSet { planCache = nil } }
    /// Grouped confirmation currently shown (nil = none).
    @Published public var pendingPlan: PendingTrash?
    /// Summary / error shown after a batch.
    @Published public var trashReport: TrashReport?
    @Published public var lastTrashedMessage: String?
    /// Zoom animation request consumed by the treemap.
    @Published public var zoomRequest: ZoomRequest?
    @Published public var isTrashing: Bool = false
    /// Bumped whenever the tree is edited in place (FileNode is a class).
    @Published public var treeRevision: Int = 0 { didSet { planCache = nil } }
    /// Snapshot-only: render the Delete button as it looks for a real item.
    public var previewTrashEnabled: Bool = false
    /// Injectable for tests / previews.
    public var trasher: TrashPerforming = FileManagerTrasher()
    /// Snapshot-only: freeze the zoom overlay at a given progress for ImageRenderer.
    public var snapshotZoom: (request: ZoomRequest, progress: CGFloat)?
    /// Last treemap size written by TreemapView (used by snapshot renderer).
    public var lastTreemapSize: CGSize = .zero

    private let scanner = DiskScanner()
    private var coverageCache: [String: TileCoverage] = [:]
    var planCache: TrashPlan?
    /// State of a tile before the first click of a possible double click.
    var clickMemo: (path: String, wasSelected: Bool, at: Date)?
    /// Set when the app was launched in snapshot mode (no automatic scan).
    public var isSnapshotRun: Bool = false

    public init() {}

    // MARK: - Computed properties

    public var currentNode: FileNode? {
        breadcrumb.last ?? rootNode
    }

    public var selectedRecommendations: [Recommendation] {
        recommendations.filter { selectedRecommendationIDs.contains($0.id) }
    }

    /// Everything ticked in the panel (clicked tiles + recommendations), de-duplicated.
    public var selectedBytes: Int64 { selectionPlan.selectedBytes }

    /// Number of ticked lines in the panel (tiles + recommendations).
    public var selectedCount: Int {
        selectedRecommendationIDs.intersection(recommendations.map(\.id)).count
            + explorerSelection.checkedPaths.count
    }

    public var safeRecommendations: [Recommendation] {
        recommendations.filter { $0.safety == .safe }
    }

    public var reviewRecommendations: [Recommendation] {
        recommendations.filter { $0.safety == .review }
    }

    public var safeTotal: Int64 {
        safeRecommendations.reduce(Int64(0)) { $0 + $1.bytes }
    }

    public var reviewTotal: Int64 {
        reviewRecommendations.reduce(Int64(0)) { $0 + $1.bytes }
    }

    public var freeAfterCleanup: Int64 {
        (volumeInfo?.availableCapacity ?? 0) + selectedBytes
    }

    public var notScanned: Int64 {
        guard let vol = volumeInfo, let root = rootNode else { return 0 }
        return vol.notScanned(scannedTotal: root.totalAllocatedSize)
    }

    public var cleanablePaths: Set<String> {
        let detector = RuleDetector()
        return detector.cleanablePaths(from: recommendations)
    }

    /// How a node relates to the recommendations (drives tile colouring).
    public func coverage(of node: FileNode) -> TileCoverage {
        if let cached = coverageCache[node.id] { return cached }
        var result = TileCoverage.none
        let path = node.url.path
        if let rec = recommendations.first(where: { rec in
            rec.paths.contains { p in path == p || path.hasPrefix(p + "/") }
        }) {
            result = TileCoverage(safety: rec.safety, selected: selectedRecommendationIDs.contains(rec.id))
        } else if node.isDirectory, !node.children.isEmpty, node.allocatedSize < node.totalAllocatedSize / 50 {
            // A folder whose every child is covered is itself covered (e.g. ~/.gradle).
            let kids = node.children.map { coverage(of: $0) }
            if kids.allSatisfy({ $0.kind != .none }) {
                result = kids[0]
                if !kids.allSatisfy({ $0.selected }) { result.selected = false }
            }
        }
        coverageCache[node.id] = result
        return result
    }

    /// Check if a file node's path is covered by any recommendation.
    public func isCleanable(node: FileNode) -> Bool {
        let nodePath = node.url.path
        for rec in recommendations {
            for path in rec.paths {
                if nodePath == path || nodePath.hasPrefix(path + "/") || path.hasPrefix(nodePath + "/") {
                    return true
                }
            }
        }
        return false
    }

    /// Home path (for display with ~).
    public var homePath: String {
        if isDemo {
            return DemoData.homePath
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    // MARK: - Actions

    public func loadDemo() {
        isDemo = true
        rootNode = DemoData.makeTree()
        recommendations = DemoData.makeRecommendations()
        selectedRecommendationIDs = DemoData.defaultSelectedIDs
        volumeInfo = DemoData.makeVolumeInfo()
        breadcrumb = []
        explorerSelection.clear()
        isScanning = false
        needsFullDiskAccess = false
    }

    public func startScan() async {
        isScanning = true
        scanProgress = nil
        breadcrumb = []
        explorerSelection.clear()

        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let result = await scanner.scan(root: homeURL) { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.scanProgress = progress
            }
        }

        rootNode = result.root
        deniedPaths = result.deniedPaths
        needsFullDiskAccess = result.needsFullDiskAccess

        // Detect recommendations (off the main thread)
        let homePath = homeURL.path
        let root = result.root
        let detected: [Recommendation] = await Task.detached(priority: .userInitiated) {
            RuleDetector().detect(root: root, home: homePath)
        }.value
        recommendations = detected

        // Auto-select safe recommendations
        selectedRecommendationIDs = Set(recommendations.filter { $0.safety == .safe }.map { $0.id })

        // Get volume info
        volumeInfo = VolumeInfo.query(for: homeURL)

        isScanning = false
    }

    public func navigateTo(node: FileNode) {
        if node.isDirectory && !node.children.isEmpty {
            if let root = rootNode, node.id == root.id {
                breadcrumb = []
            } else {
                breadcrumb.append(node)
            }
        }
    }

    /// Drill into `node`, which is a child of `parent` (itself a child of the current folder).
    public func navigateTo(node: FileNode, via parent: FileNode) {
        guard node.isDirectory, !node.children.isEmpty else {
            navigateTo(node: parent)
            return
        }
        breadcrumb.append(parent)
        breadcrumb.append(node)
    }

    /// Ask where to save the cleanup script. Writing a file is the only thing
    /// this does – the script is never executed by the app.
    public func saveScriptWithPanel() {
        #if canImport(AppKit)
        let script = generateScript()
        let panel = NSSavePanel()
        panel.title = "Save Cleanup Script"
        panel.nameFieldStringValue = "disk-cleanup.sh"
        panel.allowedContentTypes = [.shellScript]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? script.write(to: url, atomically: true, encoding: .utf8)
        }
        #endif
    }

    public func revealInFinder(_ path: String) {
        guard !isDemo else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        #endif
    }

    public func navigateToRoot() {
        let previous = currentNode
        breadcrumb = []
        if let previous, previous !== currentNode {
            zoomRequest = ZoomRequest(direction: .zoomOut, rect: .zero, node: previous)
        }
    }

    public func navigateToBreadcrumb(at index: Int) {
        let previous = currentNode
        if index < breadcrumb.count {
            breadcrumb = Array(breadcrumb.prefix(index + 1))
        }
        if let previous, previous !== currentNode {
            zoomRequest = ZoomRequest(direction: .zoomOut, rect: .zero, node: previous)
        }
    }

    public func toggleRecommendation(_ rec: Recommendation) {
        if selectedRecommendationIDs.contains(rec.id) {
            selectedRecommendationIDs.remove(rec.id)
        } else {
            selectedRecommendationIDs.insert(rec.id)
        }
    }

    public func toggleExpandRecommendation(_ rec: Recommendation) {
        if expandedRecommendationIDs.contains(rec.id) {
            expandedRecommendationIDs.remove(rec.id)
        } else {
            expandedRecommendationIDs.insert(rec.id)
        }
    }

    public func selectAllSafe() {
        for rec in safeRecommendations {
            selectedRecommendationIDs.insert(rec.id)
        }
    }

    public func generateScript() -> String {
        return ScriptGenerator.makeScript(
            for: selectedRecommendations + manualScriptRecommendations,
            home: homePath
        )
    }
}
