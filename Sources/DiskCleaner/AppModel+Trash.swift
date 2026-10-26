// AppModel+Trash.swift – Multi-selection, the selection panel data and the
// grouped "move to Trash".
//
// Requested by the owner: everything ticked in the right panel (clicked tiles
// and ticked recommendations) can be moved to the Trash after one confirmation.
// Only `trashItem` (recoverable) is used; nothing is ever deleted permanently.
// The script generator is unchanged; clicked tiles are simply added to its input.
import SwiftUI
import DiskCleanerCore

/// The grouped confirmation.
public struct PendingTrash: Identifiable {
    public let id = UUID()
    public let entries: [SelectionEntry]
    public let plan: TrashPlan
}

/// Result shown after a batch (or an error).
public struct TrashReport: Identifiable {
    public let id = UUID()
    public let title: String
    public let message: String
}

/// Zoom animation request (double-click in, breadcrumb out).
public struct ZoomRequest: Equatable {
    public enum Direction { case zoomIn, zoomOut }
    public let id = UUID()
    public let direction: Direction
    /// Rectangle of the tile in treemap coordinates (start for in, end for out).
    public let rect: CGRect
    /// Node drawn by the growing / shrinking tile.
    public let node: FileNode
    public static func == (a: ZoomRequest, b: ZoomRequest) -> Bool { a.id == b.id }
}

extension AppModel {
    var deletionPolicy: DeletionPolicy { DeletionPolicy(home: homePath) }

    // MARK: Explorer selection

    public func isInSelection(_ node: FileNode?) -> Bool {
        guard let node else { return false }
        return explorerSelection.contains(node.url.path)
    }

    /// Single click on a tile: add it to the selection, or remove it if already there.
    public func toggleTile(_ node: FileNode) {
        if let root = rootNode, node === root { return }
        let path = node.url.path
        let now = Date()
        if let memo = clickMemo, memo.path == path, now.timeIntervalSince(memo.at) < Self.doubleClickInterval {
            // Second click of a double click: handled by zoomInto.
        } else {
            clickMemo = (path, explorerSelection.contains(path), now)
        }
        explorerSelection.toggle(path)
    }

    public func setTileChecked(_ path: String, _ checked: Bool) { explorerSelection.setChecked(path, checked) }
    public func removeTile(_ path: String) { explorerSelection.remove(path) }
    public func clearExplorerSelection() { explorerSelection.clear() }

    /// Selected tiles resolved against the tree (nil node = no longer in the tree).
    public var explorerItems: [(item: ExplorerSelection.Item, node: FileNode?)] {
        explorerSelection.items.map { item in
            (item, rootNode.flatMap { SelectionPlanner.node(atPath: item.path, in: $0) })
        }
    }

    // MARK: Combined selection

    /// Every ticked line of the panel.
    public var selectionEntries: [SelectionEntry] {
        var entries: [SelectionEntry] = explorerItems.filter { $0.item.checked }.map { pair in
            if let node = pair.node { return .tile(node) }
            return SelectionEntry(id: "tile:" + pair.item.path, kind: .tile,
                                  title: (pair.item.path as NSString).lastPathComponent,
                                  paths: [pair.item.path], fallbackBytes: 0)
        }
        entries += selectedRecommendations.map { .recommendation($0) }
        return entries
    }

    /// De-duplicated plan of the current selection (memoised).
    public var selectionPlan: TrashPlan {
        if let planCache { return planCache }
        let plan = SelectionPlanner.plan(entries: selectionEntries, root: rootNode, policy: deletionPolicy)
        planCache = plan
        return plan
    }

    /// Clicked tiles as script entries, skipping those already covered by a
    /// ticked recommendation (the script generator itself is unchanged).
    var manualScriptRecommendations: [Recommendation] {
        let recPaths = selectedRecommendations.flatMap(\.paths)
        return explorerItems.filter { $0.item.checked }.compactMap { pair in
            let path = pair.item.path
            if recPaths.contains(where: { SelectionPlanner.isSameOrInside(path, $0) }) { return nil }
            let name = (path as NSString).lastPathComponent
            return Recommendation(id: "explorer:" + path, title: "Selected in explorer: \(name)",
                                  displayPath: displayPath(path), paths: [path],
                                  bytes: pair.node?.totalAllocatedSize ?? 0, safety: .review,
                                  detail: "Selected manually in the Disk Cleaner explorer.",
                                  command: .removePaths)
        }
    }

    // MARK: Delete button

    /// Number shown in « Supprimer (N) »: ticked lines of the panel.
    public var trashCount: Int { selectedCount }

