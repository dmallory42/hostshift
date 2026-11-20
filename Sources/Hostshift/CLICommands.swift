import ArgumentParser
import Foundation
import HostsCore

struct HostshiftCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hostshift",
        abstract: "Switch /etc/hosts between saved profiles.",
        discussion: """
            Hostshift keeps hosts profiles and activates one by replacing the whole /etc/hosts file \
            through its privileged helper. The Hostshift app uses the same profiles, so changes made \
            here appear there. Original is the read-only snapshot of /etc/hosts from first launch.

            Choose a profile by its exact name, a unique case-insensitive name, or --id with the \
            start of its ID from `hostshift list --json`.

            For scripts and agents: pass --json for machine-readable output, and errors are then \
            written to stderr as {"error": ..., "code": ...}. Without a terminal the tool never \
            prompts. A command that needs a decision exits with code 3 and names the flag to pass.

            Exit codes: 0 success, 1 error, 2 usage error, 3 needs a decision, 4 system access not \
            ready, 5 profile invalid.

            Reference: https://github.com/dmallory42/hostshift/blob/main/docs/cli.md
            """,
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
        subcommands: [StatusCommand.self, ListCommand.self, ShowCommand.self, ActivateCommand.self, NewCommand.self,
                      DuplicateCommand.self, CaptureCommand.self, RenameCommand.self, SetCommand.self, EditCommand.self,
                      ExportCommand.self, DeleteCommand.self, ValidateCommand.self]
    )
}

struct JSONOutput: ParsableArguments {
    @Flag(help: "Print machine-readable JSON.") var json = false
}

struct ProfileArgument: ParsableArguments {
    @Argument(help: "The profile's name.", completion: .custom { _, _, _ in profileNames() })
    var name: String?

    @Option(help: ArgumentHelp("Choose the profile by the start of its ID instead of its name.", valueName: "id-prefix"))
    var id: String?

    func validate() throws {
        if name == nil && id == nil { throw ValidationError("Name a profile, or pass --id.") }
    }

    func find(in library: ProfileLibrary) throws -> Profile {
        if name != nil && id != nil { throw CLIError(.usage, "Pass a profile name or --id, not both.") }
        return try findProfile(name: name, id: id, in: library)
    }
}

private func profileNames() -> [String] {
    let file = CLIContext.current?.library ?? .standard
    return ((try? file.load())?.library.profiles ?? []).map(\.name)
}

// MARK: - Reading

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status", abstract: "Show the active profile and whether system access is ready.")
    @OptionGroup var output: JSONOutput

    struct Result: Encodable {
        var active: ProfileSummary?
        var hosts: String
        var externalChanges: Bool
        var systemAccess: CLISystemAccess

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(active, forKey: .active)
            try container.encode(hosts, forKey: .hosts)
            try container.encode(externalChanges, forKey: .externalChanges)
            try container.encode(systemAccess, forKey: .systemAccess)
        }
        enum CodingKeys: String, CodingKey { case active, hosts, externalChanges, systemAccess }
    }

    func run() async throws {
        let context = CLIContext.active
        let library = try context.loadLibrary()
        let hosts = try? context.readHosts()
        let access = await context.systemAccess()
        let activeID = hosts.flatMap { library.activeID(matching: $0) }
        let active = library.profiles.first { $0.id == activeID }
        let state = hosts == nil ? "unreadable" : active == nil ? "differs" : "matches"
        if output.json {
            try writeJSON(Result(active: active.map { ProfileSummary($0, activeID: activeID) }, hosts: state,
                                 externalChanges: hosts.map(library.hasExternalChanges) ?? false, systemAccess: access))
            return
        }
        let style = context.outputStyle
        guard style.isEnabled else {
            if let active { context.writeLine("Active: \(active.displayName)") }
            else if hosts == nil { context.writeLine("Can’t read \(context.hostsURL.path).") }
            else { context.writeLine("/etc/hosts doesn’t match any saved profile.") }
            context.writeLine("System access: \(access.description)")
            return
        }
        let width = "System access".count + 3
        if let active {
            context.writeLine("\(style.success) \(style.bold(visible(active.displayName))) is active")
            context.writeLine("  \(style.column("/etc/hosts", width: width))matches \(visible(active.displayName))")
        } else if let hosts {
            context.writeLine("\(style.warning) \(style.bold("No profile is active"))")
            let state = library.hasExternalChanges(in: hosts) ? "changed outside Hostshift" : "doesn’t match any saved profile"
            context.writeLine("  \(style.column("/etc/hosts", width: width))\(style.yellow(state))")
        } else {
            context.writeLine("\(style.failure) \(style.bold("Can’t read \(context.hostsURL.path)"))")
        }
        let accessState = access == .ready ? style.green(access.state) : style.yellow(access.state)
        context.writeLine("  \(style.column("System access", width: width))\(accessState)")
        if let hint = access.hint { context.writeLine("  \(style.dim(hint))") }
    }
}

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "List profiles, marking the active one and Original.")
    @OptionGroup var output: JSONOutput

    func run() async throws {
        let context = CLIContext.active
        let library = try context.loadLibrary()
        let active = activeID(in: library)
        if output.json {
            try writeJSON(["profiles": library.profiles.map { ProfileSummary($0, activeID: active) }])
            return
        }
        let style = context.outputStyle
        let width = library.profiles.map { visible($0.displayName).count }.max() ?? 0
        for profile in library.profiles {
            let tags = [profile.id == active ? "active" : nil, profile.isOriginal ? "read-only" : nil].compactMap(\.self)
            guard style.isEnabled else {
                context.writeLine((profile.id == active ? "* " : "  ") + profile.displayName + (tags.isEmpty ? "" : "  (\(tags.joined(separator: ", ")))"))
                continue
            }
            let name = visible(profile.displayName)
            let mark = profile.id == active ? style.success : " "
            let shown = profile.id == active ? style.bold(name) : name
            let padding = String(repeating: " ", count: width - name.count + 3)
            context.writeLine("\(mark) \(shown)" + (tags.isEmpty ? "" : padding + style.dim(tags.joined(separator: " · "))))
        }
    }
}

