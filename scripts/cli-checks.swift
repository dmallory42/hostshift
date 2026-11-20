import Foundation
import HostsCore

/// Stands in for the terminal, the helper and the editor. Nothing here touches /etc/hosts or the real library.
final class Harness: @unchecked Sendable {
    private let lock = NSLock()
    let folder: URL
    let hosts: URL
    let library: ProfileLibraryFile
    var access = CLISystemAccess.ready
    var interactive = false
    var answers: [String] = []
    var input = Data()
    var installs = 0
    var editorChange: (@Sendable (URL) -> Void)?
    /// Pretends stdout and stderr are a terminal that allows colour.
    var styled = false
    private(set) var output = ""
    private(set) var errors = ""

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "hostshift-cli-checks-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        hosts = folder.appending(path: "hosts")
        library = ProfileLibraryFile(url: folder.appending(path: "library/profiles.json"))
    }

    func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    var context: CLIContext {
        CLIContext(
            library: library, hostsURL: hosts,
            install: { content, _ in
                self.locked { self.installs += 1 }
                try content.write(to: self.hosts, atomically: true, encoding: .utf8)
                return "Activated."
            },
            systemAccess: { self.locked { self.access } },
            isInteractive: interactive,
            readLine: { self.locked { self.answers.isEmpty ? nil : self.answers.removeFirst() } },
            readInput: { self.locked { self.input } },
            write: { text in self.locked { self.output += text } },
            writeError: { text in self.locked { self.errors += text } },
            edit: { file in
                self.editorChange?(file)
                return true
            },
            outputStyle: CLIStyle(isEnabled: styled),
            errorStyle: CLIStyle(isEnabled: styled))
    }

    /// Runs one command and returns its exit code, with output and errors from that run only.
    func run(_ arguments: String...) async -> Int32 {
        locked { output = ""; errors = "" }
        return await CLI.run(arguments, context: context)
    }

    func hostsContent() throws -> String { try String(contentsOf: hosts, encoding: .utf8) }
    func saved() throws -> ProfileLibrary { try library.load()!.library }
    func profile(_ name: String) throws -> Profile? { try saved().profiles.first { $0.name == name } }
    func json() throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(output.utf8)) as! [String: Any] }
    func errorJSON() throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(errors.utf8)) as! [String: Any] }
}

@main struct CLIChecks {
    static func main() async throws {
        let h = try Harness()
        defer { try? FileManager.default.removeItem(at: h.folder) }
        var count = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ description: String) throws {
            guard try condition() else { fatalError("FAIL: \(description)\nstdout: \(h.output)\nstderr: \(h.errors)") }
            count += 1
            print("PASS: \(description)")
        }
        let original = "##\n# Host Database\n127.0.0.1\tlocalhost\n"
        try original.write(to: h.hosts, atomically: true, encoding: .utf8)

        try check(CLI.isInvocation(["/opt/homebrew/bin/hostshift"]) && CLI.isInvocation(["/usr/local/bin/hs", "list"]), "Links named hostshift or hs run the tool")
        try check(CLI.isInvocation(["/Applications/Hostshift.app/Contents/MacOS/Hostshift", "list"]) && CLI.isInvocation(["Hostshift", "--help"]), "The app executable runs the tool when given a command")
        try check(!CLI.isInvocation(["/Applications/Hostshift.app/Contents/MacOS/Hostshift"]) && !CLI.isInvocation(["Hostshift", "-NSDocumentRevisionsDebugMode", "YES"]), "The app starts normally without a command")

        // Reading
        var code = await h.run("list", "--json")
        let firstList = try h.json()["profiles"] as! [[String: Any]]
        try check(code == 0 && firstList.count == 1 && firstList[0]["name"] as? String == "Original" && firstList[0]["isActive"] as? Bool == true && firstList[0]["isOriginal"] as? Bool == true, "First use creates Original from the hosts file, as the app's first launch does")
        code = await h.run("status", "--json")
        let status = try h.json()
        try check(code == 0 && status["hosts"] as? String == "matches" && status["systemAccess"] as? String == "ready" && status["externalChanges"] as? Bool == false, "status reports the active profile and system access")
        code = await h.run("show", "original")
        try check(code == 0 && h.output == original, "show prints content exactly, found by a case-insensitive name")

