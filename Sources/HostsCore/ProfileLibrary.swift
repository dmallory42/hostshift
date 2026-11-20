import Foundation

public struct ProfileLibrary: Codable, Equatable, Sendable {
    public static let copyOfHostsName = "Copy of /etc/hosts"

    public var profiles: [Profile]
    public var preferredActiveID: UUID?
    public var lastActivatedDigest: String?

    public init(original: String) {
        let profile = Profile(name: "Original", content: original, isOriginal: true)
        profiles = [profile]
        preferredActiveID = profile.id
        lastActivatedDigest = HostsInstallScript.digest(original)
    }

    public func activeID(matching content: String) -> UUID? {
        if let preferredActiveID,
           profiles.contains(where: { $0.id == preferredActiveID && $0.content == content }) {
            return preferredActiveID
        }
        return profiles.first(where: { $0.content == content })?.id
    }

    /// True when content matches neither a saved profile nor the last activation, so a switch would discard it.
    public func hasExternalChanges(in content: String) -> Bool {
        activeID(matching: content) == nil && lastActivatedDigest != HostsInstallScript.digest(content)
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

    /// Names typed by the user are kept, but generated names gain " (2)", " (3)" and so on until they are unused.
    public static func uniqueName(_ name: String, among names: Set<String>) -> String {
        var candidate = name
        var number = 2
        while names.contains(candidate) {
            candidate = "\(name) (\(number))"
            number += 1
        }
        return candidate
    }

    /// A typed name without surrounding whitespace, or nil when nothing is left.
    public static func normalizedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Adds a new profile or replaces a saved one with the same ID. Original is read-only.
    public mutating func upsert(_ profile: Profile) throws {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            if profiles[index].isOriginal || profile.isOriginal {
                guard profiles[index] == profile else { throw ProfileLibraryError.original }
                return
            }
            profiles[index] = profile
        } else {
            guard !profile.isOriginal else { throw ProfileLibraryError.original }
            profiles.append(profile)
        }
    }

    /// Adds a profile with a generated name. `reservedNames` covers names in use outside the library, such as unsaved drafts.
    @discardableResult
    public mutating func add(name: String, content: String, reservedNames: Set<String> = []) -> Profile {
        let profile = Profile(name: Self.uniqueName(name, among: reservedNames.union(profiles.map(\.name))), content: content)
        profiles.append(profile)
        return profile
    }

    public mutating func rename(id: UUID, to name: String) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileLibraryError.notFound }
        guard !profiles[index].isOriginal else { throw ProfileLibraryError.original }
        guard let name = Self.normalizedName(name) else { throw ProfileLibraryError.emptyName }
        profiles[index].name = name
    }

    /// Deletes a profile unless it is Original or matches the current system hosts content.
    public mutating func remove(id: UUID, systemContent: String) throws {
        guard let profile = profiles.first(where: { $0.id == id }) else { throw ProfileLibraryError.notFound }
        guard !profile.isOriginal else { throw ProfileLibraryError.original }
        guard activeID(matching: systemContent) != id else { throw ProfileLibraryError.active }
        profiles.removeAll { $0.id == id }
    }
}

public enum ProfileLibraryError: LocalizedError, Equatable, Sendable {
    case notFound, original, active, emptyName

    public var errorDescription: String? {
        switch self {
        case .notFound: "That profile no longer exists."
        case .original: "Original is read-only."
        case .active: "The active profile can’t be deleted. Activate another profile first."
        case .emptyName: "Profile names can’t be empty."
        }
    }
}
