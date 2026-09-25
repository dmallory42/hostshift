import Foundation
import HostsCore

actor HostsInstaller {
    func apply(content: String, expected: String) async throws -> String {
        let requirement: String
        if let signedRequirement = try? HelperIdentity.peerRequirement(identifier: HelperIdentity.serviceName) {
            requirement = signedRequirement
        } else {
            let registration = try LocalRegistration.load()
            guard registration.userID == getuid(), registration.clientRequirement == (try CodeIdentity.ownRequirement()) else {
                throw Self.unavailable
            }
            requirement = registration.helperRequirement
        }
        let connection = NSXPCConnection(machServiceName: HelperIdentity.serviceName, options: .privileged)
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            let completion = HelperReply(continuation)
            Task {
                try? await Task.sleep(for: .seconds(15))
                completion.finish(.failure(Self.unavailable))
            }
            connection.invalidationHandler = { @Sendable in completion.finish(.failure(Self.unavailable)) }
            connection.interruptionHandler = { @Sendable in completion.finish(.failure(Self.unavailable)) }
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ @Sendable error in
                completion.finish(.failure(error))
            }) as? HelperProtocol else {
                completion.finish(.failure(Self.unavailable))
                return
            }
            proxy.apply(content: content, expected: expected) { message, error in
                if let error {
                    completion.finish(.failure(NSError(domain: "Hostshift", code: 1, userInfo: [NSLocalizedDescriptionKey: error])))
                } else { completion.finish(.success(message ?? "Profile activated.")) }
            }
        }
    }

    private static var unavailable: NSError {
        NSError(domain: "Hostshift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Hostshift could not reach its helper. Check system access in Settings. Refresh the system file before retrying; the helper may have completed the switch."])
    }
}
