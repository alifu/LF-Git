import AppKit
import LFKit
import Observation

/// Window-level state: which repository is open, and errors to show.
@Observable
final class AppModel {
    private(set) var repository: RepositoryModel?
    var errorMessage: String?
    private var appliedLaunchArguments = false
    private static let recentsKey = "recentRepositories"
    private static let recentsLimit = 10
    /// Paths of repositories opened lately, newest first.
    private(set) var recentRepositories: [String] = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []

    /// Opens `url` (any folder inside a repository) and selects `file` when given.
    func open(_ url: URL, selecting file: String? = nil) {
        if let repository, repository.root.standardizedFileURL == (try? RepositoryModel.open(at: url))?.root.standardizedFileURL {
            if let file { repository.selection = file }
            return
        }
        guard confirmDiscardingUnsavedWork() else { return }
        do {
            let model = try RepositoryModel.open(at: url)
            repository = model
            remember(model.root)
            Task {
                await model.refresh()
                if let file, model.files.contains(where: { $0.id == file }) {
                    model.selection = file
                }
            }
        } catch {
            errorMessage = "\(error)"
        }
    }

    private func remember(_ root: URL) {
        let path = root.standardizedFileURL.path
        // Throw-away repositories (tests, scratch clones) would only clutter the menu.
        guard !path.hasPrefix(FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path), !path.hasPrefix("/private/var/folders"),
              !path.hasPrefix("/var/folders") else { return }
        recentRepositories = Array(([path] + recentRepositories.filter { $0 != path }).prefix(Self.recentsLimit))
        UserDefaults.standard.set(recentRepositories, forKey: Self.recentsKey)
    }

    func clearRecentRepositories() {
        recentRepositories = []
        UserDefaults.standard.removeObject(forKey: Self.recentsKey)
    }

    /// Runs an action and shows what went wrong. A command the user cancelled is not a problem.
    func run(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { report(error) }
        }
    }

    func report(_ error: Error) {
        if let git = error as? GitError, git == .cancelled { return }
        errorMessage = "\(error)"
    }

    func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a git repository with conflicts to resolve."
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    /// Applies the launch arguments once (the window can appear again later).
    func applyLaunchArgumentsOnce(_ arguments: [String]) {
        guard !appliedLaunchArguments else { return }
        appliedLaunchArguments = true
        apply(LaunchOptions.parse(arguments))
    }

    func handle(_ url: URL) {
        if let options = LaunchOptions.parse(url: url) {
            apply(options)
        }
    }

    private func apply(_ options: LaunchOptions) {
        if let repository = options.repository {
            open(repository, selecting: options.file)
        }
    }

    /// Asks before unsaved resolutions are thrown away. True when it is fine to continue.
    func confirmDiscardingUnsavedWork() -> Bool {
        guard let repository, repository.hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard unsaved resolutions?"
        alert.informativeText = "These files have resolutions that are not saved yet:\n"
            + repository.unsavedFiles.joined(separator: "\n")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard")
        alert.alertStyle = .warning
        return alert.runModal() == .alertSecondButtonReturn
    }
}

/// Asks before quitting with unsaved resolutions.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var app: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (app?.confirmDiscardingUnsavedWork() ?? true) ? .terminateNow : .terminateCancel
    }
}