        // Creating
        let literal = "# keep\tthis\r\n10.0.0.1\tapi.test   alias.test # note\r\n\n"
        h.input = Data(literal.utf8)
        code = await h.run("new", "API", "--from", "-")
        try check(code == 0 && (try h.profile("API"))?.content == literal, "new --from - keeps tabs, spaces, CRLF and comments exactly")
        code = await h.run("new", "API")
        try check(code == 1 && (try h.saved()).profiles.filter { $0.name == "API" }.count == 1, "A typed name already in use is refused, not renumbered")
        code = await h.run("new", "Blank", "--json")
        let blank = try h.json()
        try check(code == 0 && (try h.profile("Blank"))?.content == original && (blank["profile"] as? [String: Any])?["name"] as? String == "Blank", "new without --from starts from Original")
        code = await h.run("duplicate", "API")
        code = await h.run("duplicate", "API")
        try check(code == 0 && (try h.profile("Copy of API"))?.content == literal && (try h.profile("Copy of API (2)")) != nil, "Copies are named Copy of … and numbered")
        try "127.0.0.1 docker.test\n".write(to: h.hosts, atomically: true, encoding: .utf8)
        code = await h.run("capture")
        try check(code == 0 && (try h.profile("Copy of /etc/hosts"))?.content == "127.0.0.1 docker.test\n", "capture saves the current hosts file")
        try original.write(to: h.hosts, atomically: true, encoding: .utf8)

        // Choosing profiles
        code = await h.run("new", "api")
        code = await h.run("show", "API")
        try check(code == 0 && h.output == literal, "An exact name wins over a case-insensitive match")
        code = await h.run("show", "Api")
        try check(code == 1 && h.errors.contains("--id"), "An ambiguous case-insensitive name lists IDs to choose from")
        let api = try h.profile("API")!
        code = await h.run("show", "--id", String(api.id.uuidString.prefix(6)))
        try check(code == 0 && h.output == literal, "--id accepts an ID prefix")
        code = await h.run("show", "API", "--id", String(api.id.uuidString.prefix(6)))
        try check(code == 2, "A name and --id together are a usage error")

        // Renaming and replacing content
        code = await h.run("rename", "api", "Lower")
        try check(code == 0 && (try h.profile("Lower")) != nil, "rename renames a profile")
        code = await h.run("rename", "--id", String(api.id.uuidString.prefix(8)), " API v2 ")
        try check(code == 0 && (try h.saved()).profiles.first { $0.id == api.id }?.name == "API v2", "rename --id takes the new name as its only argument, trimmed")
        code = await h.run("rename", "Lower", "API v2")
        try check(code == 1 && (try h.profile("Lower")) != nil, "Renaming to a name in use is refused")
        let setFile = h.folder.appending(path: "set.hosts")
        try "127.0.0.1 set.test\n".write(to: setFile, atomically: true, encoding: .utf8)
        code = await h.run("set", "Lower", "--from", setFile.path)
        try check(code == 0 && (try h.profile("Lower"))?.content == "127.0.0.1 set.test\n", "set replaces a profile's content")
        code = await h.run("set", "Original", "--from", setFile.path)
        code = code == 0 ? 0 : await h.run("rename", "Original", "Mine")
        try check(code == 1 && (try h.saved()).profiles.first(where: \.isOriginal)?.content == original && (try h.profile("Original")) != nil, "Original can't be changed or renamed")
        try String(repeating: "#", count: 96_001).write(to: setFile, atomically: true, encoding: .utf8)
        code = await h.run("set", "Lower", "--from", setFile.path)
        try check(code == 1 && (try h.profile("Lower"))?.content == "127.0.0.1 set.test\n", "Content over 96 KB is refused")

