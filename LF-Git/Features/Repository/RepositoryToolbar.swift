import LFKit
import SwiftUI

/// The branch menu: a popover with a search box to switch to a branch, plus create and delete.
struct BranchMenu: View {
    let repository: RepositoryModel
    let app: AppModel
    @State private var isOpen = false
    @State private var query = ""
    @State private var creating = false
    @State private var newName = ""
    @State private var deleting: GitBranch?
    @FocusState private var searchFocused: Bool

    private var searchText: String { query.trimmingCharacters(in: .whitespaces) }
    private var locals: [GitBranch] { matching(repository.branches.filter { !$0.isRemote }) }
    private var remotes: [GitBranch] { matching(repository.branches.filter(\.isRemote)) }

    private func matching(_ list: [GitBranch]) -> [GitBranch] {
        searchText.isEmpty ? list : list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Button { isOpen.toggle() } label: {
            // An explicit HStack: toolbar Labels show only their icon.
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                Text(repository.status.branch ?? "Detached HEAD").lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
        }
        .help("Switch or create a branch")
        .accessibilityIdentifier("branch-menu")
        .disabled(repository.isBusy || repository.operation != nil)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) { popover }
        .onChange(of: isOpen) { _, open in
            if open { query = "" }
        }
        .alert("New Branch", isPresented: $creating) {
            TextField("Branch name", text: $newName)
            Button("Create") { run { try await repository.createBranch(newName.trimmingCharacters(in: .whitespaces)) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Created from the current commit and switched to.")
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "branch")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let name = deleting?.name { run { try await repository.deleteBranch(name) } }
            }
        } message: {
            Text("Git refuses if the branch has commits that are not merged.")
        }
    }

    private var popover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.theme(.textSubtle))
                TextField("Search branches", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { if let first = locals.first(where: { !$0.isCurrent }) ?? remotes.first { choose(first) } }
                    .accessibilityIdentifier("branch-menu-search")
            }
            .padding(10)
            Divider()
            List {
                if locals.isEmpty && remotes.isEmpty {
                    Text("No branches match").foregroundStyle(.theme(.textSubtle))
                }
                if !locals.isEmpty {
                    Section("Branches") { ForEach(locals) { branchRow($0) } }
                }
                if !remotes.isEmpty {
                    Section("Remote Branches") { ForEach(remotes) { branchRow($0) } }
                }
            }
            .listStyle(.plain)
            .frame(height: 260)
            Divider()
            HStack {
                Button("New Branch…") {
                    isOpen = false
                    newName = ""
                    creating = true
                }
                .accessibilityIdentifier("branch-menu-new")
                Spacer()
                Menu("Delete Branch") {
                    ForEach(repository.branches.filter { !$0.isRemote && !$0.isCurrent }) { branch in
                        Button(branch.name, role: .destructive) {
                            isOpen = false
                            deleting = branch
                        }
                    }
                }
                .fixedSize()
                .disabled(repository.branches.filter { !$0.isRemote }.count < 2)
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .frame(width: 300)
        .onAppear { searchFocused = true }
    }

    private func branchRow(_ branch: GitBranch) -> some View {
        Button { choose(branch) } label: {
            Label(branch.name, systemImage: branch.isCurrent ? "checkmark" : (branch.isRemote ? "cloud" : "arrow.triangle.branch"))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(branch.isCurrent)
        .accessibilityIdentifier("branch-menu-\(branch.name)")
    }

    private func choose(_ branch: GitBranch) {
        isOpen = false
        switchTo(branch.name)
    }

    private func switchTo(_ name: String) {
        run { try await repository.switchBranch(name) }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { app.report(error) }
        }
    }
}

/// Fetch, pull and push, with how far ahead or behind the branch is.
struct RemoteButtons: View {
    let repository: RepositoryModel
    let app: AppModel

