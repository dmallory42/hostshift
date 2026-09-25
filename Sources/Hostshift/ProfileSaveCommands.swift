import SwiftUI

struct ProfileSaveCommands: Commands {
    let store: ProfileStore

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save") { store.saveSelected() }
                .keyboardShortcut("s")
                .disabled(store.isApplying || !store.isUnsaved(id: store.selection))
            Button("Save All") { store.saveAll() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(store.isApplying || !store.hasUnsavedChanges)
        }
    }
}
