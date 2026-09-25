import Foundation

public enum HostsLines {
    public static func ranges(in content: String) -> [NSRange] {
        let text = content as NSString
        var ranges: [NSRange] = []
        var position = 0
        while position < text.length {
            var end = 0
            var contentsEnd = 0
            text.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: position, length: 0))
            ranges.append(NSRange(location: position, length: contentsEnd - position))
            position = end
            if end == text.length && contentsEnd < end {
                ranges.append(NSRange(location: end, length: 0))
            }
        }
        return ranges.isEmpty ? [NSRange(location: 0, length: 0)] : ranges
    }
}
