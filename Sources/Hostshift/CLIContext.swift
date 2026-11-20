import Foundation
import HostsCore

/// Everything the command-line tool touches outside its own process. Checks substitute all of it.
struct CLIContext: Sendable {
    var library: ProfileLibraryFile
    var hostsURL: URL
    var install: ProfileActivation.Install
    var systemAccess: @Sendable () async -> CLISystemAccess
    /// True when stdin and stderr are a terminal, so the tool may ask questions.
    var isInteractive: Bool
    var readLine: @Sendable () -> String?
    var readInput: @Sendable () throws -> Data
    var write: @Sendable (String) -> Void
    var writeError: @Sendable (String) -> Void
    /// Opens a file in the user's editor and waits for it to close. Returns false if the editor failed.
    var edit: @Sendable (URL) async -> Bool
    /// Colour and symbols for stdout and stderr. Plain unless that stream is a terminal; always plain with --json.
    var outputStyle = CLIStyle.plain
    var errorStyle = CLIStyle.plain

    @TaskLocal static var current: CLIContext?

    static var active: CLIContext {
        guard let current else { fatalError("Commands run inside CLI.run, which sets the context.") }
        return current
    }

    func writeLine(_ text: String) { write(text + "\n") }
    func warn(_ text: String) { writeError(text + "\n") }

    /// Asks a question on stderr and returns the trimmed, lowercased answer.
    func ask(_ question: String) -> String? {
        writeError(question + " ")
        return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func readHosts() throws -> String {
        do { return try String(contentsOf: hostsURL, encoding: .utf8) }
        catch { throw CLIError(.failure, "Can’t read \(hostsURL.path): \(error.localizedDescription)") }
    }

    /// The saved library, creating it from the current hosts file on first use, as the app does on first launch.
    func loadLibrary() throws -> ProfileLibrary {
        do {
            if let snapshot = try library.load() { return snapshot.library }
            if let snapshot = try library.loadOrCreate(original: try readHosts()) { return snapshot.library }
        } catch let error as CLIError { throw error }
        catch { throw CLIError(.failure, "Could not open your profiles: \(error.localizedDescription)") }
        throw CLIError(.failure, "Could not open your profiles.")
    }

    @discardableResult
    func update(_ change: (inout ProfileLibrary) throws -> Void) throws -> ProfileLibrary {
        _ = try loadLibrary()
        do { return try library.update(change).library }
        catch let error as ProfileLibraryError { throw CLIError(.failure, error.localizedDescription) }
        catch { throw CLIError(.failure, "Could not save your profiles: \(error.localizedDescription)") }
    }
}

enum CLISystemAccess: String, Codable, Sendable {
    case ready, needsApproval, notEnabled, needsReenabling, unavailable

    var description: String {
        switch self {
        case .ready: "ready"
        case .needsApproval: "waiting for approval in System Settings → General → Login Items & Extensions"
        case .notEnabled: "not enabled. Open Hostshift and choose Enable System Access"
        case .needsReenabling: "this build changed. Open Hostshift and enable system access again"
        case .unavailable: "unavailable for this build"
        }
    }

    /// A short state for the status column, with what to do about it in `hint`.
    var state: String {
        switch self {
        case .ready: "ready"
        case .needsApproval: "waiting for approval"
        case .notEnabled: "not enabled"
        case .needsReenabling: "needs enabling again"
        case .unavailable: "unavailable for this build"
        }
    }

