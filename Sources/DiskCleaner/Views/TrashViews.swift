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
        if let selection = model.tileSelection {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(Theme.selectionColor, lineWidth: 2)
                    .frame(width: 11, height: 11)
                switch selection {
                case .node(let node):
                    Image(systemName: node.isDirectory ? "folder" : "doc")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
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
                    Text((node.approximate ? "~" : "") + ByteFormatter.format(node.totalAllocatedSize))
                        .font(Theme.monoFont(size: 11.5, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .fixedSize()
                        .layoutPriority(2)
                case .aggregate(_, let bytes, let count):
                    Text("\(count) petits éléments regroupés")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Text(ByteFormatter.format(bytes))
                        .font(Theme.monoFont(size: 11.5, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .fixedSize()
                }
            }
        }
    }
}

// MARK: - "Supprimer" button (explorer footer, bottom right)

struct TrashButton: View {
    @EnvironmentObject var model: AppModel
    @State private var hovered = false

    var body: some View {
        let enabled = model.canTrashSelection
        HStack(spacing: 5) {
            Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
            Text("Supprimer").font(.system(size: 12, weight: .semibold))
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
        .help(enabled ? "Mettre l’élément sélectionné à la Corbeille (⌘⌫)"
                      : (model.trashRefusal?.frenchDescription ?? "Suppression indisponible pendant l’opération en cours."))
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Supprimer")
    }
}

// MARK: - Confirmation (custom-drawn so it also renders in snapshots)

struct TrashConfirmationOverlay: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let node = model.pendingTrash {
            ZStack {
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .onTapGesture { }           // swallow clicks behind the dialog
                VStack(spacing: 0) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white, Theme.destructive)
                        .padding(.top, 20)
                    Text("Mettre « \(node.name) » à la Corbeille ?")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                        .padding(.horizontal, 18)
                    VStack(spacing: 6) {
                        Text(node.url.path)
                            .font(Theme.monoFont(size: 11))
                            .foregroundColor(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.segmentTrack))
                        Text("\(node.isDirectory ? "Dossier" : "Fichier") · \((node.approximate ? "~" : "") + ByteFormatter.format(node.totalAllocatedSize))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("L’élément sera déplacé dans la Corbeille : vous pourrez le récupérer tant qu’elle n’a pas été vidée. L’espace n’est libéré qu’après avoir vidé la Corbeille.")
                            .font(.system(size: 11.5))
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 10)
                    .padding(.horizontal, 18)
                    HStack(spacing: 8) {
                        DialogButton(title: "Annuler", style: .cancel) { model.cancelTrash() }
                        DialogButton(title: "Mettre à la Corbeille", style: .destructive) { model.confirmTrash() }
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                }
                .frame(width: 340)
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
                if model.pendingTrash != nil { model.cancelTrash(); return nil }
                if model.tileSelection != nil { model.select(nil); return nil }
            case 36, 76: // Return / Enter
                if model.pendingTrash != nil { model.confirmTrash(); return nil }
            case 51, 117: // Delete / Forward delete
                if event.modifierFlags.contains(.command), model.pendingTrash == nil {
                    model.requestTrashSelection(); return nil
                }
            default: break
            }
            return event
        }
    }

    deinit { if let token { NSEvent.removeMonitor(token) } }
}
