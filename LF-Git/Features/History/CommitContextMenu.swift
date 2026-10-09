import LFKit
import SwiftUI

/// Everything that can be done to one commit (or a few selected ones).
struct CommitContextMenu: View {
    let repository: RepositoryModel
    let app: AppModel
    let model: HistoryModel
    let commits: [GitCommit]

    private var commit: GitCommit { commits[0] }
    /// History can only be rewritten on the checked-out branch.
    private var canRewrite: Bool {
        if case .log(let revision) = model.source { return revision == nil && repository.operation == nil }
        return false
    }
    private var isFirst: Bool { model.commits.first?.hash == commit.hash }
    private var isLast: Bool { commit.parents.isEmpty }

    var body: some View {
        if commits.count > 1 {
            Button("Copy \(commits.count) Commits for Cherry-Pick") { repository.copyCommits(commits.reversed()) }
            Button("Compare the Two Ends") {
                if let newest = commits.first, let oldest = commits.last {
                    Task { await model.compare(from: oldest.hash, to: newest.hash) }
                }
            }
        } else {
            single
        }
    }

    @ViewBuilder
    private var single: some View {
        let commit = commit
        Section("Copy") {
            Button("Copy for Cherry-Pick") { repository.copyCommits([commit]) }
            Button("Copy Hash") { Clipboard.copy(commit.hash) }
            Button("Copy Subject") { Clipboard.copy(commit.subject) }
        }
        if !repository.copiedCommits.isEmpty {
            Button("Paste \(repository.copiedCommits.count) Copied Commit\(repository.copiedCommits.count == 1 ? "" : "s") Here (Cherry-Pick)") {
                app.run { try await repository.pasteCopiedCommits() }
            }
            Button("Clear Copied Commits") { repository.clearCopiedCommits() }
        }
        if canRewrite {
            Section("Rewrite History") {
                Button("Reword…") { reword() }
                Button("Edit (stop here)") { act("Starting edit…") { try $0.editCommit(commit) } }
                Button("Squash into Previous") { act("Squashing…") { try $0.squashCommit(commit) } }
                    .disabled(isLast)
                Button("Fixup into Previous") { act("Fixing up…") { try $0.fixupCommit(commit) } }
                    .disabled(isLast)
                Button("Drop…", role: .destructive) { drop() }
                Button("Move Up") { act("Moving…") { try $0.moveCommitUp(commit) } }
                    .disabled(isFirst)
                Button("Move Down") { act("Moving…") { try $0.moveCommitDown(commit) } }
                    .disabled(isLast)
                Button("Amend with Staged Changes") { act("Amending…") { try $0.amendCommit(commit) } }
                    .disabled(repository.status.staged.isEmpty)
                Button("Create Fixup Commit from Staged Changes") { act("Creating fixup…") { try $0.createFixupCommit(for: commit) } }
                    .disabled(repository.status.staged.isEmpty)
                Button("Squash All Fixup Commits Above") { act("Squashing fixups…") { try $0.autosquash(above: commit) } }
            }
        }
        Section("Apply") {
            Button("Revert…") { revert() }
            Menu("Reset Current Branch to Here") {
                ForEach(ResetMode.allCases, id: \.self) { mode in
                    Button(mode.rawValue.capitalized + (mode == .hard ? "…" : "")) { reset(mode) }
                }
            }
            Button("Checkout (Detached HEAD)") { act("Checking out…") { try $0.checkoutDetached(commit) } }
            Button("New Branch from Here…") { newBranch() }
            Button("New Tag Here…") { newTag(annotated: false) }
            Button("New Annotated Tag Here…") { newTag(annotated: true) }
        }
        Section("Compare and Search") {
            if let base = repository.compareBase, base.hash != commit.hash {
                Button("Compare with Selected (\(base.shortHash))") {
                    Task { await model.compare(from: base.hash, to: commit.hash) }
                }
            }
            Button("Select for Compare") { repository.compareBase = commit }
            Button("Compare with HEAD") {
                Task { await model.compare(from: commit.hash, to: "HEAD") }
            }
            Divider()
            Button("Bisect: Mark as Bad") { app.run { try await repository.markForBisect(.bad, commit: commit) } }
            Button("Bisect: Mark as Good") { app.run { try await repository.markForBisect(.good, commit: commit) } }
        }
    }

    // MARK: Actions

    private func act(_ title: String, _ work: @escaping @Sendable (GitClient) throws -> Void) {
        app.run { try await repository.perform(title) { client, _ in try work(client) } }
    }

    private func reword() {
        let commit = commit
        app.run {
            let message = try await repository.message(of: commit)
            repository.messageEdit = PendingMessageEdit(title: "Reword Commit", initialText: message, confirmTitle: "Reword") { text in
                act("Rewording…") { try $0.rewordCommit(commit, message: text) }
            }
        }
    }

    private func drop() {
        let commit = commit
        repository.confirm(PendingConfirmation(
            title: "Drop “\(commit.subject)”?", message: "The commit and its changes are removed from the history.",
            confirmTitle: "Drop Commit"
        ) { act("Dropping…") { try $0.dropCommit(commit) } })
    }

    private func revert() {
        let commit = commit
        repository.confirm(PendingConfirmation(
            title: "Revert “\(commit.subject)”?", message: "A new commit that undoes it is added.",
            confirmTitle: "Revert", isDestructive: false
        ) { act("Reverting…") { try $0.revert(commit) } })
    }

    private func reset(_ mode: ResetMode) {
        let commit = commit
        let run = { act("Resetting…") { try $0.reset(to: commit.hash, mode: mode) } }
        if mode == .hard {
            repository.confirm(PendingConfirmation(
                title: "Hard reset to \(commit.shortHash)?",
                message: "Uncommitted changes and the commits after it are lost from this branch (the reflog keeps them for a while).",
                confirmTitle: "Hard Reset", action: run))
        } else {
            run()
        }
    }

    private func newBranch() {
        let hash = commit.hash
        repository.ask(PendingPrompt(title: "New Branch", message: "Created at \(commit.shortHash) and switched to.",
                                     placeholder: "Branch name", confirmTitle: "Create") { name in
            app.run { try await repository.createBranch(name.trimmingCharacters(in: .whitespaces), from: hash) }
        })
    }

    private func newTag(annotated: Bool) {
        let hash = commit.hash
        repository.ask(PendingPrompt(title: annotated ? "New Annotated Tag" : "New Tag", message: "At \(commit.shortHash).",
                                     placeholder: "Tag name", confirmTitle: annotated ? "Next" : "Create") { name in
            let name = name.trimmingCharacters(in: .whitespaces)
            guard annotated else {
                act("Tagging…") { try $0.createTag(name, at: hash) }
                return
            }
            repository.messageEdit = PendingMessageEdit(title: "Message for \(name)", initialText: "", confirmTitle: "Create Tag") { text in
                act("Tagging…") { try $0.createTag(name, at: hash, message: text) }
            }
        })
    }
}