    var body: some View {
        HStack(spacing: 4) {
            if let title = repository.busyTitle {
                ProgressView().controlSize(.small)
                Text(title).font(.caption).foregroundStyle(.theme(.textSubtle))
                if repository.isCancellable {
                    Button("Cancel") { repository.cancelBusy() }
                        .help("Stop the running command")
                        .accessibilityIdentifier("cancel-operation")
                }
            }
            Group {
            if !repository.copiedCommits.isEmpty {
                Menu {
                    Button("Paste (Cherry-Pick)…") { repository.requestPaste(app: app) }
                    Button("Clear") { repository.clearCopiedCommits() }
                } label: {
                    Label("\(repository.copiedCommits.count)", systemImage: "doc.on.clipboard")
                }
                .help("\(repository.copiedCommits.count) commit(s) copied for cherry-pick")
                .accessibilityIdentifier("copied-commits")
            }
            Button { run { try await repository.fetch() } } label: {
                Label("Fetch", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Fetch from the remote (⌥⌘F)")
            .accessibilityIdentifier("fetch")
            Menu {
                Button("Pull (fast-forward only)") { run { try await repository.pull(.fastForwardOnly) } }
                Button("Pull and merge…") { repository.requestPull(.merge, app: app) }
                Button("Pull and rebase…") { repository.requestPull(.rebase, app: app) }
            } label: {
                countLabel("arrow.down", repository.status.behind, name: "Pull")
            } primaryAction: {
                run { try await repository.pull(.fastForwardOnly) }
            }
            .help("Pull (⌥⌘L)")
            .accessibilityIdentifier("pull")
            Menu {
                Button("Push") { run { try await repository.push() } }
                Button("Force Push (with lease)…") {
                    repository.confirm(PendingConfirmation(
                        title: "Force push \(repository.status.branch ?? "this branch")?",
                        message: "The remote branch is overwritten, unless somebody else pushed to it since your last fetch.",
                        confirmTitle: "Force Push") { run { try await repository.push(force: true) } })
                }
            } label: {
                countLabel("arrow.up", repository.status.ahead, name: "Push")
            } primaryAction: {
                run { try await repository.push() }
            }
            .help(repository.status.upstream == nil ? "Publish this branch (⌥⌘P)" : "Push (⌥⌘P)")
            .accessibilityIdentifier("push")
            }
            .disabled(repository.isBusy || repository.operation != nil)
        }
    }

    /// The arrow, with how many commits are waiting next to it.
    private func countLabel(_ symbol: String, _ count: Int, name: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
            if count > 0 {
                Text("\(count)").font(.caption.monospacedDigit().weight(.semibold))
            }
        }
        .accessibilityLabel(count > 0 ? "\(name), \(count) commits" : name)
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { app.report(error) }
        }
    }
}

/// "Merge in progress": continue, skip or abort.
struct OperationBanner: View {
    let repository: RepositoryModel
    let app: AppModel
    @State private var confirmingAbort = false

    var body: some View {
        if let operation = repository.operation {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.theme(.warning))
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(operation.title) in progress").font(.headline)
                    Text(repository.files.isEmpty
                        ? "Every conflict is resolved. Continue to finish."
                        : "\(repository.files.count) conflicted file\(repository.files.count == 1 ? "" : "s") left.")
                        .font(.caption)
                        .foregroundStyle(.theme(.textSubtle))
                }
                Spacer()
                if !repository.files.isEmpty && repository.section != .conflicts {
                    Button("Show Conflicts") { repository.section = .conflicts }
                }
                if operation == .rebase || operation == .cherryPick {
                    Button("Skip") { run { try await repository.skipOperation() } }
                        .accessibilityIdentifier("operation-skip")
                }
                Button("Abort", role: .destructive) { confirmingAbort = true }
                    .accessibilityIdentifier("operation-abort")
                Button("Continue") { run { try await repository.continueOperation() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!repository.files.isEmpty || repository.isBusy)
                    .accessibilityIdentifier("operation-continue")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.theme(.surfaceRaised))
            .overlay(alignment: .bottom) { Divider() }
            .confirmationDialog("Abort the \(operation.title.lowercased())?", isPresented: $confirmingAbort, titleVisibility: .visible) {
                Button("Abort \(operation.title)", role: .destructive) { run { try await repository.abortOperation() } }
            } message: {
                Text("Everything done by the \(operation.title.lowercased()) so far is undone, including conflict resolutions.")
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { app.report(error) }
        }
    }
}

#if DEBUG
#Preview("Branch menu") {
    PreviewRepository() { repository, app in
        BranchMenu(repository: repository, app: app).padding()
    }
}
#endif

#if DEBUG
#Preview("Fetch / pull / push") {
    PreviewRepository() { repository, app in
        RemoteButtons(repository: repository, app: app).padding()
    }
}
#endif

#if DEBUG
#Preview("Operation banner") {
    PreviewRepository(width: 700) { repository, app in
        OperationBanner(repository: repository, app: app)
    }
}
#endif
