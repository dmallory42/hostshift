import Foundation
import HostsCore

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    private let service = HelperService()
    private let requirement: String
    private let allowedUser: UInt32?

    init(requirement: String, allowedUser: UInt32? = nil) {
        self.requirement = requirement
        self.allowedUser = allowedUser
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if let allowedUser, connection.effectiveUserIdentifier != allowedUser { return false }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}
