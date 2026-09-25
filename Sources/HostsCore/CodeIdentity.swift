import Foundation
import Security

public enum CodeIdentity {
    public static func requirement(at url: URL) throws -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try requirement(for: code)
    }

    public static func ownRequirement() throws -> String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try requirement(for: staticCode)
    }

    private static func requirement(for code: SecStaticCode) throws -> String {
        var requirement: SecRequirement?
        var text: CFString?
        guard SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return text as String
    }
}
