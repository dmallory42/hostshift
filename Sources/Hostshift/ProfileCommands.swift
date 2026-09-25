import SwiftUI

struct ProfileCommands: Commands {
    let store: ProfileStore

    private var unavailable: Bool {
        !store.systemAccess.isReady || store.isApplying
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Profile") { store.add() }
                .keyboardShortcut("n")
                .disabled(unavailable || store.library == nil)
            Button("Duplicate") { store.duplicate() }
                .keyboardShortcut("d")
                .disabled(unavailable || store.selected == nil)
            Button("Rename…") { store.requestRename(id: store.selection) }
                .disabled(unavailable || store.selected?.isOriginal != false)
            Button("Delete Profile", role: .destructive) { store.requestDelete(id: store.selection) }
                .disabled(unavailable || !store.canDelete(id: store.selection))
            Divider()
            Button("Import Hosts File…") { store.importProfile() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(unavailable || store.library == nil)
            Button("Export Profile…") { store.exportProfile() }
                .disabled(unavailable || store.selected == nil)
        }
    }
}
