import ArgumentParser
import Foundation

enum CLI {
    /// The command-line tool runs when the executable is invoked as `hostshift` or `hs`, which is how the
    /// installed links are named, or with a command. LaunchServices starts the app as `Hostshift` with
    /// no arguments, and Xcode passes only dash-prefixed ones.
    static func isInvocation(_ arguments: [String]) -> Bool {
        let name = URL(fileURLWithPath: arguments.first ?? "").lastPathComponent
        if name == "hostshift" || name == "hs" { return true }
        guard arguments.count > 1 else { return false }
        let first = arguments[1]
        return !first.hasPrefix("-") || ["-h", "--help", "--version", "--generate-completion-script"].contains(first)
            || first.hasPrefix("---completion")
    }

    /// Parses and runs one command, returning its exit code. Errors go to stderr, as JSON when --json was passed.
    static func run(_ arguments: [String], context: CLIContext) async -> Int32 {
        await CLIContext.$current.withValue(context) {
            let json = arguments.contains("--json")
            do {
                var command = try await HostshiftCommand.asyncParseAsRoot(arguments)
                if var command = command as? AsyncParsableCommand { try await command.run() }
                else { try command.run() }
                return CLIExitCode.success.rawValue
            } catch let error as CLIError {
                report(error.message, code: error.code, json: json)
                return error.code.rawValue
            } catch {
                let message = HostshiftCommand.fullMessage(for: error)
                switch HostshiftCommand.exitCode(for: error) {
                case .success:
                    if !message.isEmpty { context.writeLine(message) }
                    return CLIExitCode.success.rawValue
                case .validationFailure:
                    report(message, code: .usage, json: json)
                    return CLIExitCode.usage.rawValue
                default:
                    report(message, code: .failure, json: json)
                    return CLIExitCode.failure.rawValue
                }
            }
        }
    }

    private static func report(_ message: String, code: CLIExitCode, json: Bool) {
        let context = CLIContext.active
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let output = ErrorOutput(error: message.isEmpty ? "Failed." : message, code: code.rawValue)
            let data = (try? encoder.encode(output)) ?? Data()
            context.writeError(String(decoding: data, as: UTF8.self) + "\n")
        } else if !message.isEmpty {
            context.writeError(message.hasPrefix("Error:") || message.hasPrefix("Usage:") ? message + "\n" : "Error: \(message)\n")
        }
    }
}

private struct ErrorOutput: Encodable {
    var error: String
    var code: Int32
}
