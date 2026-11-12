import Foundation
import HostsCore

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    private let service: HelperService
    private let requirement: String
    private let allowedUser: UInt32?
    private let idleExit: IdleExit?

    init(requirement: String, allowedUser: UInt32? = nil, idleExit: IdleExit? = nil) {
        self.requirement = requirement
        self.allowedUser = allowedUser
        self.idleExit = idleExit
        service = HelperService(idleExit: idleExit)
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if let allowedUser, connection.effectiveUserIdentifier != allowedUser { return false }
        idleExit?.restart()
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}
