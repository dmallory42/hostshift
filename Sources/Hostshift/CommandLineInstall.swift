import Foundation

/// Finds the `hostshift` and `hs` links in the usual command folders. The app can't see the user's
/// shell PATH, so it checks the folders Homebrew and the documented commands use.
struct CommandLineLink: Equatable {
    enum State: Equatable { case thisApp, other, broken }
    var path: String
    var state: State
}

enum CommandLineInstall {
    static var folders: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/bin"]
    }

    static func links(named name: String, in folders: [String] = folders, executable: URL) -> [CommandLineLink] {
        let target = resolved(executable.path)
        return folders.compactMap { folder in
            let path = folder + "/" + name
            var info = stat()
            guard lstat(path, &info) == 0 else { return nil }
            guard let destination = resolved(path) else { return CommandLineLink(path: path, state: .broken) }
            return CommandLineLink(path: path, state: destination == target ? .thisApp : .other)
        }
    }

    /// Terminal commands that link `hostshift`, and `hs` when asked, to this app in /usr/local/bin.
    /// The `hs` link uses plain `ln -s`, which refuses to replace a command that already exists.
    static func installCommands(executable: URL, includeAlias: Bool) -> String {
        let source = quoted(executable.path)
        var lines = ["sudo mkdir -p /usr/local/bin", "sudo ln -sf \(source) /usr/local/bin/hostshift"]
        if includeAlias { lines.append("sudo ln -s \(source) /usr/local/bin/hs") }
        return lines.joined(separator: "\n")
    }

    private static func resolved(_ path: String) -> String? {
        guard let pointer = realpath(path, nil) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacing("'", with: "'\\''") + "'"
    }
}