struct ShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show", abstract: "Print a profile's content exactly as saved.")
    @OptionGroup var profile: ProfileArgument
    @OptionGroup var output: JSONOutput

    struct Result: Encodable {
        var profile: ProfileSummary
        var content: String
    }

    func run() async throws {
        let library = try CLIContext.active.loadLibrary()
        let target = try profile.find(in: library)
        if output.json {
            try writeJSON(Result(profile: ProfileSummary(target, activeID: activeID(in: library)), content: target.content))
        } else {
            CLIContext.active.write(target.content)
        }
    }
}

struct ValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Check a profile or file for entries that would block activation.",
        discussion: "Exits with code 5 when there are problems.")
    @Argument(help: "The profile's name.", completion: .custom { _, _, _ in profileNames() }) var name: String?
    @Option(help: ArgumentHelp("Choose the profile by the start of its ID instead of its name.", valueName: "id-prefix")) var id: String?
    @Option(help: ArgumentHelp("Check a file instead of a profile. Use - for stdin.", valueName: "path"), completion: .file()) var file: String?
    @OptionGroup var output: JSONOutput

    struct Result: Encodable {
        var valid: Bool
        var diagnostics: [DiagnosticOutput]
    }

    func validate() throws {
        if [name != nil, id != nil, file != nil].filter(\.self).count != 1 {
            throw ValidationError("Name a profile, or pass --id or --file.")
        }
    }

    func run() async throws {
        let context = CLIContext.active
        let content = if let file { try readProfileContent(from: file) }
            else { try findProfile(name: name, id: id, in: context.loadLibrary()).content }
        let diagnostics = diagnosticsOutput(content)
        if output.json {
            try writeJSON(Result(valid: diagnostics.isEmpty, diagnostics: diagnostics))
        } else if context.outputStyle.isEnabled {
            let style = context.outputStyle
            context.writeLine(diagnostics.isEmpty ? "\(style.success) No problems found."
                              : styledProblems(in: content, style: style, symbol: style.failure))
        } else if diagnostics.isEmpty {
            context.writeLine("No problems found.")
        } else {
            context.writeLine(HostsValidator.issues(in: content).joined(separator: "\n"))
        }
        if !diagnostics.isEmpty { throw CLIError(.invalid, "") }
    }
}

// MARK: - Activating

struct ActivateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activate",
        abstract: "Replace /etc/hosts with a profile.",
        discussion: """
            If /etc/hosts has changes that aren't saved in any profile, Hostshift asks whether to save \
            them as a profile first or replace them. Without a terminal, pass --save-current or \
            --replace, otherwise the command exits with code 3 and /etc/hosts is not changed. \
            Activating the profile that's already active does nothing.
            """)
    @OptionGroup var profile: ProfileArgument
    @Flag(help: "Discard changes to /etc/hosts that aren't saved in any profile.") var replace = false
    @Flag(help: "Save changes to /etc/hosts that aren't saved in any profile as a new profile first.") var saveCurrent = false
    @OptionGroup var output: JSONOutput

    func validate() throws {
        if replace && saveCurrent { throw ValidationError("Pass --replace or --save-current, not both.") }
    }

    func run() async throws {
        let library = try CLIContext.active.loadLibrary()
        try await activateProfile(profile.find(in: library), replace: replace, saveCurrent: saveCurrent, json: output.json)
    }
}

