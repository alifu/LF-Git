import LFKit
import SwiftUI

/// Stashes: save away local changes, bring them back later.
struct StashSidebar: View {
    @Bindable var repository: RepositoryModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ListActionBar {
                Menu {
                    Button("Stash All Changes…") { stash(.init()) }
                    Button("Stash Including Untracked Files…") { stash(.init(includeUntracked: true)) }
                    Button("Stash Staged Changes Only…") { stash(.init(stagedOnly: true)) }
                        .disabled(repository.status.staged.isEmpty)
                    Button("Stash and Keep Staged Changes…") { stash(.init(keepIndex: true)) }
                } label: {
                    Label("Stash Changes", systemImage: "tray.and.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(repository.status.isClean)
                .accessibilityIdentifier("stash-menu")
            }
            List(selection: $repository.stashSelection) {
                ForEach(repository.stashes) { stash in
                    SimpleRow(symbol: "tray.full", title: stash.message, subtitle: [stash.branch, stash.date.formatted(.relative(presentation: .named))]
                        .compactMap { $0 }.joined(separator: " · "), trailing: stash.ref, identifier: "stash-\(stash.message)")
                        .tag(stash.id)
                        .contextMenu { menu(for: stash) }
                }
            }
            .listStyle(.sidebar)
            .emptyOverlay(repository.stashes.isEmpty, "No stashes", symbol: "tray")
            .accessibilityIdentifier("stash-list")
        }
        .onChange(of: repository.stashSelection, initial: true) { show() }
        .onChange(of: repository.stashes) { show() }
    }

    private func show() {
        guard let stash = repository.stashes.first(where: { $0.id == repository.stashSelection }) else {
            Task { await repository.commitViewer.show(.fixed([])) }
            return
        }
        Task {
            await repository.commitViewer.show(.fixed([stash.commit]))
            await repository.commitViewer.select(stash.id)
        }
    }

    @ViewBuilder
    private func menu(for stash: GitStash) -> some View {
        Button("Apply") { act("Applying stash…") { try $0.stashApply(stash) } }
        Button("Pop (Apply and Drop)") { act("Popping stash…") { try $0.stashPop(stash) } }
        Button("New Branch from Stash…") { branch(from: stash) }
        Button("Rename…") { rename(stash) }
        Divider()
        Button("Drop…", role: .destructive) {
            repository.confirm(PendingConfirmation(title: "Drop “\(stash.message)”?", message: "The stashed changes are deleted.",
                                                   confirmTitle: "Drop Stash") { act("Dropping stash…") { try $0.stashDrop(stash) } })
        }
    }

    private func act(_ title: String, _ work: @escaping @Sendable (GitClient) throws -> Void) {
        app.run { try await repository.perform(title) { client, _ in try work(client) } }
    }

    private struct Options {
        var includeUntracked = false
        var stagedOnly = false
        var keepIndex = false
    }

    private func stash(_ options: Options) {
        repository.ask(PendingPrompt(title: "Stash Changes", message: "A name helps you find it later (optional).",
                                     placeholder: "Message", confirmTitle: "Stash") { message in
            act("Stashing…") {
                try $0.stashPush(message: message.trimmingCharacters(in: .whitespaces), includeUntracked: options.includeUntracked,
                                 stagedOnly: options.stagedOnly, keepIndex: options.keepIndex)
            }
        })
    }

    private func rename(_ stash: GitStash) {
        repository.ask(PendingPrompt(title: "Rename Stash", message: "", placeholder: "Message", initialText: stash.message,
                                     confirmTitle: "Rename") { name in
            act("Renaming stash…") { try $0.stashRename(stash, to: name) }
        })
    }

    private func branch(from stash: GitStash) {
        repository.ask(PendingPrompt(title: "New Branch from Stash", message: "The stash is applied on the new branch and dropped.",
                                     placeholder: "Branch name", confirmTitle: "Create") { name in
            act("Creating branch…") { try $0.stashBranch(name.trimmingCharacters(in: .whitespaces), from: stash) }
        })
    }
}

/// The stashed change: files and diff.
struct CommitViewerDetail: View {
    let repository: RepositoryModel
    let app: AppModel
    var emptyTitle = "Select an item"

    var body: some View {
        if repository.commitViewer.selectedCommit == nil {
            ContentUnavailableView(emptyTitle, systemImage: "doc.text.magnifyingglass").background(.theme(.background))
        } else {
            HistoryDetailView(repository: repository, app: app, model: repository.commitViewer)
        }
    }
}

#if DEBUG
#Preview("Stash sidebar") {
    PreviewRepository(width: 340, height: 500) { repository, app in
        StashSidebar(repository: repository, app: app)
    }
}
#endif

#if DEBUG
#Preview("Commit viewer") {
    PreviewRepository(width: 800, height: 500) { repository, app in
        CommitViewerDetail(repository: repository, app: app)
    }
}
#endif
