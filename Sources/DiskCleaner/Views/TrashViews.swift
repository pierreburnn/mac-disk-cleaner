// TrashViews.swift – Selection info, the "Supprimer" button and its confirmation.
import SwiftUI
import AppKit
import DiskCleanerCore

extension DeletionRefusal {
    /// French text for tooltips and alerts (the trash flow is labelled in French).
    var frenchDescription: String {
        switch self {
        case .demoMode: return "La suppression est désactivée en mode démo."
        case .notARealItem: return "Cette tuile regroupe plusieurs petits éléments : ce n’est pas un fichier ou un dossier unique."
        case .emptyPath: return "Sélectionnez une tuile (simple clic) pour pouvoir la supprimer."
        case .notAbsolute: return "Chemin invalide."
        case .outsideHome: return "Seuls les éléments situés dans votre dossier personnel peuvent être mis à la Corbeille."
        case .isHome: return "Votre dossier personnel lui-même ne peut pas être mis à la Corbeille."
        case .protectedFolder(let name):
            return "~/\(name) est un dossier protégé : son contenu peut être mis à la Corbeille, mais pas le dossier lui-même."
        case .insideTrash: return "Cet élément est déjà dans la Corbeille."
        case .doesNotExist: return "Cet élément n’existe plus sur le disque."
        }
    }
}

// MARK: - Selection info (breadcrumb row, right side)

