import LFKit
import SwiftUI

/// Remotes with their branches; add, rename, re-point, fetch, prune and remove them.
struct RemotesSidebar: View {
    @Bindable var repository: RepositoryModel
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ListActionBar {
                Button { addRemote() } label: { Label("Add Remote", systemImage: "plus") }
                    .accessibilityIdentifier("add-remote")
            }
            List(selection: $repository.remoteSelection) {
                ForEach(repository.remotes) { remote in
                    SimpleRow(symbol: "externaldrive.connected.to.line.below", title: remote.name, subtitle: remote.fetchURL,
                              identifier: "remote-\(remote.name)")
                        .tag(remote.id)
                        .contextMenu { menu(for: remote) }
                }
            }
            .listStyle(.sidebar)
            .emptyOverlay(repository.remotes.isEmpty, "No remotes", symbol: "externaldrive")
            .accessibilityIdentifier("remotes-list")
        }
    }

    @ViewBuilder
    private func menu(for remote: GitRemote) -> some View {
        Button("Fetch") { remoteAct("Fetching \(remote.name)…") { try $0.fetchRemote(remote.name, cancellation: $1) } }
        Button("Prune Stale Branches") { remoteAct("Pruning \(remote.name)…") { try $0.pruneRemote(remote.name, cancellation: $1) } }
        Divider()
        Button("Edit URL…") {
            repository.ask(PendingPrompt(title: "URL of \(remote.name)", message: "", placeholder: "https://…", initialText: remote.fetchURL,
                                         confirmTitle: "Save") { url in
                act("Updating remote…") { try $0.setRemoteURL(remote.name, url: url.trimmingCharacters(in: .whitespaces)) }
            })
        }
        Button("Rename…") {
            repository.ask(PendingPrompt(title: "Rename \(remote.name)", message: "", placeholder: "Name", initialText: remote.name,
                                         confirmTitle: "Rename") { name in
                act("Renaming remote…") { try $0.renameRemote(remote.name, to: name.trimmingCharacters(in: .whitespaces)) }
            })
        }
        Button("Remove…", role: .destructive) {
            repository.confirm(PendingConfirmation(title: "Remove remote \(remote.name)?", message: "Its remote-tracking branches are deleted locally. The remote repository itself is untouched.",
                                                   confirmTitle: "Remove") { act("Removing remote…") { try $0.removeRemote(remote.name) } })
        }
        Divider()
        Button("Copy URL") { Clipboard.copy(remote.fetchURL) }
    }

    private func act(_ title: String, _ work: @escaping @Sendable (GitClient) throws -> Void) {
        app.run { try await repository.perform(title) { client, _ in try work(client) } }
    }

    private func remoteAct(_ title: String, _ work: @escaping @Sendable (GitClient, GitCancellation) throws -> Void) {
        app.run { try await repository.perform(title, cancellable: true, serialized: false, work) }
    }

    private func addRemote() {
        repository.ask(PendingPrompt(title: "Add Remote", message: "Name, for example origin or upstream.", placeholder: "Name",
                                     confirmTitle: "Next") { name in
            let name = name.trimmingCharacters(in: .whitespaces)
            repository.ask(PendingPrompt(title: "URL of \(name)", message: "", placeholder: "https://… or git@…", confirmTitle: "Add") { url in
                act("Adding remote…") { try $0.addRemote(name, url: url.trimmingCharacters(in: .whitespaces)) }
            })
        })
    }
}

/// The branches of the selected remote.
struct RemotesDetail: View {
    let repository: RepositoryModel
    let app: AppModel

    private var branches: [GitBranch] {
        guard let name = repository.remoteSelection else { return [] }
        return repository.branches.filter { $0.isRemote && $0.name.hasPrefix(name + "/") }
    }

    var body: some View {
        Group {
            if let name = repository.remoteSelection, let remote = repository.remotes.first(where: { $0.name == name }) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(remote.name).font(.headline).foregroundStyle(.theme(.text))
                        Text(remote.fetchURL).font(.callout.monospaced()).foregroundStyle(.theme(.textSubtle)).textSelection(.enabled)
                        if remote.pushURL != remote.fetchURL {
                            Text("push: \(remote.pushURL)").font(.caption.monospaced()).foregroundStyle(.theme(.textSubtle))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.theme(.surfaceRaised))
                    Divider()
                    List(branches) { branch in
                        SimpleRow(symbol: "cloud", title: String(branch.name.dropFirst(name.count + 1)), trailing: branch.tip,
                                  identifier: "remote-branch-\(branch.name)")
                            .contextMenu { BranchContextMenu(repository: repository, app: app, branch: branch) }
                    }
                    .emptyOverlay(branches.isEmpty, "No fetched branches", symbol: "cloud")
                }
            } else {
                ContentUnavailableView("Select a remote", systemImage: "externaldrive.connected.to.line.below")
            }
        }
        .background(.theme(.background))
    }
}

#if DEBUG
#Preview("Remotes sidebar") {
    PreviewRepository(width: 340, height: 500) { repository, app in
        RemotesSidebar(repository: repository, app: app)
    }
}
#endif

#if DEBUG
#Preview("Remotes detail") {
    PreviewRepository(width: 700, height: 500) { repository, app in
        RemotesDetail(repository: repository, app: app)
    }
}
#endif
