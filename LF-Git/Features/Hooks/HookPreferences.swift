import Foundation

/// Per-repository choice to run or skip the `pre-push` hook. Stored in the app's preferences, never in the
/// repository, so nothing in the repo is edited or left half-changed.
struct HookPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ root: URL) -> String { "pushHooksDisabled:\(root.standardizedFileURL.path)" }

    func runsPushHooks(in root: URL) -> Bool {
        !defaults.bool(forKey: key(root))
    }

    func setRunsPushHooks(_ runs: Bool, in root: URL) {
        if runs {
            defaults.removeObject(forKey: key(root))
        } else {
            defaults.set(true, forKey: key(root))
        }
    }
}
