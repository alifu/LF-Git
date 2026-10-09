import LFKit
import SwiftUI

/// Local and remote branches, with every branch action in the context menu.
struct BranchesSidebar: View {
    @Bindable var repository: RepositoryModel
    let app: AppModel

    private var locals: [GitBranch] { repository.branches.filter { !$0.isRemote } }
    private var remotes: [GitBranch] { repository.branches.filter(\.isRemote) }

    var body: some View {
        VStack(spacing: 0) {
            ListActionBar {
                Button { newBranch(from: nil) } label: { Label("New Branch", systemImage: "plus") }
                    .accessibilityIdentifier("new-branch")
                Button { app.run { try await repository.perform("Switching…") { client, _ in try client.switchPrevious() } } } label: {
                    Label("Previous", systemImage: "arrow.uturn.backward")
                }
                .help("Check out the previously checked-out branch")
            }
            List(selection: $repository.branchSelection) {
                Section("Local · \(locals.count)") {
                    ForEach(locals) { branch in
                        row(branch).tag(branch.id)
                    }
                }
                if !remotes.isEmpty {
                    Section("Remote · \(remotes.count)") {
                        ForEach(remotes) { branch in
                            row(branch).tag(branch.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("branches-list")
        }
        .onChange(of: repository.branchSelection, initial: true) { showHistory() }
        .onChange(of: repository.branches) { showHistory() }
    }

    private func row(_ branch: GitBranch) -> some View {
        SimpleRow(
            symbol: branch.isCurrent ? "checkmark.circle.fill" : (branch.isRemote ? "cloud" : "arrow.triangle.branch"),
            symbolToken: branch.isCurrent ? .accent : .textSubtle, title: branch.name,
            subtitle: branch.upstream.map { "tracks \($0)" }, trailing: branch.tip, identifier: "branch-\(branch.name)"
        )
        .contextMenu { BranchContextMenu(repository: repository, app: app, branch: branch) }
    }

    private func showHistory() {
        let id = repository.branchSelection ?? repository.branches.first { $0.isCurrent }?.id
        guard let branch = repository.branches.first(where: { $0.id == id }) else { return }
        Task { await repository.branchHistory.show(.log(revision: branch.name)) }
    }

    private func newBranch(from start: String?) {
        repository.ask(PendingPrompt(title: "New Branch", message: start.map { "Created from \($0) and switched to." } ?? "Created from the current commit and switched to.",
                                     placeholder: "Branch name", confirmTitle: "Create") { name in
            app.run { try await repository.createBranch(name.trimmingCharacters(in: .whitespaces), from: start) }
        })
    }
}

/// The commits of the selected branch, and the selected commit.
struct BranchesDetail: View {
    let repository: RepositoryModel
    let app: AppModel

    var body: some View {
        HSplitView {
            CommitListView(repository: repository, app: app, model: repository.branchHistory)
                .frame(minWidth: 300, idealWidth: 380)
            HistoryDetailView(repository: repository, app: app, model: repository.branchHistory)
                .frame(minWidth: 320)
        }
        .background(.theme(.background))
    }
}

struct BranchContextMenu: View {
    let repository: RepositoryModel
    let app: AppModel
    let branch: GitBranch

    private var current: GitBranch? { repository.currentBranch }
    private var remoteName: String? { branch.isRemote ? branch.name.split(separator: "/").first.map(String.init) : nil }
    private var branchOnRemote: String { branch.name.split(separator: "/", maxSplits: 1).dropFirst().first.map(String.init) ?? branch.name }

    var body: some View {
        Button("Checkout") { act("Switching to \(branch.name)…") { try $0.switchBranch(branch.name) } }
            .disabled(branch.isCurrent)
        Button("Checkout, Discarding Local Changes…") {
            repository.confirm(PendingConfirmation(title: "Discard local changes and switch?", message: "Edits that conflict with \(branch.name) are lost.",
                                                   confirmTitle: "Discard and Switch") {
                act("Switching…") { try $0.switchBranch(branch.name, discardChanges: true) }
            })
        }
        .disabled(branch.isCurrent || branch.isRemote)
        Button("New Branch from Here…") { newBranchHere() }
        if !branch.isRemote {
            Button("Rename…") { rename() }
        }
        if !branch.isCurrent {
            Divider()
            Menu("Merge into Current Branch") {
                ForEach(MergeMode.allCases, id: \.self) { mode in
                    Button(mode.title) { act("Merging…") { try $0.mergeBranch(branch.name, mode: mode) } }
                }
            }
            Button("Rebase Current Branch onto This") { act("Rebasing…") { try $0.rebase(onto: branch.name) } }
            Menu("Reset Current Branch to This") {
                ForEach(ResetMode.allCases, id: \.self) { mode in
                    Button(mode.rawValue.capitalized + (mode == .hard ? "…" : "")) { reset(mode) }
                }
            }
            if !branch.isRemote, branch.upstream != nil {
                Button("Fast-Forward from Upstream") { act("Fast-forwarding…") { try $0.fastForward(branch.name) } }
            }
            Button("Compare with Current Branch") {
                Task { await repository.branchHistory.compare(from: "HEAD", to: branch.name) }
            }
        }
        if !branch.isRemote {
            Divider()
            Button("Set Upstream…") { setUpstream() }
            Button("Unset Upstream") { act("Unsetting upstream…") { try $0.unsetUpstream(of: branch.name) } }
                .disabled(branch.upstream == nil)
            Button("Delete…", role: .destructive) { delete() }
                .disabled(branch.isCurrent)
        } else if let remote = remoteName {
            Divider()
            Button("Delete Branch on \(remote)…", role: .destructive) { deleteRemote(remote) }
        }
        Divider()
        Button("Copy Name") { Clipboard.copy(branch.name) }
    }

    private func act(_ title: String, _ work: @escaping @Sendable (GitClient) throws -> Void) {
        app.run { try await repository.perform(title, cancellable: false) { client, _ in try work(client) } }
    }

    private func newBranchHere() {
        let start = branch.name
        repository.ask(PendingPrompt(title: "New Branch", message: "Created from \(start) and switched to.",
                                     placeholder: "Branch name", confirmTitle: "Create") { name in
            app.run { try await repository.createBranch(name.trimmingCharacters(in: .whitespaces), from: start) }
        })
    }

    private func rename() {
        let old = branch.name
        repository.ask(PendingPrompt(title: "Rename \(old)", message: "", placeholder: "New name", initialText: old,
                                     confirmTitle: "Rename") { name in
            act("Renaming…") { try $0.renameBranch(old, to: name.trimmingCharacters(in: .whitespaces)) }
        })
    }

    private func setUpstream() {
        let name = branch.name
        repository.ask(PendingPrompt(title: "Set Upstream of \(name)", message: "A remote branch such as origin/main.",
                                     placeholder: "origin/main", initialText: branch.upstream ?? "", confirmTitle: "Set") { upstream in
            act("Setting upstream…") { try $0.setUpstream(of: name, to: upstream.trimmingCharacters(in: .whitespaces)) }
        })
    }

    private func reset(_ mode: ResetMode) {
        let name = branch.name
        let run = { act("Resetting…") { try $0.reset(to: name, mode: mode) } }
        if mode == .hard {
            repository.confirm(PendingConfirmation(title: "Hard reset to \(name)?",
                                                   message: "Uncommitted changes are lost, and the current branch moves to \(name).",
                                                   confirmTitle: "Hard Reset", action: run))
        } else {
            run()
        }
    }

    private func delete() {
        let name = branch.name
        repository.confirm(PendingConfirmation(
            title: "Delete \(name)?", message: "Git refuses if the branch has commits that are not merged; then you can force it.",
            confirmTitle: "Delete"
        ) {
            app.run {
                do {
                    try await repository.deleteBranch(name)
                } catch {
                    repository.confirm(PendingConfirmation(title: "Force delete \(name)?", message: "\(error)", confirmTitle: "Force Delete") {
                        app.run { try await repository.deleteBranch(name, force: true) }
                    })
                }
            }
        })
    }

    private func deleteRemote(_ remote: String) {
        let name = branchOnRemote
        repository.confirm(PendingConfirmation(title: "Delete \(name) on \(remote)?", message: "The branch is removed from the remote repository.",
                                               confirmTitle: "Delete on Remote") {
            app.run {
                try await repository.perform("Deleting on \(remote)…", cancellable: true, serialized: false) { client, token in
                    try client.deleteRemoteBranch(name, on: remote, cancellation: token)
                }
            }
        })
    }
}