    var hint: String? {
        switch self {
        case .ready, .unavailable: nil
        case .needsApproval: "Approve Hostshift in System Settings → General → Login Items & Extensions."
        case .notEnabled: "Open Hostshift and choose Enable System Access."
        case .needsReenabling: "This build of Hostshift changed. Open it and enable system access again."
        }
    }
}

/// Exit codes are part of the tool's interface. Keep them in step with docs/cli.md.
enum CLIExitCode: Int32, Sendable {
    case success = 0
    case failure = 1
    case usage = 2
    case needsDecision = 3
    case systemAccess = 4
    case invalid = 5
}

struct CLIError: Error, CustomStringConvertible {
    var code: CLIExitCode
    var message: String
    /// The message already starts with its own symbol, so the runner prints it as it is.
    var isFormatted = false
    init(_ code: CLIExitCode, _ message: String, isFormatted: Bool = false) {
        self.code = code
        self.message = message
        self.isFormatted = isFormatted
    }
    var description: String { message }
}

/// Finds a profile by exact name, then by a unique case-insensitive name, or by a UUID prefix.
func findProfile(name: String?, id: String?, in library: ProfileLibrary) throws -> Profile {
    if let id {
        let prefix = id.lowercased()
        let matches = library.profiles.filter { $0.id.uuidString.lowercased().hasPrefix(prefix) }
        guard !prefix.isEmpty, !matches.isEmpty else { throw CLIError(.failure, "No profile has an ID starting with “\(id)”.") }
        guard matches.count == 1 else { throw ambiguous(matches) }
        return matches[0]
    }
    guard let name else { throw CLIError(.usage, "Name a profile, or pass --id.") }
    let exact = library.profiles.filter { $0.name == name }
    if exact.count == 1 { return exact[0] }
    if exact.count > 1 { throw ambiguous(exact) }
    let folded = library.profiles.filter { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
    if folded.count == 1 { return folded[0] }
    if folded.count > 1 { throw ambiguous(folded) }
    if let style = CLIContext.current?.errorStyle, style.isEnabled {
        let names = library.profiles.map { visible($0.displayName) }.joined(separator: ", ")
        throw CLIError(.failure, "No profile is named “\(visible(name))”.\n  \(style.dim("Profiles:")) \(names)")
    }
    let names = library.profiles.map { "  \($0.displayName)" }.joined(separator: "\n")
    throw CLIError(.failure, "No profile is named “\(name)”. Profiles:\n\(names)")
}

private func ambiguous(_ matches: [Profile]) -> CLIError {
    let list = matches.map { "  \($0.displayName)  --id \($0.id.uuidString.prefix(8).lowercased())" }.joined(separator: "\n")
    return CLIError(.failure, "More than one profile matches. Choose one with --id:\n\(list)")
}

/// Reads a profile's content from a file, or from stdin when the path is "-". Imports are limited to 96 KB, as in the app.
func readProfileContent(from path: String) throws -> String {
    let context = CLIContext.active
    let data: Data
    do {
        data = path == "-" ? try context.readInput() : try Data(contentsOf: URL(fileURLWithPath: path))
    } catch { throw CLIError(.failure, "Can’t read \(path == "-" ? "stdin" : path): \(error.localizedDescription)") }
    guard data.count <= 96_000 else { throw CLIError(.failure, "Keep profiles under 96 KB.") }
    guard let content = String(data: data, encoding: .utf8) else { throw CLIError(.failure, "Profiles must be UTF-8 text.") }
    return content
}

// MARK: - JSON output

struct ProfileSummary: Codable, Equatable {
    var id: String
    var name: String
    var isOriginal: Bool
    var isActive: Bool

    init(_ profile: Profile, activeID: UUID?) {
        id = profile.id.uuidString.lowercased()
        name = profile.name
        isOriginal = profile.isOriginal
        isActive = profile.id == activeID
    }
}

/// A line is null for problems with the whole file, such as its size.
struct DiagnosticOutput: Encodable, Equatable {
    var line: Int?
    var message: String

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(line, forKey: .line)
        try container.encode(message, forKey: .message)
    }
    enum CodingKeys: String, CodingKey { case line, message }
}

func diagnosticsOutput(_ content: String) -> [DiagnosticOutput] {
    HostsValidator.diagnostics(in: content).map { DiagnosticOutput(line: $0.line, message: $0.message) }
}

func writeJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    CLIContext.active.writeLine(String(decoding: data, as: UTF8.self))
}

/// The active profile's ID, or nil when the hosts file is unreadable or matches no saved profile.
func activeID(in library: ProfileLibrary) -> UUID? {
    (try? CLIContext.active.readHosts()).flatMap { library.activeID(matching: $0) }
}
