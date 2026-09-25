import AppKit
import HostsCore

@MainActor
enum HostsSyntaxHighlighter {
    static func apply(to editor: NSTextView) {
        guard let layout = editor.layoutManager else { return }
        let range = NSRange(location: 0, length: (editor.string as NSString).length)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        for token in HostsSyntax.tokens(in: editor.string) {
            let color: NSColor
            switch token.kind {
            case .address: color = .systemPurple
            case .hostname: color = .systemBlue
            case .comment: color = .secondaryLabelColor
            }
            layout.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: token.range)
        }
    }
}