        // Validating
        h.input = Data("# fine\nnot-an-ip broken.test\n".utf8)
        code = await h.run("new", "Broken", "--from", "-")
        try check(code == 0 && h.errors.contains("Line 2"), "A profile with problems is saved with a warning, as in the app")
        code = await h.run("validate", "Broken", "--json")
        let diagnostics = try h.json()
        let first = (diagnostics["diagnostics"] as? [[String: Any]])?.first
        try check(code == 5 && diagnostics["valid"] as? Bool == false && first?["line"] as? Int == 2 && h.errors.isEmpty, "validate exits with 5 and reports line numbers, with nothing extra on stderr")
        code = await h.run("validate", "API v2")
        try check(code == 0 && h.output.contains("No problems"), "validate passes a valid profile")

        // Activating
        code = await h.run("activate", "Broken")
        try check(code == 5 && h.installs == 0 && (try h.hostsContent()) == original, "An invalid profile is not installed")
        h.access = .notEnabled
        code = await h.run("activate", "API v2", "--json")
        try check(code == 4 && (try h.errorJSON())["code"] as? Int == 4 && h.installs == 0, "Activation without system access exits with 4 and a JSON error")
        h.access = .ready
        code = await h.run("activate", "API v2", "--json")
        let activated = try h.json()
        try check(code == 0 && (try h.hostsContent()) == literal && activated["changed"] as? Bool == true && activated["warning"] is NSNull, "activate installs the profile")
        try check((try h.saved()).preferredActiveID == api.id && (try h.saved()).lastActivatedDigest == HostsInstallScript.digest(literal), "activate records the activation for the app")
        code = await h.run("activate", "API v2", "--json")
        try check(code == 0 && (try h.json())["changed"] as? Bool == false && h.installs == 1, "Activating the active profile does nothing")
        code = await h.run("status")
        try check(h.output.hasPrefix("Active: API v2"), "status names the active profile")

        // External changes
        try "127.0.0.1 manual.test\n".write(to: h.hosts, atomically: true, encoding: .utf8)
        code = await h.run("activate", "Lower")
        try check(code == 3 && h.errors.contains("--save-current") && (try h.hostsContent()) == "127.0.0.1 manual.test\n", "Without a terminal, external changes stop activation with code 3")
        code = await h.run("activate", "Lower", "--save-current")
        try check(code == 0 && (try h.hostsContent()) == "127.0.0.1 set.test\n" && (try h.saved()).profiles.contains { $0.content == "127.0.0.1 manual.test\n" && $0.name == "Copy of /etc/hosts (2)" }, "--save-current keeps external changes as a profile")
        try "127.0.0.1 manual2.test\n".write(to: h.hosts, atomically: true, encoding: .utf8)
        code = await h.run("activate", "Lower", "--replace", "--save-current")
        try check(code == 2, "--replace and --save-current together are a usage error")
        code = await h.run("activate", "API v2", "--replace")
        try check(code == 0 && (try h.hostsContent()) == literal && !(try h.saved()).profiles.contains { $0.content == "127.0.0.1 manual2.test\n" }, "--replace discards external changes")
        h.interactive = true
        try "127.0.0.1 manual3.test\n".write(to: h.hosts, atomically: true, encoding: .utf8)
        h.answers = ["maybe", ""]
        code = await h.run("activate", "Lower")
        try check(code == 1 && (try h.hostsContent()) == "127.0.0.1 manual3.test\n" && h.errors.contains("[s/r/C]"), "In a terminal, the default answer cancels and unclear answers ask again")
        h.answers = ["s"]
        code = await h.run("activate", "Lower")
        try check(code == 0 && (try h.hostsContent()) == "127.0.0.1 set.test\n" && (try h.saved()).profiles.contains { $0.content == "127.0.0.1 manual3.test\n" }, "In a terminal, answering s saves external changes first")

