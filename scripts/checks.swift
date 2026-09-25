import Foundation
import HostsCore

@main
struct Checks {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) {
            guard condition() else { fatalError("FAIL: \(description)") }
            count += 1
            print("PASS: \(description)")
        }
        check(HostsValidator.issues(in: "# comment\n127.0.0.1 localhost alias.test # note\n::1 localhost\n").isEmpty, "IPv4, IPv6, aliases and comments")
        check(!HostsValidator.issues(in: "999.0.0.1 localhost").isEmpty, "Reject invalid IP")
        check(!HostsValidator.issues(in: "127.0.0.1").isEmpty, "Require hostname")
        check(!HostsValidator.issues(in: "127.0.0.1 https://example.com").isEmpty, "Reject URLs")
        check(!HostsValidator.issues(in: "127.0.0.1 -invalid.test").isEmpty, "Reject invalid hostname labels")
        check(!HostsValidator.issues(in: "127.0.0.1 local\0host").isEmpty, "Reject null bytes")
        check(!HostsValidator.issues(in: String(repeating: "#", count: 96_001)).isEmpty, "Bound privileged command size")
        check(HostsLines.ranges(in: "").count == 1, "Empty editor shows line one")
        check(HostsLines.ranges(in: "# comment\n\n").count == 3, "Blank and trailing lines are numbered")
        check(HostsLines.ranges(in: "# 😀\r\ninvalid").map(\.location) == [0, 6], "UTF-16 offsets and CRLF line boundaries")
        check(HostsValidator.issues(in: "# comment\r\ninvalid").first?.hasPrefix("Line 2:") == true, "CRLF errors match editor line numbers")
        check(HostsValidator.issues(in: "# comment\rinvalid").first?.hasPrefix("Line 2:") == true, "CR errors match editor line numbers")
        let original = "127.0.0.1 localhost\n::1 localhost\n"
        var library = ProfileLibrary(original: original)
        let duplicate = Profile(name: "Work", content: original)
        library.profiles.append(duplicate)
        library.preferredActiveID = duplicate.id
        check(library.activeID(matching: original) == duplicate.id, "Only one identical profile is active")
        check(library.activeID(matching: "# external\n") == nil, "External modifications clear active status")
        let folder = FileManager.default.temporaryDirectory.appending(path: "hostshift-checks-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "library/profiles.json")
        try library.save(to: url)
        let loaded = try ProfileLibrary.load(from: url)
        check(loaded.profiles == library.profiles, "Profile persistence preserves exact content")
        check(loaded.preferredActiveID == duplicate.id, "Preferred active profile survives restart")
        try Data("broken".utf8).write(to: url)
        do { _ = try ProfileLibrary.load(from: url); fatalError("Corrupt library accepted") }
        catch { check(true, "Corrupt library reported without overwriting") }

        // Run the actual install shell against an isolated directory. Only the fixed
        // target, root ownership and DNS operations are substituted for this check.
        let target = folder.appending(path: "hosts")
        let payload = "# ' \" $(touch /tmp/hostshift-injection) `id` \\ café\n127.0.0.1 example.test\n"
        try original.write(to: target, atomically: true, encoding: .utf8)
        func runInstall(expected: String) throws -> (Int32, String) {
            let script = HostsInstallScript.shell(content: payload, expected: expected)
                .replacing("/private/etc/", with: folder.path + "/")
                .replacing("/usr/sbin/chown root:wheel", with: "/usr/bin/true")
                .replacing("/usr/bin/dscacheutil -flushcache", with: "/usr/bin/true")
                .replacing("/usr/bin/killall -HUP mDNSResponder", with: "/usr/bin/true")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: output, as: UTF8.self))
        }
        let applied = try runInstall(expected: original)
        check(applied.0 == 0, "Install shell succeeds: \(applied.1)")
        let installed = try String(contentsOf: target, encoding: .utf8)
        check(installed == payload, "Shell metacharacters and Unicode round-trip literally")
        let backups = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("hosts.hostshift-backup.") }
        check(backups.count == 1, "Creates backup before replacement")
        let backup = try String(contentsOf: backups[0], encoding: .utf8)
        check(backup == original, "Backup preserves prior hosts")
        let conflict = try runInstall(expected: original)
        check(conflict.0 != 0 && conflict.1.contains("changed outside"), "Reject stale system content")
        let afterConflict = try String(contentsOf: target, encoding: .utf8)
        check(afterConflict == payload, "Conflict leaves hosts unchanged")
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: backups[0])
        let symlink = try runInstall(expected: original)
        check(symlink.0 != 0, "Reject symlink target")
        print("\(count) checks passed. /etc/hosts was not modified.")
    }
}
