import Foundation

public enum ExternalChangeChoice: Sendable {
    case saveAsProfile, replace, cancel
}

public enum ActivationError: LocalizedError, Equatable, Sendable {
    case invalid([String])
    case hostsUnreadable(String)
    case cancelled
    case saveFailed(String)
    case installFailed(String)
    case mismatch

    public var errorDescription: String? {
        switch self {
        case .invalid(let issues): issues.joined(separator: "\n")
        case .hostsUnreadable(let message): message
        case .cancelled: "Activation cancelled."
        case .saveFailed(let message): "Could not save your profiles: \(message)"
        case .installFailed(let message): message
        case .mismatch: "The hosts file no longer matches the profile. Another app may have changed it."
        }
    }
}

/// The activation sequence shared by the app and the command-line tool: validate, resolve external
/// changes, save the profile, install it through the helper, read it back and record the activation.
public struct ProfileActivation: Sendable {
    public typealias Install = @Sendable (_ content: String, _ expected: String) async throws -> String

    public let library: ProfileLibraryFile
    public let hostsURL: URL
    public let install: Install

    public init(library: ProfileLibraryFile, hostsURL: URL = URL(fileURLWithPath: "/etc/hosts"),
                install: @escaping Install = { try await HostsInstaller().apply(content: $0, expected: $1) }) {
        self.library = library
        self.hostsURL = hostsURL
        self.install = install
    }

    /// Activates `profile`, saving it first. A failed save stops the install.
    /// - Parameters:
    ///   - reservedNames: Names in use outside the saved library, so a saved copy of /etc/hosts doesn't repeat one.
    ///   - resolveExternalChanges: Asked when /etc/hosts matches neither the last activation nor a saved profile.
    /// - Returns: A warning to show even though the profile was activated, such as a failed DNS refresh.
    public func run(_ profile: Profile, reservedNames: Set<String> = [],
                    resolveExternalChanges: @Sendable (Profile) async -> ExternalChangeChoice) async throws(ActivationError) -> String? {
        let issues = HostsValidator.issues(in: profile.content)
        guard issues.isEmpty else { throw .invalid(issues) }
        let expected = try readHosts()
        let saved: ProfileLibrary
        do {
            guard let snapshot = try library.load() else { throw CocoaError(.fileNoSuchFile) }
            saved = snapshot.library
        } catch { throw .saveFailed(error.localizedDescription) }
        if saved.hasExternalChanges(in: expected) {
            switch await resolveExternalChanges(profile) {
            case .cancel: throw .cancelled
            case .replace: break
            case .saveAsProfile:
                try save { _ = $0.add(name: ProfileLibrary.copyOfHostsName, content: expected, reservedNames: reservedNames) }
            }
        }
        try save { try $0.upsert(profile) }
        let message: String
        do { message = try await install(profile.content, expected) }
        catch { throw .installFailed(error.localizedDescription) }
        guard try readHosts() == profile.content else { throw .mismatch }
        var warning: String?
        do {
            try library.update {
                $0.preferredActiveID = profile.id
                $0.lastActivatedDigest = HostsInstallScript.digest(profile.content)
            }
        } catch { warning = ActivationError.saveFailed(error.localizedDescription).errorDescription }
        if message == HostsInstallScript.dnsRefreshFailed { warning = [warning, message].compactMap(\.self).joined(separator: "\n") }
        return warning
    }

    public func readHosts() throws(ActivationError) -> String {
        do { return try String(contentsOf: hostsURL, encoding: .utf8) }
        catch { throw .hostsUnreadable(error.localizedDescription) }
    }

    private func save(_ change: (inout ProfileLibrary) throws -> Void) throws(ActivationError) {
        do { try library.update(change) }
        catch { throw .saveFailed(error.localizedDescription) }
    }
}