        // Deleting
        code = await h.run("delete", "Lower", "--yes")
        try check(code == 1 && (try h.profile("Lower")) != nil, "The active profile can't be deleted")
        code = await h.run("delete", "Original", "--yes")
        try check(code == 1 && (try h.profile("Original")) != nil, "Original can't be deleted")
        h.answers = ["n"]
        code = await h.run("delete", "Blank")
        try check(code == 1 && (try h.profile("Blank")) != nil, "Declining the confirmation keeps the profile")
        h.answers = ["y"]
        code = await h.run("delete", "Blank")
        try check(code == 0 && (try h.profile("Blank")) == nil, "Confirming deletes the profile")
        h.interactive = false
        code = await h.run("delete", "Copy of API (2)")
        try check(code == 3 && (try h.profile("Copy of API (2)")) != nil, "Without a terminal, delete needs --yes")
        code = await h.run("delete", "Copy of API (2)", "--yes", "--json")
        try check(code == 0 && (try h.profile("Copy of API (2)")) == nil, "delete --yes deletes without asking")

        // Editing
        code = await h.run("edit", "Copy of API")
        try check(code == 2, "edit needs a terminal")
        h.interactive = true
        h.editorChange = { file in try? "127.0.0.1 edited.test\n".write(to: file, atomically: true, encoding: .utf8) }
        code = await h.run("edit", "Copy of API")
        try check(code == 0 && (try h.profile("Copy of API"))?.content == "127.0.0.1 edited.test\n", "edit saves what the editor wrote")
        h.editorChange = nil
        code = await h.run("edit", "Copy of API")
        try check(code == 0 && h.errors.contains("--wait"), "An unchanged file saves nothing and mentions editors that need to wait")
        h.editorChange = { file in try? "broken\n".write(to: file, atomically: true, encoding: .utf8) }
        h.answers = ["d"]
        code = await h.run("edit", "Copy of API")
        try check(code == 0 && (try h.profile("Copy of API"))?.content == "127.0.0.1 edited.test\n", "Discarding invalid edits keeps the saved content")
        h.answers = ["s"]
        code = await h.run("edit", "Copy of API")
        try check(code == 0 && (try h.profile("Copy of API"))?.content == "broken\n", "Invalid edits can be saved anyway")
        h.editorChange = { file in try? "127.0.0.1 activated.test\n".write(to: file, atomically: true, encoding: .utf8) }
        code = await h.run("edit", "Copy of API", "--activate")
        try check(code == 0 && (try h.hostsContent()) == "127.0.0.1 activated.test\n", "edit --activate saves and activates")
        code = await h.run("edit", "Original")
        try check(code == 1 && (try h.saved()).profiles.first(where: \.isOriginal)?.content == original, "Original can't be edited")
        h.interactive = false
        h.editorChange = nil

        // Export, help and usage
        let exported = h.folder.appending(path: "api.hosts")
        code = await h.run("export", "API v2", "-o", exported.path)
        try check(code == 0 && (try Data(contentsOf: exported)) == Data(literal.utf8), "export -o writes the exact bytes")
        code = await h.run("export", "API v2")
        try check(code == 0 && h.output == literal, "export without a file writes to stdout")
        code = await h.run("--help")
        try check(code == 0 && h.output.contains("Exit codes") && h.errors.isEmpty, "--help explains the tool and its exit codes on stdout")
        code = await h.run("frobnicate")
        try check(code == 2 && h.output.isEmpty && !h.errors.isEmpty, "Unknown commands are usage errors")
        code = await h.run("show", "Missing", "--json")
        let missing = try h.errorJSON()
        try check(code == 1 && missing["code"] as? Int == 1 && (missing["error"] as? String)?.contains("Missing") == true && h.output.isEmpty, "--json errors are JSON on stderr")

        code = await h.run("---completion", "show", "--", "positional@0", "1", "0", "hs", "show", "")
        try check(code == 0 && h.output.split(separator: "\n").contains("API v2"), "Shell completion suggests profile names")

