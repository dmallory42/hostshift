import Foundation

// XPC can deliver a reply and an invalidation; resume the continuation once.
final class HelperReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, any Error>?

    init(_ continuation: CheckedContinuation<String, any Error>) { self.continuation = continuation }

    func finish(_ result: Result<String, any Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
