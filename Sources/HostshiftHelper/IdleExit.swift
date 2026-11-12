import Foundation

/// Exits the helper after a quiet period, so launchd starts the installed binary for the next request and an updated app gets its own helper.
final class IdleExit: @unchecked Sendable {
    private let lock = NSLock()
    private var activeRequests = 0
    private var generation = 0
    private let delay: TimeInterval
    private let exit: @Sendable () -> Void

    init(after delay: TimeInterval, exit: @escaping @Sendable () -> Void) {
        self.delay = delay
        self.exit = exit
        restart()
    }

    func begin() {
        lock.lock()
        activeRequests += 1
        generation += 1
        lock.unlock()
    }

    func end() {
        lock.lock()
        activeRequests -= 1
        lock.unlock()
        restart()
    }

    /// Starts the quiet period again, cancelling any earlier countdown.
    func restart() {
        lock.lock()
        generation += 1
        let scheduled = generation
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            // Holding the lock keeps a request from starting between this check and the exit.
            lock.lock()
            defer { lock.unlock() }
            if activeRequests == 0 && generation == scheduled { exit() }
        }
    }
}
