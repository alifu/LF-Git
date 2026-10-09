import Foundation

/// Lets one thread stop a git command that another thread is running.
public final class GitCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [UUID: @Sendable () -> Void] = [:]

    public init() {}

    public var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    /// Stops the command now, or as soon as it starts if it has not yet.
    public func cancel() {
        let pending: [@Sendable () -> Void] = lock.withLock {
            cancelled = true
            let all = Array(handlers.values)
            handlers.removeAll()
            return all
        }
        pending.forEach { $0() }
    }

    /// Runs `handler` on cancellation (immediately if it already happened); returns a key for `remove`.
    func onCancel(_ handler: @escaping @Sendable () -> Void) -> UUID {
        let key = UUID()
        let runNow: Bool = lock.withLock {
            if cancelled { return true }
            handlers[key] = handler
            return false
        }
        if runNow { handler() }
        return key
    }

    func remove(_ key: UUID) {
        lock.withLock { _ = handlers.removeValue(forKey: key) }
    }
}

/// One git command that ran.
public struct GitCommandEntry: Sendable, Equatable, Identifiable {
    public let id: Int
    public let command: String
    /// Exit status; -1 when the command was cancelled, timed out or could not start.
    public let status: Int32
    public let duration: TimeInterval
    public let date: Date

    public var succeeded: Bool { status == 0 }
}

/// Remembers the most recent git commands, like lazygit's command log. Thread-safe.
public final class GitCommandLog: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var stored: [GitCommandEntry] = []
    private var counter = 0
    private var observers: [UUID: @Sendable (GitCommandEntry) -> Void] = [:]

    public init(capacity: Int = 500) {
        self.capacity = max(1, capacity)
    }

    public var entries: [GitCommandEntry] {
        lock.withLock { stored }
    }

    /// Calls `observer` for every command from now on, on whichever thread ran it.
    public func observe(_ observer: @escaping @Sendable (GitCommandEntry) -> Void) -> UUID {
        let key = UUID()
        lock.withLock { observers[key] = observer }
        return key
    }

    public func stopObserving(_ key: UUID) {
        lock.withLock { _ = observers.removeValue(forKey: key) }
    }

    func record(arguments: [String], status: Int32, duration: TimeInterval) {
        record(command: Self.render(arguments), status: status, duration: duration)
    }

    /// Records a command that is not git itself (a user-defined command).
    public func record(command: String, status: Int32, duration: TimeInterval) {
        let (entry, callbacks): (GitCommandEntry, [@Sendable (GitCommandEntry) -> Void]) = lock.withLock {
            counter += 1
            let entry = GitCommandEntry(id: counter, command: command, status: status,
                                        duration: duration, date: Date())
            stored.append(entry)
            if stored.count > capacity { stored.removeFirst(stored.count - capacity) }
            return (entry, Array(observers.values))
        }
        callbacks.forEach { $0(entry) }
    }

    /// `git a "b c"`, with the password of a URL such as `https://user:secret@host` hidden.
    static func render(_ arguments: [String]) -> String {
        let parts = arguments.map { argument -> String in
            let hidden = argument.replacingOccurrences(of: #"://[^/@\s]+@"#, with: "://***@", options: .regularExpression)
            return hidden.contains(where: \.isWhitespace) ? "\"\(hidden)\"" : hidden
        }
        return (["git"] + parts).joined(separator: " ")
    }
}
