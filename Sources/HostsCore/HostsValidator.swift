import Foundation
import Darwin

public enum HostsValidator {
    public static func issues(in content: String) -> [String] {
        diagnostics(in: content).map(\.description)
    }

    public static func diagnostics(in content: String) -> [HostsDiagnostic] {
        var issues: [HostsDiagnostic] = []
        if content.utf8.count > 96_000 {
            issues.append(HostsDiagnostic(line: nil, message: "Keep profiles under 96 KB."))
        }
        if content.contains("\0") { issues.append(HostsDiagnostic(line: nil, message: "Remove null characters.")) }
        for (index, range) in HostsLines.ranges(in: content).enumerated() {
            let line = (content as NSString).substring(with: range)
            let entry = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let fields = entry.split(whereSeparator: { $0.isWhitespace })
            guard !fields.isEmpty else { continue }
            var ipv4 = in_addr()
            var ipv6 = in6_addr()
            let address = String(fields[0])
            let validIP = address.withCString {
                inet_pton(AF_INET, $0, &ipv4) == 1 || inet_pton(AF_INET6, $0, &ipv6) == 1
            }
            if !validIP || fields.count < 2 {
                issues.append(HostsDiagnostic(line: index + 1, message: "use an IPv4 or IPv6 address followed by a hostname."))
                continue
            }
            for host in fields.dropFirst() {
                let name = host.hasSuffix(".") ? host.dropLast() : host[...]
                let labels = name.split(separator: ".", omittingEmptySubsequences: false)
                let valid = name.utf8.count <= 253 && labels.allSatisfy { label in
                    !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
                    label.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
                }
                if !valid { issues.append(HostsDiagnostic(line: index + 1, message: "“\(host)” is not a valid hostname. Use ASCII or punycode names.")) }
            }
        }
        return issues
    }
}
