import Foundation
import HostsCore

/// Colour and symbols for one output stream. When styling is off, the tool prints its plain format,
/// which is what pipes, NO_COLOR and --json get.
struct CLIStyle: Sendable {
    var isEnabled: Bool

    static let plain = CLIStyle(isEnabled: false)

    static func forStream(_ descriptor: Int32, environment: [String: String] = ProcessInfo.processInfo.environment) -> CLIStyle {
        CLIStyle(isEnabled: isatty(descriptor) != 0 && allowsColour(environment))
    }

    /// Follows the NO_COLOR convention (any non-empty value) and TERM=dumb.
    static func allowsColour(_ environment: [String: String]) -> Bool {
        (environment["NO_COLOR"] ?? "").isEmpty && environment["TERM"] != "dumb"
    }

    func bold(_ text: String) -> String { wrap("1", text) }
    func dim(_ text: String) -> String { wrap("2", text) }
    func green(_ text: String) -> String { wrap("32", text) }
    func yellow(_ text: String) -> String { wrap("33", text) }
    func red(_ text: String) -> String { wrap("31", text) }

    var success: String { green("✓") }
    var warning: String { yellow("!") }
    var failure: String { red("✗") }

    /// Pads text to a column width, measured before styling.
    func column(_ text: String, width: Int) -> String {
        dim(text + String(repeating: " ", count: max(0, width - text.count)))
    }

    private func wrap(_ code: String, _ text: String) -> String {
        isEnabled ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }
}

/// Replaces control characters with visible symbols, so profile text can't send terminal escape
/// sequences and unusual separators show up. Tabs are kept.
func visible(_ text: String) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.flatMap { scalar -> [Unicode.Scalar] in
        switch scalar.value {
        case 0x09: [scalar]
        case 0x00..<0x20: [Unicode.Scalar(0x2400 + scalar.value)!]
        case 0x7F: ["\u{2421}"]
        case 0x80..<0xA0, 0x2028, 0x2029: Array(String(format: "<U+%04X>", scalar.value).unicodeScalars)
        default: [scalar]
        }
    }))
}

func problemCount(_ count: Int) -> String {
    count == 1 ? "1 problem blocks activation" : "\(count) problems block activation"
}

/// Lists validation problems under the lines they're about, like a compiler error.
func styledProblems(in content: String, style: CLIStyle, symbol: String, heading: String? = nil) -> String {
    let diagnostics = HostsValidator.diagnostics(in: content)
    let text = content as NSString
    let ranges = HostsLines.ranges(in: content)
    let width = String(diagnostics.compactMap(\.line).max() ?? 0).count
    var lines = ["\(symbol) " + style.bold(heading ?? problemCount(diagnostics.count)), ""]
    for diagnostic in diagnostics {
        if let line = diagnostic.line, line >= 1, line <= ranges.count {
            let number = String(line)
            let gutter = String(repeating: " ", count: width - number.count) + number + " │"
            lines.append("  " + style.dim(gutter) + " " + visible(text.substring(with: ranges[line - 1])))
            lines.append("  " + String(repeating: " ", count: width + 3) + style.red(diagnostic.message))
        } else {
            lines.append("  " + style.red(diagnostic.message))
        }
    }
    return lines.joined(separator: "\n")
}
