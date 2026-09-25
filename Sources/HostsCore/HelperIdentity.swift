import Foundation
import Security

public enum HelperIdentity {
    public static let serviceName = "local.hostshift.helper"
    public static let plistName = serviceName + ".plist"

    public static func peerRequirement(identifier: String) throws -> String {
        var code: SecCode?
        var information: CFDictionary?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let details = information as? [String: Any],
              let team = details[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty, team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw NSError(domain: "Hostshift", code: 1, userInfo: [NSLocalizedDescriptionKey: "This build needs an Apple code-signing identity before system access can be enabled."])
        }
        guard ["local.hostshift.app", serviceName].contains(identifier) else {
            throw CocoaError(.coderInvalidValue)
        }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
}
