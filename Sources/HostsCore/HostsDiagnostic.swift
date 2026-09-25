import Foundation

public struct HostsDiagnostic: Equatable, Sendable {
    public let line: Int?
    public let message: String

    public init(line: Int?, message: String) {
        self.line = line
        self.message = message
    }

    public var description: String {
        if let line { return "Line \(line): \(message)" }
        return message
    }
}
