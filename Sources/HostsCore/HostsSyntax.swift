import Foundation

public enum HostsSyntax {
    public enum Kind: Sendable { case address, hostname, comment }

    public struct Token: Sendable {
        public let range: NSRange
        public let kind: Kind
    }

    public static func tokens(in content: String) -> [Token] {
        let text = content as NSString
        var tokens: [Token] = []
        for line in HostsLines.ranges(in: content) {
            let comment = text.range(of: "#", range: line)
            let entryEnd = comment.location == NSNotFound ? NSMaxRange(line) : comment.location
            var position = line.location
            var firstField = true
            while position < entryEnd {
                let remaining = NSRange(location: position, length: entryEnd - position)
                let start = text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted, range: remaining)
                guard start.location != NSNotFound else { break }
                let tail = NSRange(location: start.location, length: entryEnd - start.location)
                let space = text.rangeOfCharacter(from: .whitespacesAndNewlines, range: tail)
                let end = space.location == NSNotFound ? entryEnd : space.location
                tokens.append(Token(range: NSRange(location: start.location, length: end - start.location),
                                    kind: firstField ? .address : .hostname))
                firstField = false
                position = end
            }
            if comment.location != NSNotFound {
                tokens.append(Token(range: NSRange(location: comment.location, length: NSMaxRange(line) - comment.location), kind: .comment))
            }
        }
        return tokens
    }
}
