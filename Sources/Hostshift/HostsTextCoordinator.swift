import SwiftUI
import HostsCore

@MainActor
final class HostsTextCoordinator: NSObject, NSTextViewDelegate {
    var text: Binding<String>
    var lastLineSelection: UUID?

    init(text: Binding<String>) { self.text = text }

    func selectLine(_ line: Int, in editor: NSTextView) {
        let ranges = HostsLines.ranges(in: editor.string)
        guard line > 0, line <= ranges.count else { return }
        let range = ranges[line - 1]
        editor.window?.makeFirstResponder(editor)
        editor.setSelectedRange(range)
        editor.scrollRangeToVisible(range)
        editor.showFindIndicator(for: range)
    }

    func textDidChange(_ notification: Notification) {
        guard let editor = notification.object as? NSTextView else { return }
        HostsSyntaxHighlighter.apply(to: editor)
        text.wrappedValue = editor.string
    }
}
