import Foundation
import LFKit

extension RepositoryModel {
    /// Runs `body` as a recorded hook run when the repository has one of `hookNames` (and hooks are on).
    /// `body` receives a sink for what git and the hooks print. The panel opens when the run starts.
    func withHookRun(_ title: String, hookNames: [String], enabled: Bool = true,
                     _ body: @escaping (@escaping @Sendable (String) -> Void) async throws -> Void) async throws {
        guard enabled, hookNames.contains(where: { client.hasHook(named: $0) }) else {
            try await body { _ in }
            return
        }
        let store = hooks
        let id = store.begin(title: title)
        showsHooksPanel = true
        let sink: @Sendable (String) -> Void = { chunk in
            Task { @MainActor in store.append(chunk, to: id) }
        }
        do {
            try await body(sink)
            store.finish(id, error: nil)
        } catch {
            store.finish(id, error: error)
            throw error
        }
    }

    func push(force: Bool = false) async throws {
        let runHooks = runsPushHooks
        if !runHooks, client.hasHook(named: "pre-push") {
            record(.info, "Pushing with hooks disabled: pre-push is skipped")
        }
        try await withHookRun("Push", hookNames: ["pre-push"], enabled: runHooks) { sink in
            try await self.perform("Pushing…", cancellable: true, serialized: false) { client, token in
                try client.push(force: force, runHooks: runHooks, cancellation: token, onOutput: sink)
            }
        }
    }
}