        // Terminal styling
        try check(CLIStyle.allowsColour([:]) && CLIStyle.allowsColour(["NO_COLOR": ""]), "Colour is allowed by default and when NO_COLOR is empty")
        try check(!CLIStyle.allowsColour(["NO_COLOR": "1"]) && !CLIStyle.allowsColour(["TERM": "dumb"]), "NO_COLOR and TERM=dumb turn colour off")
        let t = try Harness()
        defer { try? FileManager.default.removeItem(at: t.folder) }
        try original.write(to: t.hosts, atomically: true, encoding: .utf8)
        _ = await t.run("list")
        try check(t.output == "* Original  (active, read-only)\n", "Without a terminal, list prints the plain format")
        _ = await t.run("status")
        let plainStatus = t.output
        t.styled = true
        let escape = "\u{1B}["
        code = await t.run("list")
        try check(code == 0 && t.output.contains("✓") && t.output.contains(escape) && t.output.contains("active · read-only"), "At a terminal, list marks the active profile with a check and colour")
        code = await t.run("status")
        try check(code == 0 && t.output.contains("is active") && t.output.contains("System access") && t.output != plainStatus, "At a terminal, status uses the column layout")
        code = await t.run("list", "--json")
        try check(code == 0 && !t.output.contains(escape) && (try? JSONSerialization.jsonObject(with: Data(t.output.utf8))) != nil, "--json output is never styled")
        code = await t.run("show", "Nope", "--json")
        try check(code == 1 && !t.errors.contains(escape) && (try t.errorJSON())["code"] as? Int == 1, "--json errors are never styled")
        code = await t.run("show", "Nope")
        try check(code == 1 && t.errors.hasPrefix("\(escape)31m✗") && t.errors.contains("Profiles:") && t.errors.contains("Original"), "At a terminal, errors start with a red cross and list the profiles on one line")
        t.input = Data("127.0.0.1 ok.test\nx\u{1B}]0;title\u{07}\n".utf8)
        code = await t.run("validate", "--file", "-")
        try check(code == 5 && t.output.contains("1 problem blocks activation") && t.output.contains("2 │"), "At a terminal, validate shows each problem under its line")
        try check(t.output.contains("x␛]0;title␇") && !t.output.contains("\u{1B}]0;"), "Control characters in profile text are shown as symbols, never sent to the terminal")
        t.input = Data("127.0.0.1 styled.test\n".utf8)
        code = await t.run("new", "Styled", "--from", "-")
        try check(code == 0 && t.output.contains("Created") && t.output.contains("✓"), "At a terminal, saves confirm with a check")
        code = await t.run("activate", "Styled")
        try check(code == 0 && t.output.contains("Activated") && (try String(contentsOf: t.hosts, encoding: .utf8)) == "127.0.0.1 styled.test\n", "At a terminal, activate confirms with a check")
        try "127.0.0.1 manual.test\n".write(to: t.hosts, atomically: true, encoding: .utf8)
        code = await t.run("activate", "Original")
        try check(code == 3 && t.errors.contains("!") && t.errors.contains("--save-current"), "A needed decision is marked as a warning, not a failure")

        let bin = h.folder.appending(path: "bin")
        let other = h.folder.appending(path: "other")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let app = h.folder.appending(path: "Hostshift")
        try Data().write(to: app)
        try Data().write(to: other.appending(path: "hs"))
        try FileManager.default.createSymbolicLink(atPath: bin.path + "/hostshift", withDestinationPath: app.path)
        try FileManager.default.createSymbolicLink(atPath: bin.path + "/hs", withDestinationPath: h.folder.path + "/missing")
        let folders = [bin.path, other.path, h.folder.path + "/absent"]
        try check(CommandLineInstall.links(named: "hostshift", in: folders, executable: app) == [CommandLineLink(path: bin.path + "/hostshift", state: .thisApp)], "Settings finds a hostshift link to this app")
        try check(CommandLineInstall.links(named: "hs", in: folders, executable: app).map(\.state) == [.broken, .other], "Settings reports broken links and an hs that belongs to another program")
        let commands = CommandLineInstall.installCommands(executable: URL(fileURLWithPath: "/Applications/It's Hostshift.app/Contents/MacOS/Hostshift"), includeAlias: true)
        try check(commands.contains("ln -sf '/Applications/It'\\''s Hostshift.app/Contents/MacOS/Hostshift' /usr/local/bin/hostshift") && commands.contains("sudo ln -s '"), "Install commands quote the app path and never replace an existing hs")
        try check(!CommandLineInstall.installCommands(executable: app, includeAlias: false).contains("/hs"), "The hs line is left out when the name is taken")
        print("\(count) CLI checks passed. /etc/hosts was not modified.")
    }
}
