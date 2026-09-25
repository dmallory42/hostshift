import SwiftUI
import HostsCore

struct HostsTextEditor: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    var lineSelection: EditorLineSelection? = nil

    func makeCoordinator() -> HostsTextCoordinator {
        HostsTextCoordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let editor = scroll.documentView as? NSTextView else { return scroll }
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        editor.inlinePredictionType = .no
        editor.smartInsertDeleteEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        if #available(macOS 15.0, *) {
            editor.writingToolsBehavior = .none
            editor.mathExpressionCompletionType = .no
        }
        editor.usesFindBar = true
        HostsTextFormatting.configure(editor)
        editor.textColor = .textColor
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.setAccessibilityLabel("Hosts file contents")
        scroll.verticalRulerView = LineNumberRuler(scrollView: scroll, editor: editor)
        scroll.hasVerticalRuler = true
        scroll.hasHorizontalRuler = false
        scroll.rulersVisible = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        editor.isEditable = isEditable
        if editor.string != text {
            editor.string = text
            HostsSyntaxHighlighter.apply(to: editor)
            (scroll.verticalRulerView as? LineNumberRuler)?.updateLines()
        }
        if let request = lineSelection, context.coordinator.lastLineSelection != request.id {
            context.coordinator.lastLineSelection = request.id
            context.coordinator.selectLine(request.line, in: editor)
        }
    }
}
