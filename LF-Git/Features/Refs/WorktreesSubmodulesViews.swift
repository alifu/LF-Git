import AppKit
import LFKit
import SwiftUI

/// Linked working directories of the repository.
struct WorktreesSidebar: View {
    @Bindable var repository: RepositoryModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ListActionBar {
                Button { add() } label: { Label("Add Worktree", systemImage: "plus") }
                    .accessibilityIdentifier("add-worktree")
                Button { act("Pruning…") { try $0.pruneWorktrees() } } label: { Label("Prune", systemImage: "scissors") }
                    .help("Forget worktrees whose directory is gone")
            }
            List(selection: $repository.worktreeSelection) {
                ForEach(repository.worktrees) { tree in
                    SimpleRow(symbol: tree.isMain ? "house" : "square.stack.3d.up", title: URL(fileURLWithPath: tree.path).lastPathComponent,
                              subtitle: tree.path, trailing: tree.branch ?? "detached", identifier: "worktree-\(tree.path)")
                        .tag(tree.id)
                        .contextMenu {
                            Button("Open in This Window") { app.open(URL(fileURLWithPath: tree.path)) }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: tree.path)]) }
                            Button("Copy Path") { Clipboard.copy(tree.path) }
                            if !tree.isMain {
                                Divider()
                                Button("Remove…", role: .destructive) { remove(tree) }
                            }
                        }
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("worktrees-list")
        }
    }

    private func act(_ title: String, _ work: @escaping @Sendable (GitClient) throws -> Void) {
        app.run { try await repository.perform(title) { client, _ in try work(client) } }
    }

    private func add() {
        repository.ask(PendingPrompt(title: "Add Worktree", message: "A new branch with this name is created and checked out in a new directory next to the repository.",
                                     placeholder: "Branch name", confirmTitle: "Create") { name in
            let branch = name.trimmingCharacters(in: .whitespaces)
            let folder = repository.root.deletingLastPathComponent()
                .appendingPathComponent("\(repository.root.lastPathComponent)-\(branch.replacingOccurrences(of: "/", with: "-"))").path
            act("Adding worktree…") { try $0.addWorktree(at: folder, branch: branch, createBranch: true) }
        })
    }

    private func remove(_ tree: GitWorktree) {
        repository.confirm(PendingConfirmation(title: "Remove worktree \(URL(fileURLWithPath: tree.path).lastPathComponent)?",
                                               message: "The directory is deleted. Git refuses if it has uncommitted changes.",
                                               confirmTitle: "Remove") { act("Removing worktree…") { try $0.removeWorktree(at: tree.path) } })
    }
}

struct SubmodulesSidebar: View {
    @Bindable var repository: RepositoryModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ListActionBar {
                Button { add() } label: { Label("Add Submodule", systemImage: "plus") }
                    .accessibilityIdentifier("add-submodule")
                Button { remote("Updating submodules…") { try $0.updateSubmodules(cancellation: $1) } } label: {
                    Label("Update All", systemImage: "arrow.down.circle")
                }
                .disabled(repository.submodules.isEmpty)
            }
            List(selection: $repository.submoduleSelection) {
                ForEach(repository.submodules) { module in
                    SimpleRow(symbol: symbol(module.state), symbolToken: token(module.state), title: module.path, subtitle: module.url,
                              trailing: String(module.hash.prefix(7)), identifier: "submodule-\(module.path)")
                        .tag(module.id)
                        .contextMenu {
                            Button("Update") { remote("Updating…") { try $0.updateSubmodules(paths: [module.path], cancellation: $1) } }
                            Button("Open in This Window") { app.open(repository.root.appendingPathComponent(module.path)) }
                            Button("Copy URL") { Clipboard.copy(module.url) }
                            Divider()
                            Button("Remove…", role: .destructive) {
                                repository.confirm(PendingConfirmation(title: "Remove \(module.path)?", message: "The submodule is removed from the work tree, the index and .gitmodules.",
                                                                       confirmTitle: "Remove") {
                                    app.run { try await repository.perform("Removing submodule…") { client, _ in try client.removeSubmodule(path: module.path) } }
                                })
                            }
                        }
                }
            }
            .listStyle(.sidebar)
            .emptyOverlay(repository.submodules.isEmpty, "No submodules", symbol: "shippingbox")
            .accessibilityIdentifier("submodules-list")
        }
    }

    private func symbol(_ state: SubmoduleState) -> String {
        switch state {
        case .upToDate: "shippingbox"
        case .notInitialized: "shippingbox.circle"
        case .modified: "arrow.triangle.2.circlepath"
        case .conflicted: "exclamationmark.triangle"
        }
    }

    private func token(_ state: SubmoduleState) -> LFThemeToken {
        switch state {
        case .upToDate: .accentText
        case .notInitialized: .textSubtle
        case .modified: .warning
        case .conflicted: .danger
        }
    }

    private func remote(_ title: String, _ work: @escaping @Sendable (GitClient, GitCancellation) throws -> Void) {
        app.run { try await repository.perform(title, cancellable: true, serialized: true, work) }
    }

    private func add() {
        repository.ask(PendingPrompt(title: "Add Submodule", message: "Repository URL", placeholder: "https://… or git@…", confirmTitle: "Next") { url in
            let url = url.trimmingCharacters(in: .whitespaces)
            repository.ask(PendingPrompt(title: "Add Submodule", message: "Folder inside this repository", placeholder: "vendor/library",
                                         confirmTitle: "Add") { path in
                remote("Adding submodule…") { try $0.addSubmodule(url: url, path: path.trimmingCharacters(in: .whitespaces), cancellation: $1) }
            })
        })
    }
}

#if DEBUG
#Preview("Worktrees sidebar") {
    PreviewRepository(width: 340, height: 400) { repository, app in
        WorktreesSidebar(repository: repository, app: app)
    }
}
#endif

#if DEBUG
#Preview("Submodules sidebar") {
    PreviewRepository(width: 340, height: 400) { repository, app in
        SubmodulesSidebar(repository: repository, app: app)
    }
}
#endif
