import Foundation

public struct AppRelease: Decodable, Sendable {
    public let tag_name: String
    public let html_url: URL
    public let draft: Bool
    public let prerelease: Bool

    public static func validRepository(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { part in
            !part.isEmpty && part != "." && part != ".." && part.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0))
            }
        }
    }

    public func isNewer(than current: String, repository: String) throws -> Bool {
        guard !draft, !prerelease, Self.validRepository(repository),
              let version = ReleaseVersion(tag_name), let installed = ReleaseVersion(current),
              html_url.scheme == "https", html_url.host == "github.com",
              html_url.user == nil, html_url.password == nil, html_url.port == nil,
              html_url.path.hasPrefix("/\(repository)/releases/tag/") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return version > installed
    }
}