struct ActivationResult: Encodable {
    var profile: ProfileSummary
    var changed: Bool
    var warning: String?

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profile, forKey: .profile)
        try container.encode(changed, forKey: .changed)
        try container.encode(warning, forKey: .warning)
    }
    enum CodingKeys: String, CodingKey { case profile, changed, warning }
}

func activateProfile(_ target: Profile, replace: Bool, saveCurrent: Bool, json: Bool) async throws {
    let context = CLIContext.active
    let issues = HostsValidator.issues(in: target.content)
    guard issues.isEmpty else {
        let style = context.errorStyle
        if style.isEnabled {
            let heading = "\(visible(target.displayName)) can’t be activated. \(problemCount(issues.count))."
            throw CLIError(.invalid, styledProblems(in: target.content, style: style, symbol: style.failure, heading: heading), isFormatted: true)
        }
        throw CLIError(.invalid, "“\(target.displayName)” can’t be activated:\n" + issues.joined(separator: "\n"))
    }
    let hosts = try context.readHosts()
    let library = try context.loadLibrary()
    if library.activeID(matching: hosts) == target.id {
        if json { try writeJSON(ActivationResult(profile: ProfileSummary(target, activeID: target.id), changed: false)) }
        else if context.outputStyle.isEnabled {
            context.writeLine("\(context.outputStyle.success) \(context.outputStyle.bold(visible(target.displayName))) is already active.")
        } else { context.writeLine("“\(target.displayName)” is already active.") }
        return
    }
    let access = await context.systemAccess()
    guard access == .ready else { throw CLIError(.systemAccess, "System access is \(access.description).") }
    let decided: ExternalChangeChoice? = replace ? .replace : saveCurrent ? .saveAsProfile : nil
    if decided == nil && !context.isInteractive && library.hasExternalChanges(in: hosts) { throw needsDecision }
    let activation = ProfileActivation(library: context.library, hostsURL: context.hostsURL, install: context.install)
    let warning: String?
    do {
        warning = try await activation.run(target) { _ in
            if let decided { return decided }
            return context.isInteractive ? askAboutExternalChanges() : .cancel
        }
    } catch .cancelled {
        if decided == nil && !context.isInteractive { throw needsDecision }
        throw CLIError(.failure, "Cancelled. /etc/hosts was not changed.")
    } catch .invalid(let issues) {
        throw CLIError(.invalid, issues.joined(separator: "\n"))
    } catch {
        throw CLIError(.failure, error.localizedDescription)
    }
    if json {
        try writeJSON(ActivationResult(profile: ProfileSummary(target, activeID: target.id), changed: true, warning: warning))
    } else {
        if context.outputStyle.isEnabled {
            context.writeLine("\(context.outputStyle.success) Activated \(context.outputStyle.bold(visible(target.displayName))).")
        } else {
            context.writeLine("Activated “\(target.displayName)”.")
        }
        if let warning { context.warn(context.errorStyle.isEnabled ? "\(context.errorStyle.warning) \(warning)" : warning) }
    }
}

private var needsDecision: CLIError {
    CLIError(.needsDecision, "/etc/hosts has changes that aren’t saved in any profile. Pass --save-current to save them as a profile first, or --replace to discard them.")
}

private func askAboutExternalChanges() -> ExternalChangeChoice {
    let context = CLIContext.active
    context.warn("/etc/hosts has changed outside Hostshift. Activating will replace those changes.")
    while true {
        switch context.ask("Save them as a profile first, replace them, or cancel? [s/r/C]") {
        case "s", "save": return .saveAsProfile
        case "r", "replace": return .replace
        case nil, "", "c", "cancel": return .cancel
        default: continue
        }
    }
}

// MARK: - Changing profiles

struct ProfileResult: Encodable {
    var profile: ProfileSummary
    var diagnostics: [DiagnosticOutput]
}

/// Reports a created or changed profile. Problems don't stop a save, as in the app, but they block activation.
private func report(_ verb: String, _ profile: Profile, in library: ProfileLibrary, json: Bool) throws {
    let context = CLIContext.active
    let diagnostics = diagnosticsOutput(profile.content)
    if json {
        try writeJSON(ProfileResult(profile: ProfileSummary(profile, activeID: activeID(in: library)), diagnostics: diagnostics))
        return
    }
    context.writeLine(done(verb, profile))
    guard !diagnostics.isEmpty else { return }
    if context.errorStyle.isEnabled {
        context.warn(styledProblems(in: profile.content, style: context.errorStyle, symbol: context.errorStyle.warning))
    } else {
        context.warn("It has problems that block activation:\n" + HostsValidator.issues(in: profile.content).joined(separator: "\n"))
    }
}