struct SelectionInfo: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let count = model.explorerSelection.count
        if count > 0 {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(Theme.selectionColor, lineWidth: 2)
                    .frame(width: 11, height: 11)
                if count == 1, let pair = model.explorerItems.first, let node = pair.node {
                    Text(node.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(2)
                    Text(model.displayPath(node.url.path))
                        .font(Theme.monoFont(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(ByteFormatter.format(node.totalAllocatedSize))
                        .font(Theme.monoFont(size: 11.5, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .fixedSize()
                } else {
                    let bytes = SelectionPlanner.plan(
                        entries: model.explorerItems.compactMap { $0.node.map(SelectionEntry.tile) },
                        root: model.rootNode, policy: model.deletionPolicy).selectedBytes
                    Text(selectionTitle(count: count))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Text(ByteFormatter.format(bytes))
                        .font(Theme.monoFont(size: 11.5, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .fixedSize()
                }
                Text("Échap pour vider")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textTertiary)
                    .fixedSize()
            }
        }
    }

    private func selectionTitle(count: Int) -> String {
        let base = "\(count) tuiles sélectionnées"
        guard let node = model.currentNode, !model.explorerSelection.isEmpty else {
            return base
        }
        let size = model.lastTreemapSize.width > 1 ? model.lastTreemapSize : CGSize(width: 768, height: 498)
        let items = TreemapGeometry.items(for: node, in: size)
        let selectedPaths = model.explorerSelection.checkedPaths
        let detailed = SelectionMarks.marks(items: items, selectedPaths: selectedPaths, displayedNodePath: node.url.path)
        let direct = detailed.values.filter(\.direct).count
        let hidden = detailed.values.reduce(0) { $0 + $1.hiddenCount }
        let outside = max(0, selectedPaths.count - (direct + hidden))

        var details: [String] = []
        if hidden > 0 {
            details.append(hidden == 1 ? "1 dans un dossier réduit" : "\(hidden) dans des dossiers réduits")
        }
        if outside > 0 {
            details.append(outside == 1 ? "1 hors de ce dossier" : "\(outside) hors de ce dossier")
        }
        if details.isEmpty {
            return base
        }
        return "\(base) (\(details.joined(separator: ", ")))"
    }
}

// MARK: - "Supprimer (N)" button (explorer footer, bottom right)

struct TrashButton: View {
    @EnvironmentObject var model: AppModel
    @State private var hovered = false

    var body: some View {
        let enabled = model.canTrashSelection
        let n = model.trashCount
        HStack(spacing: 5) {
            Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
            Text(n > 0 ? "Supprimer (\(n))" : "Supprimer").font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(enabled ? .white : Theme.textTertiary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(enabled ? (hovered ? Theme.destructiveHover : Theme.destructive) : Theme.segmentTrack)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(enabled ? Color.black.opacity(0.08) : Theme.cardBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { if enabled { model.requestTrashSelection() } }
        .help(model.trashDisabledReason ?? "Mettre à la Corbeille tout ce qui est coché dans le panneau de droite (⌘⌫)")
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(n > 0 ? "Supprimer \(n) éléments" : "Supprimer")
    }
}

// MARK: - Grouped confirmation (custom-drawn so it also renders in snapshots)

struct TrashConfirmationOverlay: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.isSnapshot) var isSnapshot: Bool

    var body: some View {
        if let pending = model.pendingPlan {
            let plan = pending.plan
            ZStack {
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .onTapGesture { }           // swallow clicks behind the dialog
                VStack(spacing: 0) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white, Theme.destructive)
                        .padding(.top, 18)
                    Text("Mettre \(plan.targets.count) élément\(plan.targets.count > 1 ? "s" : "") à la Corbeille ?")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.top, 10)
                    Text("Total : \(ByteFormatter.format(plan.trashableBytes))")
                        .font(Theme.monoFont(size: 12, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.top, 4)

                    list(pending)
                        .frame(height: listHeight(pending))
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.segmentTrack))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .padding(.top, 12)
                        .padding(.horizontal, 16)

                    Text("Les éléments seront déplacés dans la Corbeille : récupérables tant qu’elle n’a pas été vidée. L’espace n’est libéré qu’après avoir vidé la Corbeille.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .padding(.horizontal, 18)
                    HStack(spacing: 8) {
                        DialogButton(title: "Annuler", style: .cancel) { model.cancelTrash() }
                        DialogButton(title: "Mettre à la Corbeille", style: .destructive) { model.confirmTrash() }
                    }
                    .padding(.top, 14)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .frame(width: 460)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.cardBackground)
                        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
                )
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1))
            }
        }
    }

    private func rowCount(_ p: PendingTrash) -> Int { p.plan.targets.count + p.plan.refused.count + (p.plan.refused.isEmpty ? 0 : 1) }
    private func listHeight(_ p: PendingTrash) -> CGFloat { min(250, CGFloat(rowCount(p)) * 34 + 8) }

    @ViewBuilder
    private func list(_ pending: PendingTrash) -> some View {
        let content = VStack(alignment: .leading, spacing: 0) {
            ForEach(pending.plan.targets, id: \.path) { t in
                row(title: title(for: t, in: pending), path: model.displayPath(t.path), bytes: t.bytes, refused: nil)
            }
            if !pending.plan.refused.isEmpty {
                Text("Ignorés (protégés ou hors du dossier personnel)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Theme.reviewBadgeText)
                    .padding(.horizontal, 10)
                    .frame(height: 34, alignment: .bottomLeading)
                ForEach(pending.plan.refused, id: \.path) { r in
                    row(title: (r.path as NSString).lastPathComponent, path: model.displayPath(r.path), bytes: r.bytes,
                        refused: r.refusal.frenchDescription)
                }
            }
        }
        .padding(.vertical, 4)
        if isSnapshot {
            Color.clear.overlay(alignment: .top) { content.fixedSize(horizontal: false, vertical: true) }.clipped()
        } else {
            ScrollView(.vertical) { content }
        }
    }

    private func title(for t: TrashTarget, in pending: PendingTrash) -> String {
        let owners = pending.entries.filter { t.entryIDs.contains($0.id) }
        if let rec = owners.first(where: { $0.kind == .recommendation }) { return rec.title }
        return (t.path as NSString).lastPathComponent
    }

    private func row(title: String, path: String, bytes: Int64, refused: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: refused == nil ? "trash" : "nosign")
                .font(.system(size: 10))
                .foregroundColor(refused == nil ? Theme.textSecondary : Theme.reviewBadgeText)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(refused == nil ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Text(path)
                    .font(Theme.monoFont(size: 10))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(refused ?? path)
            }
            Spacer(minLength: 6)
            Text(ByteFormatter.format(bytes))
                .font(Theme.monoFont(size: 11, weight: .medium))
                .foregroundColor(refused == nil ? Theme.textPrimary : Theme.textTertiary)
                .strikethrough(refused != nil)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }
}

struct DialogButton: View {
    enum Style { case cancel, destructive }
    let title: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Text(title)
            .font(.system(size: 12.5, weight: style == .destructive ? .semibold : .regular))
            .foregroundColor(style == .destructive ? .white : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(style == .destructive ? Theme.destructive : Theme.segmentTrack)
            )
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Keyboard: Escape deselects / cancels, Return confirms, ⌘⌫ asks.

final class TreemapKeyMonitor {
    private var token: Any?

    @MainActor func install(model: AppModel) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
            guard let model else { return event }
            // Don't steal keys from text fields / panels.
            if let responder = event.window?.firstResponder, responder is NSText { return event }
            switch event.keyCode {
            case 53: // Escape
                if model.pendingPlan != nil { model.cancelTrash(); return nil }
                if !model.explorerSelection.isEmpty { model.clearExplorerSelection(); return nil }
            case 36, 76: // Return / Enter
                if model.pendingPlan != nil { model.confirmTrash(); return nil }
            case 51, 117: // Delete / Forward delete
                if event.modifierFlags.contains(.command), model.pendingPlan == nil {
                    model.requestTrashSelection(); return nil
                }
            default: break
            }
            return event
        }
    }

    deinit { if let token { NSEvent.removeMonitor(token) } }
}
