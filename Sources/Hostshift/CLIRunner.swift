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
        let json = arguments.contains("--json")
        var context = context
        if json {
            context.outputStyle = .plain
            context.errorStyle = .plain
        }
        return await CLIContext.$current.withValue(context) {
            do {
                var command = try await HostshiftCommand.asyncParseAsRoot(arguments)
                if var command = command as? AsyncParsableCommand { try await command.run() }
                else { try command.run() }
                return CLIExitCode.success.rawValue
            } catch let error as CLIError {
                report(error.message, code: error.code, json: json, isFormatted: error.isFormatted)
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

    private static func report(_ message: String, code: CLIExitCode, json: Bool, isFormatted: Bool = false) {
        let context = CLIContext.active
        // Commands that already printed their result, like validate, fail with no message.
        guard !message.isEmpty else { return }
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let output = ErrorOutput(error: message, code: code.rawValue)
            let data = (try? encoder.encode(output)) ?? Data()
            context.writeError(String(decoding: data, as: UTF8.self) + "\n")
        } else if isFormatted || message.hasPrefix("Usage:") {
            context.writeError(message + "\n")
        } else if context.errorStyle.isEnabled {
            let style = context.errorStyle
            let symbol = code == .needsDecision ? style.warning : style.failure
            let text = message.hasPrefix("Error: ") ? String(message.dropFirst("Error: ".count)) : message
            context.writeError("\(symbol) \(text)\n")
        } else {
            context.writeError(message.hasPrefix("Error:") ? message + "\n" : "Error: \(message)\n")
        }
    }
}

private struct ErrorOutput: Encodable {
    var error: String
    var code: Int32
}
