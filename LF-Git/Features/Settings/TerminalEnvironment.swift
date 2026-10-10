import Foundation
import LFKit
import Observation

/// Lets git inside the app see what git sees in the user's terminal: the same `PATH`, SSH agent and tokens.
/// An app started from the Dock gets none of the exports in `.zshrc`, so token logins that work in a terminal fail in it.
@Observable
final class TerminalEnvironment {
    static let storageKey = "importTerminalEnvironment"
    static let shared = TerminalEnvironment()

    private(set) var importedNames: [String] = []
    private(set) var gitPath: String?
    private(set) var gitVersion: String?
    private(set) var isLoading = false

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.storageKey) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.storageKey)
        Task { await reload() }
    }

    /// Reads the login shell again (or forgets it when switched off) and tells git about it.
    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let enabled = isEnabled
        let result = await Self.read(enabled: enabled)
        importedNames = result.names
        gitPath = result.path
        gitVersion = result.version
    }

    @concurrent
    nonisolated private static func read(enabled: Bool) async -> (names: [String], path: String?, version: String?) {
        let captured = enabled ? LoginEnvironment.capture() : [:]
        GitEnvironment.shared.set(captured)
        let location = GitEnvironment.shared.gitLocation()
        return (captured.keys.sorted(), location?.path, location?.version)
    }
}
