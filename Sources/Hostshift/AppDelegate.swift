import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: ProfileStore?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        guard !store.isBusy else { return .terminateCancel }
        guard store.hasUnsavedChanges else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Save changes before quitting?"
        alert.informativeText = "Your profiles have unsaved changes. If you don’t save them, your changes will be lost."
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don’t Save")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return store.saveAll() ? .terminateNow : .terminateCancel
        case .alertThirdButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