/// “Created “API”.” in plain output, or a check mark and the name in bold at a terminal.
private func done(_ verb: String, _ profile: Profile) -> String {
    let style = CLIContext.active.outputStyle
    guard style.isEnabled else { return "\(verb) “\(profile.displayName)”." }
    return "\(style.success) \(verb) \(style.bold(visible(profile.displayName)))."
}

/// Typed names are kept exactly, so a name already in use is refused instead of numbered.
private func requireUnusedName(_ name: String, in library: ProfileLibrary, except id: UUID? = nil) throws {
    if library.profiles.contains(where: { $0.name == name && $0.id != id }) {
        throw CLIError(.failure, "A profile named “\(name)” already exists.")
    }
}

struct NewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Create a profile.",
        discussion: "Without --from, the profile starts with Original's content.")
    @Argument(help: "The new profile's name.") var name: String
    @Option(help: ArgumentHelp("Read the content from a file. Use - for stdin.", valueName: "path"), completion: .file()) var from: String?
    @OptionGroup var output: JSONOutput

    func run() async throws {
        let context = CLIContext.active
        guard let name = ProfileLibrary.normalizedName(name) else { throw CLIError(.usage, ProfileLibraryError.emptyName.localizedDescription) }
        let content = try from.map(readProfileContent)
        var created: Profile?
        let library = try context.update { library in
            try requireUnusedName(name, in: library)
            let profile = Profile(name: name, content: content ?? library.profiles.first(where: \.isOriginal)?.content ?? "")
            library.profiles.append(profile)
            created = profile
        }
        try report("Created", created!, in: library, json: output.json)
    }
}

struct DuplicateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "duplicate", abstract: "Copy a profile. The copy is named “Copy of …”.")
    @OptionGroup var profile: ProfileArgument
    @OptionGroup var output: JSONOutput

    func run() async throws {
        let context = CLIContext.active
        let source = try profile.find(in: context.loadLibrary())
        var created: Profile?
        let library = try context.update { created = $0.add(name: "Copy of \(source.displayName)", content: source.content) }
        try report("Created", created!, in: library, json: output.json)
    }
}

struct CaptureCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture", abstract: "Save the current /etc/hosts as a new profile.")
    @OptionGroup var output: JSONOutput

    func run() async throws {
        let context = CLIContext.active
        let hosts = try context.readHosts()
        var created: Profile?
        let library = try context.update { created = $0.add(name: ProfileLibrary.copyOfHostsName, content: hosts) }
        try report("Created", created!, in: library, json: output.json)
    }
}

struct RenameCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a profile.",
        usage: "hostshift rename <profile> <new-name>\nhostshift rename --id <id-prefix> <new-name>")
    @OptionGroup var profile: ProfileArgument
    @Argument(help: "The new name.") var newName: String?
    @OptionGroup var output: JSONOutput

    func run() async throws {
        let context = CLIContext.active
        // With --id, the only positional argument is the new name.
        let (selector, typed) = profile.id != nil && newName == nil ? (nil, profile.name) : (profile.name, newName)
        guard let typed else { throw CLIError(.usage, "Give the new name after the profile.") }
        guard let name = ProfileLibrary.normalizedName(typed) else { throw CLIError(.usage, ProfileLibraryError.emptyName.localizedDescription) }
        if selector != nil && profile.id != nil { throw CLIError(.usage, "Pass a profile name or --id, not both.") }
        let target = try findProfile(name: selector, id: profile.id, in: context.loadLibrary())
        let library = try context.update { library in
            try requireUnusedName(name, in: library, except: target.id)
            try library.rename(id: target.id, to: name)
        }
        try report("Renamed to", library.profiles.first { $0.id == target.id }!, in: library, json: output.json)
    }
}

struct SetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set", abstract: "Replace a profile's content and save it.")
    @OptionGroup var profile: ProfileArgument
    @Option(help: ArgumentHelp("Read the content from a file. Use - for stdin.", valueName: "path"), completion: .file()) var from: String
    @OptionGroup var output: JSONOutput

    func run() async throws {
        let context = CLIContext.active
        let target = try profile.find(in: context.loadLibrary())
        let content = try readProfileContent(from: from)
        let saved = try save(content, to: target.id)
        try report("Saved", saved.profile, in: saved.library, json: output.json)
    }
}

