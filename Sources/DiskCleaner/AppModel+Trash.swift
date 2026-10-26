// AppModel+Trash.swift – Treemap tile selection and "move to Trash".
//
// Explicitly requested by the owner: a confirmed, single item can be moved to
// the Trash (recoverable). Nothing is ever deleted permanently, and the
// cleanup-script feature is unchanged.
import SwiftUI
import DiskCleanerCore

/// What is selected in the treemap.
public enum TileSelection: Equatable {
    case node(FileNode)
    /// The "other" bucket: many small items drawn as one tile.
    case aggregate(parent: FileNode, bytes: Int64, count: Int)

    public static func == (a: TileSelection, b: TileSelection) -> Bool {
        switch (a, b) {
        case (.node(let x), .node(let y)): return x === y
        case (.aggregate(let p, _, _), .aggregate(let q, _, _)): return p === q
        default: return false
        }
    }

    public var node: FileNode? {
        if case .node(let n) = self { return n }
        return nil
    }
}

extension AppModel {
    var deletionPolicy: DeletionPolicy { DeletionPolicy(home: homePath) }

    public func select(_ selection: TileSelection?) {
        if tileSelection != selection { tileSelection = selection }
    }

    public func isSelected(_ node: FileNode?) -> Bool {
        guard let node, let sel = tileSelection?.node else { return false }
        return sel === node
    }

    /// Why the selected tile cannot be moved to the Trash (nil = it can).
    public var trashRefusal: DeletionRefusal? {
        guard let selection = tileSelection else { return .emptyPath }
        guard let node = selection.node else { return .notARealItem }
        if isDemo { return .demoMode }
        if let root = rootNode, node === root { return .isHome }
        return deletionPolicy.refusal(forPath: node.url.path)
    }

    public var canTrashSelection: Bool {
        if previewTrashEnabled, tileSelection?.node != nil { return true }
        return trashRefusal == nil && !isTrashing && !isScanning
    }

    public func displayPath(_ path: String) -> String {
        let home = homePath
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// Show the confirmation for the selected tile.
    public func requestTrashSelection() {
        guard canTrashSelection, let node = tileSelection?.node else { return }
        pendingTrash = node
    }

    public func cancelTrash() { pendingTrash = nil }

    /// Move the confirmed item to the Trash and update the tree in place.
    public func confirmTrash() {
        guard let node = pendingTrash else { return }
        pendingTrash = nil
        guard !isDemo, let root = rootNode else {
            trashErrorMessage = DeletionRefusal.demoMode.description
            return
        }
        isTrashing = true
        defer { isTrashing = false }
        do {
            _ = try FileTreeEditor.trash(node: node, root: root, policy: deletionPolicy, trasher: trasher)
        } catch let refusal as DeletionRefusal {
            trashErrorMessage = refusal.description
            return
        } catch {
            let ns = error as NSError
            var msg = "« \(node.name) » n’a pas pu être mis à la Corbeille.\n\n\(ns.localizedDescription)"
            if ns.domain == NSCocoaErrorDomain && (ns.code == NSFileWriteNoPermissionError || ns.code == NSFileReadNoPermissionError) {
                msg += "\n\nVérifiez les autorisations (Accès complet au disque) ou si l’élément est utilisé par une autre app."
            }
            trashErrorMessage = msg
            return
        }
        tileSelection = nil
        // Drop breadcrumb entries that no longer exist (defensive).
        breadcrumb = breadcrumb.filter { FileTreeEditor.pathToNode(withID: $0.id, in: root) != nil }
        lastTrashedMessage = "« \(node.name) » (\(ByteFormatter.format(node.totalAllocatedSize))) a été mis à la Corbeille."
        refreshAfterTreeEdit()
    }

    /// Re-run the rules on the edited tree (no rescan) and refresh free space.
    func refreshAfterTreeEdit() {
        treeRevision += 1
        guard let root = rootNode else { return }
        let home = homePath
        let previouslySelected = selectedRecommendationIDs
        let previousIDs = Set(recommendations.map(\.id))
        Task { @MainActor in
            let detected: [Recommendation] = await Task.detached(priority: .userInitiated) {
                RuleDetector().detect(root: root, home: home)
            }.value
            self.recommendations = detected
            let ids = Set(detected.map(\.id))
            // Keep the user's choices; auto-select new safe items only.
            self.selectedRecommendationIDs = previouslySelected.intersection(ids)
                .union(detected.filter { $0.safety == .safe && !previousIDs.contains($0.id) }.map(\.id))
            self.volumeInfo = VolumeInfo.query(for: URL(fileURLWithPath: home)) ?? self.volumeInfo
            self.treeRevision += 1
        }
    }
}
