// AppModel.swift – Main application state
import SwiftUI
import DiskCleanerCore

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

/// Main application state object.
@MainActor
public final class AppModel: ObservableObject {
    // MARK: - Published state
    @Published public var rootNode: FileNode?
    @Published public var recommendations: [Recommendation] = []
    @Published public var selectedRecommendationIDs: Set<String> = []
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

    private let scanner = DiskScanner()

    public init() {}

    // MARK: - Computed properties

    public var currentNode: FileNode? {
        breadcrumb.last ?? rootNode
    }

    public var selectedRecommendations: [Recommendation] {
        recommendations.filter { selectedRecommendationIDs.contains($0.id) }
    }

    public var selectedBytes: Int64 {
        selectedRecommendations.reduce(Int64(0)) { $0 + $1.bytes }
    }

    public var selectedCount: Int {
        selectedRecommendationIDs.count
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
        isScanning = false
        needsFullDiskAccess = false
    }

    public func startScan() async {
        isScanning = true
        scanProgress = nil
        breadcrumb = []

        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let result = await scanner.scan(root: homeURL) { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.scanProgress = progress
            }
        }

        rootNode = result.root
        deniedPaths = result.deniedPaths
        needsFullDiskAccess = result.needsFullDiskAccess

        // Detect recommendations
        let detector = RuleDetector()
        recommendations = detector.detect(
            root: result.root,
            home: homeURL.path
        )

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

    public func navigateToRoot() {
        breadcrumb = []
    }

    public func navigateToBreadcrumb(at index: Int) {
        if index < breadcrumb.count {
            breadcrumb = Array(breadcrumb.prefix(index + 1))
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
            for: selectedRecommendations,
            home: homePath
        )
    }
}
