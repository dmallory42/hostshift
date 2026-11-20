import Foundation

public struct Profile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var content: String
    public var isOriginal: Bool

    public init(id: UUID = UUID(), name: String, content: String, isOriginal: Bool = false) {
        self.id = id
        self.name = name
        self.content = content
        self.isOriginal = isOriginal
    }
}

extension Profile {
    public var displayName: String { name.isEmpty ? "Untitled" : name }
    /// The save panel and Finder treat slashes and colons as path separators.
    public var exportFileName: String { displayName.replacing("/", with: "-").replacing(":", with: "-") + ".hosts" }
}
