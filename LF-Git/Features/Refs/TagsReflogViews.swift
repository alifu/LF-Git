import LFKit
import SwiftUI

/// Tags: list, create, push and delete.
struct TagsSidebar: View {
    @Bindable var repository: RepositoryModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ListActionBar {
                Button { newTag(annotated: false) } label: { Label("New Tag", systemImage: "plus") }
                    .accessibilityIdentifier("new-tag")
                Button { newTag(annotated: true) } label: { Label("Annotated", systemImage: "text.badge.plus") }
            }
            List(selection: $repository.tagSelection) {
                ForEach(repository.tags) { tag in
                    SimpleRow(symbol: tag.isAnnotated ? "tag.fill" : "tag", title: tag.name,
                              subtitle: tag.message, trailing: String(tag.commit.prefix(7)), identifier: "tag-\(tag.name)")
                        .tag(tag.id)
                        .contextMenu { menu(for: tag) }
                }
            }
            .listStyle(.sidebar)
            .emptyOverlay(repository.tags.isEmpty, "No tags", symbol: "tag")
            .accessibilityIdentifier("tags-list")
        }
        .onChange(of: repository.tagSelection, initial: true) { show() }
    }

    private func show() {
        guard let tag = repository.tags.first(where: { $0.id == repository.tagSelection }) else {
            Task { await repository.commitViewer.show(.fixed([])) }
            return
        }
        Task {
            guard let commit = await repository.commit(for: tag.commit) else { return }
            await repository.commitViewer.show(.fixed([commit]))
            await repository.commitViewer.select(commit.id)
        }
    }

    @ViewBuilder
    private func menu(for tag: GitTag) -> some View {
        Button("Checkout (Detached HEAD)") { act("Checking out…") { try $0.git.run(["switch", "--detach", "refs/tags/\(tag.name)"]) } }
        Button("New Branch from Tag…") { branch(from: tag) }
        Divider()
        ForEach(repository.remotes) { remote in
            Button("Push to \(remote.name)") {
                app.run {
                    try await repository.perform("Pushing tag…", cancellable: true, serialized: false) { client, token in
                        try client.pushTag(tag.name, to: remote.name, cancellation: token)
                    }
                }
            }
        }
        Button("Delete…", role: .destructive) {
            repository.confirm(PendingConfirmation(title: "Delete tag \(tag.name)?", message: "Only the local tag is deleted.",
                                                   confirmTitle: "Delete Tag") { act("Deleting tag…") { try $0.deleteTag(tag.name) } })
        }
        ForEach(repository.remotes) { remote in
            Button("Delete on \(remote.name)…", role: .destructive) {
                repository.confirm(PendingConfirmation(title: "Delete \(tag.name) on \(remote.name)?", message: "The tag is removed from the remote repository.",
                                                       confirmTitle: "Delete on Remote") {
                    app.run {
                        try await repository.perform("Deleting remote tag…", cancellable: true, serialized: false) { client, token in
                            try client.deleteRemoteTag(tag.name, on: remote.name, cancellation: token)
                        }
                    }
                })
            }
        }
        Divider()
        Button("Copy Name") { Clipboard.copy(tag.name) }
    }

    private func act(_ title: String, _ work: @escaping @Sendable (GitClient) throws -> Void) {
        app.run { try await repository.perform(title) { client, _ in try work(client) } }
    }

    private func newTag(annotated: Bool) {
        repository.ask(PendingPrompt(title: annotated ? "New Annotated Tag" : "New Tag", message: "At the current commit.",
                                     placeholder: "Tag name", confirmTitle: annotated ? "Next" : "Create") { name in
            let name = name.trimmingCharacters(in: .whitespaces)
            guard annotated else {
                act("Tagging…") { try $0.createTag(name) }
                return
            }
            repository.messageEdit = PendingMessageEdit(title: "Message for \(name)", initialText: "", confirmTitle: "Create Tag") { text in
                act("Tagging…") { try $0.createTag(name, message: text) }
            }
        })
    }

    private func branch(from tag: GitTag) {
        repository.ask(PendingPrompt(title: "New Branch from \(tag.name)", message: "", placeholder: "Branch name", confirmTitle: "Create") { name in
            app.run { try await repository.createBranch(name.trimmingCharacters(in: .whitespaces), from: "refs/tags/\(tag.name)") }
        })
    }
}

