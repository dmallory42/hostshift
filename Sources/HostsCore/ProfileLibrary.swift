import Foundation

public struct ProfileLibrary: Codable, Sendable {
    public var profiles: [Profile]
    public var preferredActiveID: UUID?

    public init(original: String) {
        let profile = Profile(name: "Original", content: original, isOriginal: true)
        profiles = [profile]
        preferredActiveID = profile.id
    }

    public func activeID(matching content: String) -> UUID? {
        if let preferredActiveID,
           profiles.contains(where: { $0.id == preferredActiveID && $0.content == content }) {
            return preferredActiveID
        }
        return profiles.first(where: { $0.content == content })?.id
    }

    public static func load(from url: URL) throws -> Self {
        let library = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard library.profiles.filter({ $0.isOriginal }).count == 1,
              Set(library.profiles.map(\.id)).count == library.profiles.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return library
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
