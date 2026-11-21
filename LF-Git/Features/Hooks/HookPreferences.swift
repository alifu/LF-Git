import Foundation

/// Per-repository choices to run or skip the `pre-push` hook and the commit hooks. Stored in the app's preferences, never in the
/// repository, so nothing in the repo is edited or left half-changed.
struct HookPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ root: URL) -> String { "pushHooksDisabled:\(root.standardizedFileURL.path)" }
    private func commitKey(_ root: URL) -> String { "commitHooksSkipped:\(root.standardizedFileURL.path)" }

    /// The Changes "Skip hooks" checkbox (`git commit --no-verify`) for this repository. Off by default.
    func skipsCommitHooks(in root: URL) -> Bool {
        defaults.bool(forKey: commitKey(root))
    }

    func setSkipsCommitHooks(_ skips: Bool, in root: URL) {
        if skips {
            defaults.set(true, forKey: commitKey(root))
        } else {
            defaults.removeObject(forKey: commitKey(root))
        }
    }

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
