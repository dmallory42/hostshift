import Foundation
import HostsCore

final class HelperService: NSObject, HelperProtocol {
    private let lock = NSLock()

    func apply(content: String, expected: String, reply: @escaping @Sendable (String?, String?) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard expected.utf8.count <= 1_048_576 else { reply(nil, "The current hosts file is too large."); return }
        let issues = HostsValidator.issues(in: content)
        guard issues.isEmpty else { reply(nil, issues.joined(separator: "\n")); return }
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", HostsInstallScript.shell(content: content, expected: expected)]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus == 0 { reply(message, nil) }
            else { reply(nil, message.isEmpty ? "The hosts file could not be updated." : message) }
        } catch { reply(nil, error.localizedDescription) }
    }
}
