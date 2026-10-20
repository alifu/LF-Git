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
    private static let lastOpenedKey = "lastOpenedRepository"
    static let reopenLastKey = "reopenLastRepository"
    /// Launch argument that starts on the dashboard whatever was open last (the UI tests pass it).
    static let noRestoreArgument = "-LFNoRestore"
    private static let recentsLimit = 20
    private let defaults: UserDefaults
    /// Paths of repositories opened lately, newest first.
    private(set) var recentRepositories: [String]
    /// The repository that was open when the app last had one open; nil after it was closed on purpose.
    private(set) var lastOpenedRepository: String?
    /// Set when the last repository could not be reopened, for the dashboard to explain.
    private(set) var restoreNote: String?
    /// The clone sheet is shown; the menu, the dashboard and the palette all set this.
    var showsClone = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recentRepositories = defaults.stringArray(forKey: Self.recentsKey) ?? []
        lastOpenedRepository = defaults.string(forKey: Self.lastOpenedKey)
    }

    /// Whether the last repository comes back at launch (on unless the user turned it off).
    var reopensLastRepository: Bool { defaults.object(forKey: Self.reopenLastKey) as? Bool ?? true }

    /// Opens `url` (any folder inside a repository) and selects `file` when given.
    func open(_ url: URL, selecting file: String? = nil) {
        if let repository, repository.root.standardizedFileURL == (try? RepositoryModel.open(at: url))?.root.standardizedFileURL {
            if let file { repository.selection = file }
            return
        }
        guard confirmDiscardingUnsavedWork() else { return }
        do {
            let model = try RepositoryModel.open(at: url)
            repository?.shutDown()
            repository = model
            restoreNote = nil
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
        defaults.set(recentRepositories, forKey: Self.recentsKey)
        lastOpenedRepository = path
        defaults.set(path, forKey: Self.lastOpenedKey)
    }

    func clearRecentRepositories() {
        recentRepositories = []
        defaults.removeObject(forKey: Self.recentsKey)
        forgetLastOpened()
    }

    func removeFromRecents(_ path: String) {
        recentRepositories = recentRepositories.filter { $0 != path }
        defaults.set(recentRepositories, forKey: Self.recentsKey)
        if lastOpenedRepository == path { forgetLastOpened() }
    }

    private func forgetLastOpened() {
        lastOpenedRepository = nil
        defaults.removeObject(forKey: Self.lastOpenedKey)
    }

    /// Closes the open repository and returns to the dashboard. False when the user chose to keep working.
    @discardableResult
    func close() -> Bool {
        guard let repository, confirmDiscardingUnsavedWork() else { return repository == nil }
        repository.shutDown()
        self.repository = nil
        forgetLastOpened()
        return true
    }

    /// Opens the repository that was open last, if the user wants that and it is still there.
    func restoreLastRepository(arguments: [String]) {
        guard repository == nil, reopensLastRepository, !arguments.contains(Self.noRestoreArgument),
              let path = lastOpenedRepository else { return }
        let url = URL(fileURLWithPath: path)
        guard (try? RepositoryModel.open(at: url)) != nil else {
            restoreNote = "\(url.lastPathComponent) is no longer at \(url.deletingLastPathComponent().path)."
            removeFromRecents(path)
            return
        }
        open(url)
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
        let options = LaunchOptions.parse(arguments)
        apply(options)
        if options.repository == nil { restoreLastRepository(arguments: arguments) }
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
