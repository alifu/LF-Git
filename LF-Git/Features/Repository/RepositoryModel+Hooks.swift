import Foundation
import LFKit

extension RepositoryModel {
    /// Runs `body` as a recorded hook run when the repository has one of `hookNames` (and hooks are on).
    /// `body` receives a sink for what git and the hooks print. The panel opens when the run starts.
    func withHookRun(_ title: String, hookNames: [String], enabled: Bool = true,
                     _ body: @escaping (@escaping @Sendable (String) -> Void) async throws -> Void) async throws {
        guard enabled, await Self.anyHookExists(client, hookNames) else {
            try await body { _ in }
            return
        }
        let store = hooks
        let id = store.begin(title: title)
        showsHooksPanel = true
        let pending = HookOutputBuffer()
        let sink: @Sendable (String) -> Void = { chunk in
            pending.add(chunk)
            Task { @MainActor in store.append(pending.drain(), to: id) }
        }
        do {
            try await body(sink)
            store.append(pending.drain(), to: id)
            store.finish(id, error: nil)
        } catch {
            store.append(pending.drain(), to: id)
            store.finish(id, error: error)
            throw error
        }
    }

    func push(force: Bool = false) async throws {
        let runHooks = runsPushHooks
        if !runHooks, hasPrePushHook {
            record(.info, "Pushing with hooks disabled: pre-push is skipped")
        }
        try await withHookRun("Push", hookNames: ["pre-push"], enabled: runHooks) { sink in
            try await self.perform("Pushing…", cancellable: true, serialized: false) { client, token in
                try client.push(force: force, runHooks: runHooks, cancellation: token, onOutput: sink)
            }
        }
    }

    @concurrent
    nonisolated private static func anyHookExists(_ client: GitClient, _ names: [String]) async -> Bool {
        client.hasHook(namedAnyOf: names)
    }
}

/// Output that arrived from git's thread and has not reached the hook panel yet. `finish` drains it first, so the
/// last lines always land before the run's status, whatever order the main-actor hops run in.
nonisolated final class HookOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func add(_ chunk: String) {
        lock.withLock { text += chunk }
    }

    func drain() -> String {
        lock.withLock {
            defer { text = "" }
            return text
        }
    }
}
