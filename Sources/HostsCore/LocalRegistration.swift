import Foundation

public struct LocalRegistration: Codable, Equatable, Sendable {
    public static let directory = "/Library/Application Support/Hostshift"
    public static let path = directory + "/registration.json"
    public static let executable = "/Library/PrivilegedHelperTools/local.hostshift.helper"
    public static let daemon = "/Library/LaunchDaemons/local.hostshift.helper.plist"

    public var clientRequirement: String
    public var helperRequirement: String
    public var userID: UInt32

    public init(clientRequirement: String, helperRequirement: String, userID: UInt32) {
        self.clientRequirement = clientRequirement
        self.helperRequirement = helperRequirement
        self.userID = userID
    }

    public static func load() throws -> Self {
        for path in [directory, Self.path] {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let type = attributes[.type] as? FileAttributeType
            guard attributes[.ownerAccountID] as? UInt32 == 0,
                  (attributes[.posixPermissions] as? Int ?? 0) & 0o022 == 0,
                  type == (path == directory ? .typeDirectory : .typeRegular) else {
                throw CocoaError(.fileReadNoPermission)
            }
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }
}
