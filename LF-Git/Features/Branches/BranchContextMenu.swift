import LFKit
import SwiftUI

/// Every action on one branch, for the context menu of the branches list.
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
            Menu("Merge into Current Branch…") {
                ForEach(MergeMode.allCases, id: \.self) { mode in
                    Button(mode.title) { merge(mode) }
                }
            }
            Button("Rebase Current Branch onto This…") { rebase() }
            Menu("Reset Current Branch to This") {
                ForEach(ResetMode.allCases, id: \.self) { mode in
                    Button(mode.rawValue.capitalized + "…") { reset(mode) }
                }
            }
            if !branch.isRemote, branch.upstream != nil {
                Button("Fast-Forward from Upstream…") { fastForward() }
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

    private var currentName: String { current?.name ?? "the current branch" }

    /// Asks before something that changes the current branch, naming exactly what is about to happen.
    private func confirmThen(_ title: String, message: String, confirmTitle: String, destructive: Bool = false,
                             _ run: @escaping () -> Void) {
        repository.confirm(PendingConfirmation(title: title, message: message, confirmTitle: confirmTitle,
                                               isDestructive: destructive, action: run))
    }

    private func merge(_ mode: MergeMode) {
        let name = branch.name
        let detail: String = switch mode {
        case .default: "Git fast-forwards when it can, and otherwise creates a merge commit."
        case .noFastForward: "A merge commit is always created."
        case .fastForwardOnly: "Nothing happens unless \(currentName) can simply move forward to \(name)."
        case .squash: "The changes are staged on \(currentName) without a commit."
        }
        confirmThen("Merge ‘\(name)’ into ‘\(currentName)’?", message: detail, confirmTitle: "Merge") {
            act("Merging…") { try $0.mergeBranch(name, mode: mode) }
        }
    }

    private func rebase() {
        let name = branch.name
        confirmThen("Rebase ‘\(currentName)’ onto ‘\(name)’?",
                    message: "The commits of \(currentName) are replayed on top of \(name), which rewrites them. Local edits are stashed and brought back.",
                    confirmTitle: "Rebase") {
            act("Rebasing…") { try $0.rebase(onto: name) }
        }
    }

    private func fastForward() {
        let name = branch.name
        confirmThen("Fast-forward ‘\(name)’ from \(branch.upstream ?? "its upstream")?",
                    message: "\(name) moves forward to the upstream tip. Nothing is merged or rewritten.", confirmTitle: "Fast-Forward") {
            act("Fast-forwarding…") { try $0.fastForward(name) }
        }
    }

    private func reset(_ mode: ResetMode) {
        let name = branch.name
        let detail: String = switch mode {
        case .soft: "\(currentName) moves to \(name); the changes after it stay staged."
        case .mixed: "\(currentName) moves to \(name); the changes after it stay in your files, unstaged."
        case .hard: "Uncommitted changes are lost, and \(currentName) moves to \(name)."
        }
        confirmThen("\(mode.rawValue.capitalized) reset ‘\(currentName)’ to ‘\(name)’?", message: detail,
                    confirmTitle: "\(mode.rawValue.capitalized) Reset", destructive: mode == .hard) {
            act("Resetting…") { try $0.reset(to: name, mode: mode) }
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