/// Where HEAD has been: the safety net behind undo.
struct ReflogSidebar: View {
    @Bindable var repository: RepositoryModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ListActionBar {
                Button { app.run { try await repository.undoHeadMove() } } label: {
                    Label("Undo Last Move", systemImage: "arrow.uturn.backward")
                }
                .help("Move HEAD back to where it was before the latest entry. Doing it again redoes it.")
                .accessibilityIdentifier("reflog-undo")
            }
            List(selection: $repository.reflogSelection) {
                ForEach(repository.reflog) { entry in
                    SimpleRow(symbol: "arrow.uturn.backward.circle", title: entry.message,
                              subtitle: entry.date.formatted(.relative(presentation: .named)),
                              trailing: entry.shortHash, identifier: "reflog-\(entry.selector)")
                        .tag(entry.id)
                        .contextMenu { menu(for: entry) }
                }
            }
            .listStyle(.sidebar)
            .emptyOverlay(repository.reflog.isEmpty, "Nothing in the reflog", symbol: "arrow.uturn.backward.circle")
            .accessibilityIdentifier("reflog-list")
        }
        .onChange(of: repository.reflogSelection, initial: true) { show() }
    }

    private func show() {
        guard let entry = repository.reflog.first(where: { $0.id == repository.reflogSelection }) else {
            Task { await repository.commitViewer.show(.fixed([])) }
            return
        }
        Task {
            guard let commit = await repository.commit(for: entry.hash) else { return }
            await repository.commitViewer.show(.fixed([commit]))
            await repository.commitViewer.select(commit.id)
        }
    }

    @ViewBuilder
    private func menu(for entry: GitReflogEntry) -> some View {
        Button("Checkout (Detached HEAD)") { act("Checking out…") { try $0.git.run(["switch", "--detach", entry.hash]) } }
        Button("New Branch from Here…") {
            repository.ask(PendingPrompt(title: "New Branch", message: "At \(entry.shortHash).", placeholder: "Branch name", confirmTitle: "Create") { name in
                app.run { try await repository.createBranch(name.trimmingCharacters(in: .whitespaces), from: entry.hash) }
            })
        }
        Menu("Reset Current Branch to Here") {
            ForEach(ResetMode.allCases, id: \.self) { mode in
                Button(mode.rawValue.capitalized + (mode == .hard ? "…" : "")) { reset(entry, mode) }
            }
        }
        Button("Copy for Cherry-Pick") {
            Task { if let commit = await repository.commit(for: entry.hash) { repository.copyCommits([commit]) } }
        }
        Button("Copy Hash") { Clipboard.copy(entry.hash) }
    }

    private func reset(_ entry: GitReflogEntry, _ mode: ResetMode) {
        let run = { act("Resetting…") { try $0.reset(to: entry.hash, mode: mode) } }
        if mode == .hard {
            repository.confirm(PendingConfirmation(title: "Hard reset to \(entry.shortHash)?", message: "Uncommitted changes are lost.",
                                                   confirmTitle: "Hard Reset", action: run))
        } else {
            run()
        }
    }

    private func act(_ title: String, _ work: @escaping @Sendable (GitClient) throws -> Void) {
        app.run { try await repository.perform(title) { client, _ in try work(client) } }
    }
}

#if DEBUG
#Preview("Tags sidebar") {
    PreviewRepository(width: 340, height: 500) { repository, app in
        TagsSidebar(repository: repository, app: app)
    }
}
#endif

#if DEBUG
#Preview("Reflog sidebar") {
    PreviewRepository(width: 340, height: 500) { repository, app in
        ReflogSidebar(repository: repository, app: app)
    }
}
#endif