    public var trashDisabledReason: String? {
        if selectedCount == 0 { return "Rien n’est coché : cliquez des tuiles ou cochez des recommandations." }
        if previewTrashEnabled { return nil }
        if isDemo { return DeletionRefusal.demoMode.frenchDescription }
        if isScanning || isTrashing { return "Opération en cours…" }
        if selectionPlan.targets.isEmpty { return "Aucun des éléments cochés ne peut être mis à la Corbeille (dossiers protégés ou hors du dossier personnel)." }
        return nil
    }

    public var canTrashSelection: Bool { trashDisabledReason == nil }

    public func displayPath(_ path: String) -> String {
        let home = homePath
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// Show the grouped confirmation.
    public func requestTrashSelection() {
        guard canTrashSelection else { return }
        pendingPlan = PendingTrash(entries: selectionEntries, plan: selectionPlan)
    }

    public func cancelTrash() { pendingPlan = nil }

    /// Move every allowed target to the Trash, then update everything in place.
    public func confirmTrash() {
        guard let pending = pendingPlan else { return }
        pendingPlan = nil
        guard !isDemo else {
            trashReport = TrashReport(title: "Mode démo", message: DeletionRefusal.demoMode.frenchDescription)
            return
        }
        isTrashing = true
        let result = BatchTrasher.run(plan: pending.plan, root: rootNode, policy: deletionPolicy, trasher: trasher)
        isTrashing = false

        let trashedPaths = result.trashed.map(\.path)
        explorerSelection.removeCovered(by: trashedPaths)
        if let root = rootNode {
            breadcrumb = breadcrumb.filter { SelectionPlanner.node(atPath: $0.url.path, in: root) != nil }
        }
        trashReport = Self.report(for: result, displayPath: displayPath)
        if !result.trashed.isEmpty {
            lastTrashedMessage = "\(result.trashed.count) élément(s) mis à la Corbeille (\(ByteFormatter.format(result.trashedBytes)))."
            refreshAfterTreeEdit()
        }
    }

    static func report(for result: BatchTrashResult, displayPath: (String) -> String) -> TrashReport {
        let ok = result.trashed.count
        let bad = result.problemCount
        var lines: [String] = []
        lines.append("\(ok) élément\(ok > 1 ? "s" : "") mis à la Corbeille (\(ByteFormatter.format(result.trashedBytes))), \(bad) refusé\(bad > 1 ? "s" : "") ou en erreur.")
        let problems = result.refused.map { "• \(displayPath($0.path)) — \($0.refusal.frenchDescription)" }
            + result.failed.map { "• \(displayPath($0.path)) — \($0.message)" }
        if !problems.isEmpty {
            lines.append("")
            lines.append(contentsOf: problems.prefix(12))
            if problems.count > 12 { lines.append("… et \(problems.count - 12) autre(s).") }
        }
        if ok > 0 {
            lines.append("")
            lines.append("L’espace ne sera libéré qu’après avoir vidé la Corbeille.")
        }
        let title = bad == 0 ? "Mis à la Corbeille" : (ok == 0 ? "Rien n’a été mis à la Corbeille" : "Mise à la Corbeille partielle")
        return TrashReport(title: title, message: lines.joined(separator: "\n"))
    }

    /// Re-run the rules on the edited tree (no rescan) and refresh free space.
    func refreshAfterTreeEdit() {
        treeRevision += 1
        guard let root = rootNode else { return }
        let home = homePath
        let previouslySelected = selectedRecommendationIDs
        Task { @MainActor in
            let detected: [Recommendation] = await Task.detached(priority: .userInitiated) {
                RuleDetector().detect(root: root, home: home)
            }.value
            self.recommendations = detected
            // Keep the user's ticks for recommendations that still exist.
            self.selectedRecommendationIDs = previouslySelected.intersection(Set(detected.map(\.id)))
            self.volumeInfo = VolumeInfo.query(for: URL(fileURLWithPath: home)) ?? self.volumeInfo
            self.treeRevision += 1
        }
    }

    static var doubleClickInterval: TimeInterval {
        #if canImport(AppKit)
        return NSEvent.doubleClickInterval
        #else
        return 0.5
        #endif
    }

    // MARK: Zoom navigation

    /// Double-click: animate the tile growing, then enter it.
    public func zoomInto(_ node: FileNode, via parent: FileNode?, from rect: CGRect) {
        // A double click must not change the selection: restore the state from
        // before its first click.
        let path = node.url.path
        if let memo = clickMemo, memo.path == path,
           Date().timeIntervalSince(memo.at) < Self.doubleClickInterval + 0.2,
           explorerSelection.contains(path) != memo.wasSelected {
            explorerSelection.toggle(path)
        }
        clickMemo = nil
        guard node.isDirectory, !node.children.isEmpty else { return }
        zoomRequest = ZoomRequest(direction: .zoomIn, rect: rect, node: node)
        if let parent { navigateTo(node: node, via: parent) } else { navigateTo(node: node) }
    }
}
