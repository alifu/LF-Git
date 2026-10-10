import Foundation

/// Runs `action` once after a delay unless cancelled first.
///
/// It owns a thread instead of using a dispatch queue: a time limit has to fire on time even when every shared
/// worker thread is busy waiting for other commands, which is exactly when a hung command needs stopping.
final class Watchdog: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    init(after seconds: TimeInterval, _ action: @escaping @Sendable () -> Void) {
        let semaphore = semaphore
        let thread = Thread {
            if semaphore.wait(timeout: .now() + seconds) == .timedOut { action() }
        }
        thread.stackSize = 256 * 1024
        thread.start()
    }

    /// Stops the countdown; the action will not run (if it has not run yet).
    func cancel() {
        semaphore.signal()
    }
}
