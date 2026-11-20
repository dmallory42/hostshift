import Foundation
import HostsCore

@main
enum HostshiftMain {
    static func main() {
        guard CLI.isInvocation(CommandLine.arguments) else {
            HostshiftApp.main()
            return
        }
        runFromRealPath()
        Task { @MainActor in
            exit(await CLI.run(Array(CommandLine.arguments.dropFirst()), context: .live))
        }
        dispatchMain()
    }

    /// Links such as /opt/homebrew/bin/hostshift point into the app bundle. Running from the resolved path
    /// lets Foundation find the bundle, its version and its helper. argv[0] is kept, so `hs` stays `hs`.
    private static func runFromRealPath() {
        if getenv("HOSTSHIFT_RESOLVED") != nil {
            unsetenv("HOSTSHIFT_RESOLVED")
            return
        }
        var size = UInt32(PATH_MAX)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0,
              let resolved = realpath(buffer, nil) else { return }
        defer { free(resolved) }
        guard strcmp(buffer, resolved) != 0 else { return }
        setenv("HOSTSHIFT_RESOLVED", "1", 1)
        execv(resolved, CommandLine.unsafeArgv)
        // If exec fails, carry on from the link. Only the version and system-access status depend on the bundle.
    }
}

extension CLIContext {
    static var live: CLIContext {
        CLIContext(
            library: .standard,
            hostsURL: URL(fileURLWithPath: "/etc/hosts"),
            install: { try await HostsInstaller().apply(content: $0, expected: $1) },
            systemAccess: { await MainActor.run { CLISystemAccess(SystemAccess()) } },
            isInteractive: isatty(STDIN_FILENO) != 0 && isatty(STDERR_FILENO) != 0,
            readLine: { Swift.readLine() },
            readInput: { try FileHandle.standardInput.readToEnd() ?? Data() },
            write: { FileHandle.standardOutput.write(Data($0.utf8)) },
            writeError: { FileHandle.standardError.write(Data($0.utf8)) },
            edit: runEditor
        )
    }

    /// Runs the editor through the shell, as git does, so EDITOR can include arguments such as `code --wait`.
    private static func runEditor(_ file: URL) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exec ${VISUAL:-${EDITOR:-vi}} \"$1\"", "hostshift-edit", file.path]
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do { try process.run() } catch { continuation.resume(returning: false) }
        }
    }
}

extension CLISystemAccess {
    @MainActor init(_ access: SystemAccess) {
        if access.isReady { self = .ready }
        else if access.requiresRestart { self = .needsReenabling }
        else if access.needsApproval { self = .needsApproval }
        else if access.isLocalBuild && access.errorMessage != nil { self = .unavailable }
        else { self = .notEnabled }
    }
}
