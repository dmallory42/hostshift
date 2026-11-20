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
        check(HostsValidator.diagnostics(in: "# comment\rinvalid").map(\.line) == [1, 2], "A lone CR is flagged and later errors match editor line numbers")
        check(!HostsValidator.issues(in: "127.0.0.1 a.test\u{2028}127.0.0.2 b.test\n").isEmpty, "Reject line breaks macOS does not recognise")
        check(!HostsValidator.issues(in: "127.0.0.1\u{A0}example.test").isEmpty && !HostsValidator.issues(in: "127.0.0.1 a.test\u{0C}b.test").isEmpty, "Only spaces and tabs separate fields")
        check(HostsValidator.issues(in: "127.0.0.1 a.test\r\n::1\tb.test\n# \u{A0}note\u{3000}\n").isEmpty, "CRLF, tabs and unusual whitespace in comments stay valid")
        let original = "127.0.0.1 localhost\n::1 localhost\n"
        var library = ProfileLibrary(original: original)
        let duplicate = Profile(name: "Work", content: original)
        library.profiles.append(duplicate)
        library.preferredActiveID = duplicate.id
        check(library.activeID(matching: original) == duplicate.id, "Only one identical profile is active")
        check(library.activeID(matching: "# external\n") == nil, "External modifications clear active status")
        check(!library.hasExternalChanges(in: original), "A saved profile's content is not an external change")
        check(library.hasExternalChanges(in: "# external\n"), "Unsaved content from another app is an external change")
        var edited = library
        edited.lastActivatedDigest = HostsInstallScript.digest("127.0.0.1 before-save.test\n")
        check(!edited.hasExternalChanges(in: "127.0.0.1 before-save.test\n"), "Saving edits to the active profile is not an external change")
        check(!ProfileLibrary(original: "# first launch\n").hasExternalChanges(in: "# first launch\n"), "First launch has no external changes")
        let folder = FileManager.default.temporaryDirectory.appending(path: "hostshift-checks-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "library/profiles.json")
        try library.save(to: url)
        let loaded = try ProfileLibrary.load(from: url)
        check(loaded.profiles == library.profiles, "Profile persistence preserves exact content")
        check(loaded.preferredActiveID == duplicate.id, "Preferred active profile survives restart")
        check(loaded.lastActivatedDigest == library.lastActivatedDigest, "Last activation survives restart")
        var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        legacy["lastActivatedDigest"] = nil
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        let legacyLibrary = try ProfileLibrary.load(from: url)
        check(legacyLibrary.lastActivatedDigest == nil && legacyLibrary.profiles == library.profiles, "Libraries saved before activation tracking still load")
        try Data("broken".utf8).write(to: url)
        do { _ = try ProfileLibrary.load(from: url); fatalError("Corrupt library accepted") }
        catch { check(true, "Corrupt library reported without overwriting") }

        check(ProfileLibrary.uniqueName("Work", among: ["Work", "Work (2)"]) == "Work (3)" && ProfileLibrary.uniqueName("New", among: []) == "New", "Generated names skip names in use")
        check(ProfileLibrary.normalizedName("  Dev \n") == "Dev" && ProfileLibrary.normalizedName(" \t") == nil, "Typed names are trimmed and must not be empty")
        var rules = ProfileLibrary(original: original)
        let originalProfile = rules.profiles[0]
        var changedOriginal = originalProfile
        changedOriginal.content = "# changed\n"
        check((try? rules.upsert(changedOriginal)) == nil && (try? rules.upsert(originalProfile)) != nil && rules.profiles == [originalProfile], "Original can't be replaced, and saving it unchanged is allowed")
        check((try? rules.upsert(Profile(name: "Fake", content: "", isOriginal: true))) == nil, "A second Original can't be added")
        check((try? rules.rename(id: originalProfile.id, to: "Changed")) == nil && (try? rules.remove(id: originalProfile.id, systemContent: "# other\n")) == nil, "Original can't be renamed or deleted")
        let work = rules.add(name: "Work", content: "127.0.0.1 work.test\n", reservedNames: ["Work"])
        check(work.name == "Work (2)", "Reserved names, such as unsaved drafts, are skipped")
        check((try? rules.rename(id: work.id, to: "  ")) == nil && (try? rules.rename(id: work.id, to: " Work ")) != nil && rules.profiles.last?.name == "Work", "Renames are trimmed and empty names refused")
        check((try? rules.remove(id: work.id, systemContent: work.content)) == nil && rules.profiles.count == 2, "The active profile can't be deleted")
        check((try? rules.remove(id: work.id, systemContent: original)) != nil && rules.profiles == [originalProfile], "Inactive profiles can be deleted")
        check((try? rules.remove(id: work.id, systemContent: original)) == nil, "Deleting a missing profile reports it")

        let file = ProfileLibraryFile(url: folder.appending(path: "shared/profiles.json"))
        check((try? file.loadOrCreate(original: nil)) == nil && !file.exists, "No library is created until the hosts file can be read")
        let created = try file.loadOrCreate(original: original)
        let again = try file.loadOrCreate(original: "# later\n")
        check(created?.library.profiles.map(\.content) == [original] && again?.library == created?.library, "First launch creates Original once and never replaces it")
        let before = file.stamp()
        DispatchQueue.concurrentPerform(iterations: 24) { index in
            _ = try? file.update { _ = $0.add(name: "Concurrent \(index)", content: "") }
        }
        let concurrent = try file.load()!
        check(concurrent.library.profiles.count == 25 && Set(concurrent.library.profiles.map(\.name)).count == 25, "Concurrent updates each keep the others' changes")
        check(before != concurrent.stamp && concurrent.stamp == file.stamp(), "Saving changes the file's stamp")
        let unchanged = try Data(contentsOf: file.url)
        _ = try? file.update { library in
            library.profiles.removeAll()
            throw ProfileLibraryError.notFound
        }
        let afterThrow = try Data(contentsOf: file.url)
        check(afterThrow == unchanged, "A change that throws writes nothing")

        // Run the actual install shell against an isolated directory. Only the fixed
        // target, root ownership and DNS operations are substituted for this check.
        let target = folder.appending(path: "hosts")
        let canary = folder.appending(path: "injected")
        let payload = "# ' \" $(touch \(canary.path)) `id` \\ café\n127.0.0.1 example.test\n"
        try original.write(to: target, atomically: true, encoding: .utf8)
        func runInstall(content: String = payload, expected: String, dnsRefresh: String = "/usr/bin/true") throws -> (Int32, String) {
            let script = HostsInstallScript.shell(content: content, expected: expected)
                .replacing("/private/etc/", with: folder.path + "/")
                .replacing("/usr/sbin/chown root:wheel", with: "/usr/bin/true")
                .replacing("/usr/bin/dscacheutil -flushcache", with: "/usr/bin/true")
                .replacing("/usr/bin/killall -HUP mDNSResponder", with: dnsRefresh)
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
        check(!FileManager.default.fileExists(atPath: canary.path), "Profile text is never run as a shell command")
        let backupURL = folder.appending(path: "hosts.hostshift-backup")
        let backup = try String(contentsOf: backupURL, encoding: .utf8)
        check(backup == original, "Backup preserves prior hosts")
        let conflict = try runInstall(expected: original)
        check(conflict.0 != 0 && conflict.1.contains("changed outside"), "Reject stale system content")
        let afterConflict = try String(contentsOf: target, encoding: .utf8)
        check(afterConflict == payload, "Conflict leaves hosts unchanged")
        let backupAfterConflict = try String(contentsOf: backupURL, encoding: .utf8)
        check(backupAfterConflict == original, "Conflict leaves backup unchanged")
        let second = "127.0.0.1 second.test\n"
        let switched = try runInstall(content: second, expected: payload)
        check(switched.0 == 0, "Second switch succeeds: \(switched.1)")
        let latestBackup = try String(contentsOf: backupURL, encoding: .utf8)
        check(latestBackup == payload, "Backup holds the file the latest switch replaced")
        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.contains("hostshift-backup") }
        check(backups == ["hosts.hostshift-backup"], "Only one backup is kept")
        let dnsFailure = try runInstall(content: payload, expected: second, dnsRefresh: "/usr/bin/false")
        check(dnsFailure.0 == 0 && dnsFailure.1.trimmingCharacters(in: .whitespacesAndNewlines) == HostsInstallScript.dnsRefreshFailed, "DNS refresh failure still activates and reports the warning the app shows")
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: backupURL)
        let symlink = try runInstall(expected: original)
        check(symlink.0 != 0, "Reject symlink target")
        print("\(count) checks passed. /etc/hosts was not modified.")
    }
}
