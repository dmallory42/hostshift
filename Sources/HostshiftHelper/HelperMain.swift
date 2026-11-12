import Foundation
import HostsCore

@main
struct HelperMain {
    static func main() throws {
        guard geteuid() == 0 else { throw CocoaError(.fileWriteNoPermission) }
        let requirement: String
        let allowedUser: UInt32?
        if CommandLine.arguments.contains("--local") {
            let registration = try LocalRegistration.load()
            guard registration.helperRequirement == (try CodeIdentity.ownRequirement()) else { throw CocoaError(.fileReadNoPermission) }
            requirement = registration.clientRequirement
            allowedUser = registration.userID
        } else {
            requirement = try HelperIdentity.peerRequirement(identifier: "dev.dmallory.hostshift")
            allowedUser = nil
        }
        // launchd delays restarting a job that ran for under 10 seconds, so the quiet period stays well above that.
        let idleExit = IdleExit(after: 30) { exit(0) }
        let delegate = HelperDelegate(requirement: requirement, allowedUser: allowedUser, idleExit: idleExit)
        let listener = NSXPCListener(machServiceName: HelperIdentity.serviceName)
        listener.setConnectionCodeSigningRequirement(requirement)
        listener.delegate = delegate
        listener.resume()
        withExtendedLifetime(delegate) { RunLoop.current.run() }
    }
}
