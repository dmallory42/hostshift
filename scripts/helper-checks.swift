import Foundation
import HostsCore

@main
struct HelperChecks {
    static func main() async throws {
        let helper = HelperService()
        let invalid: String? = await withCheckedContinuation { continuation in
            helper.apply(content: "not-an-ip example.test", expected: "") { message, error in
                precondition(message == nil)
                continuation.resume(returning: error)
            }
        }
        precondition(invalid?.contains("Line 1") == true)
        print("PASS: Helper rejects malformed requests independently of UI")
        let oversized: String? = await withCheckedContinuation { continuation in
            helper.apply(content: "127.0.0.1 localhost", expected: String(repeating: "x", count: 1_048_577)) { message, error in
                precondition(message == nil)
                continuation.resume(returning: error)
            }
        }
        precondition(oversized?.contains("too large") == true)
        print("PASS: Helper bounds incoming expected content")

        let listener = NSXPCListener.anonymous()
        let requirement = "identifier \"invalid.hostshift.test-client\""
        let delegate = HelperDelegate(requirement: requirement)
        listener.delegate = delegate
        listener.setConnectionCodeSigningRequirement(requirement)
        listener.resume()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.resume()
        let rejected: Bool = await withCheckedContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable _ in
                continuation.resume(returning: true)
            } as! HelperProtocol
            proxy.apply(content: "invalid", expected: "") { _, _ in continuation.resume(returning: false) }
        }
        precondition(rejected)
        connection.invalidate()
        listener.invalidate()
        withExtendedLifetime(delegate) {}
        print("PASS: XPC rejects a client whose signing identity does not match")
        let allowedRequirement = try CodeIdentity.ownRequirement()
        let allowedListener = NSXPCListener.anonymous()
        let allowedDelegate = HelperDelegate(requirement: allowedRequirement, allowedUser: getuid())
        allowedListener.delegate = allowedDelegate
        allowedListener.setConnectionCodeSigningRequirement(allowedRequirement)
        allowedListener.resume()
        let allowedConnection = NSXPCConnection(listenerEndpoint: allowedListener.endpoint)
        allowedConnection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        allowedConnection.resume()
        let accepted: Bool = await withCheckedContinuation { continuation in
            let proxy = allowedConnection.remoteObjectProxyWithErrorHandler { @Sendable _ in
                continuation.resume(returning: false)
            } as! HelperProtocol
            proxy.apply(content: "invalid", expected: "") { _, error in
                continuation.resume(returning: error?.contains("Line 1") == true)
            }
        }
        precondition(accepted)
        allowedConnection.invalidate()
        allowedListener.invalidate()
        withExtendedLifetime(allowedDelegate) {}
        print("PASS: XPC accepts the pinned local build and reaches helper validation")
        try checkLocalSetup(requirement: allowedRequirement)
        print("8 helper checks passed. No privileged operations were performed.")
    }
    static func checkLocalSetup(requirement: String) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "hostshift-setup-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fakeLaunchctl = directory.appending(path: "launchctl")
        try "#!/bin/sh\n[ \"$1\" != print ]\n".write(to: fakeLaunchctl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeLaunchctl.path)
        let fakeStat = directory.appending(path: "stat")
        try "#!/bin/sh\necho 0\n".write(to: fakeStat, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeStat.path)
        let registration = LocalRegistration(clientRequirement: requirement, helperRequirement: requirement, userID: getuid())
        let executable = directory.appending(path: "helper ' $(touch untrusted) `.bin")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[0]), to: executable)
        let shell = try LocalSetupScript.install(helperURL: executable, registration: registration)
        func run(_ script: String) throws -> Int32 {
            let isolated = script
                .replacing("/Library/", with: directory.path + "/Library/")
                .replacing("/usr/sbin/chown root:wheel", with: "/usr/bin/true")
                .replacing("/usr/bin/stat -f %u", with: LocalSetupScript.quote(fakeStat.path))
                .replacing("/bin/launchctl", with: LocalSetupScript.quote(fakeLaunchctl.path))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", isolated]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
        let installed = try run(shell)
        precondition(installed == 0)
        let saved = try JSONDecoder().decode(LocalRegistration.self, from: Data(contentsOf: directory.appending(path: String(LocalRegistration.path.dropFirst()))))
        precondition(saved == registration)
        print("PASS: Local setup installs pinned identities and user ID")
        let copied = directory.appending(path: String(LocalRegistration.executable.dropFirst()))
        let copiedRequirement = try CodeIdentity.requirement(at: copied)
        precondition(copiedRequirement == requirement)
        print("PASS: Installed helper retains the required signature, including a quoted source path")
        var wrongIdentity = registration
        wrongIdentity.helperRequirement = "identifier \"invalid.hostshift.helper\""
        let rejectedScript = try LocalSetupScript.install(helperURL: executable, registration: wrongIdentity)
        let rejectedInstall = try run(rejectedScript)
        precondition(rejectedInstall != 0)
        let preserved = try JSONDecoder().decode(LocalRegistration.self, from: Data(contentsOf: directory.appending(path: String(LocalRegistration.path.dropFirst()))))
        precondition(preserved == registration)
        print("PASS: A mismatched helper signature stops setup before replacing registration")
        let scriptURL = directory.appending(path: "setup.applescript")
        try LocalSetupScript.appleScript(shell).write(to: scriptURL, atomically: true, encoding: .utf8)
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        compiler.arguments = ["-o", directory.appending(path: "setup.scpt").path, scriptURL.path]
        try compiler.run()
        compiler.waitUntilExit()
        precondition(compiler.terminationStatus == 0)
        let removed = try run(LocalSetupScript.uninstall)
        precondition(removed == 0)
        precondition(!FileManager.default.fileExists(atPath: copied.path))
        print("PASS: Setup AppleScript compiles and removal cleans up the isolated helper")
    }

}