/// Saves new content for a profile, reading the latest saved version so other changes to it, like a rename, are kept.
private func save(_ content: String, to id: UUID) throws -> (profile: Profile, library: ProfileLibrary) {
    var saved: Profile?
    let library = try CLIContext.active.update { library in
        guard var profile = library.profiles.first(where: { $0.id == id }) else { throw ProfileLibraryError.notFound }
        profile.content = content
        try library.upsert(profile)
        saved = profile
    }
    return (saved!, library)
}

struct EditCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit a profile in $VISUAL or $EDITOR, then save it.",
        discussion: """
            Needs a terminal. Editors that open a window must wait until the file is closed, for \
            example EDITOR="code --wait". From a script, use `show` and `set --from` instead.
            """)
    @OptionGroup var profile: ProfileArgument
    @Flag(help: "Activate the profile after saving it.") var activate = false
    @OptionGroup var output: JSONOutput

    func run() async throws {
        let context = CLIContext.active
        guard context.isInteractive else {
            throw CLIError(.usage, "edit needs a terminal. From a script, use `hostshift show` and `hostshift set --from` instead.")
        }
        let target = try profile.find(in: context.loadLibrary())
        guard !target.isOriginal else { throw CLIError(.failure, "Original is read-only. Duplicate it to make an editable copy.") }
        let folder = FileManager.default.temporaryDirectory.appending(path: "hostshift-edit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: target.exportFileName)
        guard FileManager.default.createFile(atPath: file.path, contents: Data(target.content.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw CLIError(.failure, "Could not create a file to edit.")
        }
        var edited: String
        editing: while true {
            guard await context.edit(file) else { throw CLIError(.failure, "The editor exited with an error. Nothing was saved.") }
            edited = try readProfileContent(from: file.path)
            if edited == target.content {
                context.warn("No changes saved. If your editor returns straight away, set it to wait, for example EDITOR=\"code --wait\".")
                return
            }
            let issues = HostsValidator.issues(in: edited)
            if issues.isEmpty { break }
            context.warn(context.errorStyle.isEnabled
                         ? styledProblems(in: edited, style: context.errorStyle, symbol: context.errorStyle.warning) + "\n"
                         : issues.joined(separator: "\n"))
            while true {
                switch context.ask("Edit again, save anyway, or discard your changes? [E/s/d]") {
                case "", "e", "edit": continue editing
                case "s", "save": break editing
                case nil, "d", "discard":
                    context.warn("Discarded your changes.")
                    return
                default: continue
                }
            }
        }
        let saved = try save(edited, to: target.id)
        if activate {
            try await activateProfile(saved.profile, replace: false, saveCurrent: false, json: output.json)
        } else {
            try report("Saved", saved.profile, in: saved.library, json: output.json)
        }
    }
}

struct ExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export", abstract: "Write a profile's content to a file, or to stdout without one.")
    @OptionGroup var profile: ProfileArgument
    @Option(name: .shortAndLong, help: ArgumentHelp("The file to write. It is replaced if it exists.", valueName: "path"), completion: .file()) var output: String?

    func run() async throws {
        let context = CLIContext.active
        let target = try profile.find(in: context.loadLibrary())
        guard let output else { context.write(target.content); return }
        do { try Data(target.content.utf8).write(to: URL(fileURLWithPath: output), options: .atomic) }
        catch { throw CLIError(.failure, "Can’t write \(output): \(error.localizedDescription)") }
    }
}

struct DeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a profile.",
        discussion: "Original and the active profile can't be deleted. Without a terminal, pass --yes.")
    @OptionGroup var profile: ProfileArgument
    @Flag(name: .shortAndLong, help: "Delete without asking.") var yes = false
    @OptionGroup var output: JSONOutput

    func run() async throws {
        let context = CLIContext.active
        let library = try context.loadLibrary()
        let target = try profile.find(in: library)
        let hosts = try context.readHosts()
        var check = library
        do { try check.remove(id: target.id, systemContent: hosts) }
        catch { throw CLIError(.failure, error.localizedDescription) }
        if !yes {
            guard context.isInteractive else {
                throw CLIError(.needsDecision, "Pass --yes to delete “\(target.displayName)” without a terminal.")
            }
            guard ["y", "yes"].contains(context.ask("Delete “\(target.displayName)”? This can’t be undone. [y/N]") ?? "") else {
                throw CLIError(.failure, "Cancelled. Nothing was deleted.")
            }
        }
        try context.update { try $0.remove(id: target.id, systemContent: hosts) }
        if output.json { try writeJSON(["deleted": ProfileSummary(target, activeID: nil)]) }
        else { context.writeLine(done("Deleted", target)) }
    }
}
