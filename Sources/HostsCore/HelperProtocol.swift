import Foundation

@objc public protocol HelperProtocol {
    func apply(content: String, expected: String, reply: @escaping @Sendable (String?, String?) -> Void)
}
