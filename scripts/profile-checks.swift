import Foundation
import HostsCore

@main @MainActor struct ProfileChecks {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "profiles.json")
        let store = ProfileStore(libraryURL: url)
        let original = store.profiles[0]
        store.add(name: "First", content: "127.0.0.1 first.test\n")
        let first = store.selected!
        precondition(store.saveSelected())
        store.add(name: "Second", content: "127.0.0.1 second.test\n")
        let second = store.selected!
        precondition(store.saveSelected())
        store.duplicate(id: first.id)
        precondition(store.selected?.content == first.content && store.selected?.name == "First Copy")
        print("PASS duplicate targets clicked profile, not selection")
        store.duplicate(id: first.id)
        precondition(store.selected?.name == "First Copy (2)")
        store.add()
        store.add()
        precondition(store.profiles.suffix(2).map(\.name) == ["New Profile", "New Profile (2)"])
        store.add(name: "First")
        precondition(store.selected?.name == "First (2)")
        print("PASS new, duplicated and imported profiles get numbered names instead of repeating one")
        store.rename(id: first.id, name: " Renamed ")
        precondition(store.profiles.first { $0.id == first.id }?.name == "Renamed")
        precondition(store.profiles.first { $0.id == first.id }?.content == first.content)
        print("PASS rename preserves profile content and identity")
        store.rename(id: first.id, name: "  ")
        precondition(store.profiles.first { $0.id == first.id }?.name == "Renamed")
        store.rename(id: original.id, name: "Changed")
        store.delete(id: original.id)
        precondition(store.profiles[0] == original)
        print("PASS empty names and Original modifications rejected")
        store.requestDelete(id: first.id)
        precondition(store.profileToDelete?.id == first.id && store.showDeleteConfirmation)
        precondition(store.profiles.contains { $0.id == first.id })
        store.selection = second.id
        store.delete(id: store.profileToDelete!.id)
        precondition(!store.profiles.contains { $0.id == first.id })
        precondition(store.selection == second.id)
        print("PASS delete waits for confirmation and retains target after selection changes")
        let current = try String(contentsOfFile: "/etc/hosts", encoding: .utf8)
        store.add(name: "Active check", content: current)
        let active = store.selected!
        precondition(store.saveSelected())
        store.library?.preferredActiveID = active.id
        store.delete(id: active.id)
        precondition(store.profiles.contains { $0.id == active.id })
        print("PASS deletion rechecks and protects current active profile")
        let saved = try ProfileLibrary.load(from: url)
        precondition(!saved.profiles.contains { $0.id == first.id })
        print("PASS sidebar changes persisted to isolated library")
        store.selection = second.id
        var edited = second
        edited.content += "127.0.0.2 additional.test\n"
        store.stage(edited)
        precondition(store.isUnsaved(id: second.id))
        let beforeSave = try ProfileLibrary.load(from: url)
        precondition(beforeSave.profiles.first { $0.id == second.id } == second)
        store.selection = original.id
        store.selection = second.id
        precondition(store.selected == edited)
        print("PASS edits stay in memory across selection changes")
        store.stage(second)
        precondition(!store.isUnsaved(id: second.id))
        print("PASS returning to saved content clears unsaved state")
        store.stage(edited)
        store.add(name: "Unsaved new profile", content: "127.0.0.1 unsaved.test\n")
        let unsaved = store.selected!
        precondition(store.isUnsaved(id: unsaved.id))
        let beforeNewSave = try ProfileLibrary.load(from: url)
        precondition(!beforeNewSave.profiles.contains { $0.id == unsaved.id })
        precondition(!store.canApply(unsaved))
        store.selection = second.id
        precondition(store.saveSelected())
        let afterSave = try ProfileLibrary.load(from: url)
        precondition(afterSave.profiles.first { $0.id == second.id } == edited)
        precondition(!afterSave.profiles.contains { $0.id == unsaved.id })
        precondition(!store.isUnsaved(id: second.id) && store.isUnsaved(id: unsaved.id))
        print("PASS Save writes only selected profile, leaving other drafts unsaved")
        precondition(store.saveAll())
        precondition(!store.hasUnsavedChanges)
        let afterSaveAll = try ProfileLibrary.load(from: url)
        precondition(afterSaveAll.profiles.contains { $0.id == unsaved.id })
        print("PASS Save All persists all drafts")
        store.rename(id: second.id, name: "Unsaved Rename")
        precondition(store.isUnsaved(id: second.id))
        let beforeRenameSave = try ProfileLibrary.load(from: url)
        precondition(beforeRenameSave.profiles.first { $0.id == second.id }?.name == second.name)
        print("PASS renaming requires deliberate Save")
        let selectionBeforeCapture = store.selection
        precondition(store.saveExternalChanges("127.0.0.1 docker.test\n"))
        let captured = try ProfileLibrary.load(from: url).profiles.last!
        precondition(captured.name == "Copy of /etc/hosts" && captured.content == "127.0.0.1 docker.test\n")
        precondition(store.selection == selectionBeforeCapture && store.isUnsaved(id: second.id))
        print("PASS external changes save as a profile without saving drafts or changing selection")
        precondition(store.saveExternalChanges("127.0.0.1 second.docker.test\n"))
        precondition(store.saveExternalChanges("127.0.0.1 third.docker.test\n"))
        let copies = try ProfileLibrary.load(from: url).profiles.map(\.name).filter { $0.hasPrefix("Copy of /etc/hosts") }
        precondition(copies == ["Copy of /etc/hosts", "Copy of /etc/hosts (2)", "Copy of /etc/hosts (3)"])
        print("PASS repeated copies of /etc/hosts get numbered names")
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        precondition(!store.saveSelected())
        precondition(store.isUnsaved(id: second.id) && store.selected?.name == "Unsaved Rename")
        precondition(store.library?.profiles.first { $0.id == second.id }?.name == second.name)
        print("PASS failed save preserves draft and previously saved state")
    }
}
