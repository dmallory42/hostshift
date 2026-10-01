import SwiftUI
import HostsCore

struct ProfileSidebar: View {
    @Bindable var store: ProfileStore

    var body: some View {
        List(selection: $store.selection) {
            Section("Profiles") {
                ForEach(store.profiles) { profile in
                    HStack {
                        Label(profile.displayName,
                              systemImage: profile.isOriginal ? "clock.arrow.circlepath" : "doc.text")
                        if store.isUnsaved(id: profile.id) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Unsaved changes")
                                .help("Unsaved changes")
                        }
                        Spacer()
                        if store.activeID == profile.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Active profile")
                                .help("Active profile")
                        }
                    }
                    .tag(profile.id)
                }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            Button("New Profile", systemImage: "doc.badge.plus") { store.add() }
            if let id = ids.first, ids.count == 1 {
                Divider()
                if let profile = store.profiles.first(where: { $0.id == id }), store.activeID != id {
                    Button("Activate", systemImage: "checkmark.circle") {
                        Task { await store.apply(id: id) }
                    }
                    .disabled(!store.canApply(profile))
                    Divider()
                }
                Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(id: id) }
                Button("Rename…", systemImage: "pencil") { store.requestRename(id: id) }
                    .disabled(store.profiles.first(where: { $0.id == id })?.isOriginal != false)
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { store.requestDelete(id: id) }
                    .disabled(!store.canDelete(id: id))
            }
        }
        .onDeleteCommand { store.requestDelete(id: store.selection) }
        .onKeyPress(keys: [.delete, KeyEquivalent("\u{8}")], phases: .down) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            store.requestDelete(id: store.selection)
            return .handled
        }
        .onKeyPress(keys: [.return], phases: .down) { press in
            guard press.modifiers.isEmpty, store.selected?.isOriginal == false else { return .ignored }
            store.requestRename(id: store.selection)
            return .handled
        }
    }
}
