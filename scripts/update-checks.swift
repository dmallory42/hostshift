import Foundation
import HostsCore

@main struct UpdateChecks {
    static func main() throws {
        precondition(ReleaseVersion("1.0") == ReleaseVersion("v1.0.0"))
        precondition(ReleaseVersion("1.10")! > ReleaseVersion("1.9")!)
        precondition(ReleaseVersion("2.0")! > ReleaseVersion("1.99")!)
        precondition(["", "1..2", "1.0-beta", "v", "1.-1", "1.9999999999999999999999999999"].allSatisfy { ReleaseVersion($0) == nil })
        print("PASS version comparison handles numeric ordering, equivalent versions and malformed tags")
        func release(tag: String = "v1.1", url: String = "https://github.com/example/hostshift/releases/tag/v1.1", draft: Bool = false, prerelease: Bool = false) throws -> AppRelease {
            let data = try JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": url, "draft": draft, "prerelease": prerelease])
            return try JSONDecoder().decode(AppRelease.self, from: data)
        }
        let newer = try release().isNewer(than: "1.0", repository: "example/hostshift")
        let same = try release(tag: "1.0").isNewer(than: "1.0", repository: "example/hostshift")
        let older = try release(tag: "0.9").isNewer(than: "1.0", repository: "example/hostshift")
        precondition(newer && !same && !older)
        print("PASS only newer releases are offered")
        for invalid in [try release(draft: true), try release(prerelease: true), try release(tag: "latest"), try release(url: "https://example.com/download"), try release(url: "http://github.com/example/hostshift/releases/tag/v1.1"), try release(url: "https://github.com/other/app/releases/tag/v1.1")] {
            do {
                _ = try invalid.isNewer(than: "1.0", repository: "example/hostshift")
                fatalError("Invalid release accepted")
            } catch {}
        }
        precondition(!AppRelease.validRepository("../hostshift"))
        precondition(!AppRelease.validRepository("example/hostshift?token=x"))
        precondition(AppRelease.validRepository("example/hostshift"))
        print("PASS drafts, prereleases, invalid metadata and unexpected download destinations are rejected")
    }
}
