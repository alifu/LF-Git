import LFKit
import SwiftUI

/// The branch menu: a popover to switch to a branch, plus create and delete. Local and remote branches each have
/// their own list and search box; the remote list starts folded so it is opened on purpose.
struct BranchMenu: View {
    let repository: RepositoryModel
    let app: AppModel
    @State private var isOpen = false
    @State private var localQuery = ""
    @State private var remoteQuery = ""
    /// Remote branches start folded away so a stray click cannot check one out; reset on every open.
    @State private var showsRemotes = false
    @State private var deleting: GitBranch?
    @FocusState private var localSearchFocused: Bool
    @FocusState private var remoteSearchFocused: Bool

    private static let listHeight: CGFloat = 260
    private static let splitListHeight: CGFloat = 160

    private var allLocals: [GitBranch] { repository.branches.filter { !$0.isRemote } }
    private var allRemotes: [GitBranch] { repository.branches.filter(\.isRemote) }
    private var locals: [GitBranch] { BranchMenuFilter.matching(allLocals, query: localQuery, name: \.name) }
    private var remotes: [GitBranch] { BranchMenuFilter.matching(allRemotes, query: remoteQuery, name: \.name) }

    var body: some View {
        Button { isOpen.toggle() } label: {
            // An explicit HStack: toolbar Labels show only their icon.
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(.theme(.textSubtle))
                Text(repository.status.branch ?? "Detached HEAD")
                    .foregroundStyle(.theme(.textSubtle))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.theme(.textSubtle))
            }
        }
        .help("Switch or create a branch")
        .accessibilityIdentifier("branch-menu")
        .disabled(repository.isBusy || repository.operation != nil)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) { popover }
        .onChange(of: isOpen) { _, open in
            guard open else { return }
            localQuery = ""
            remoteQuery = ""
            showsRemotes = false
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "branch")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete") {
                if let name = deleting?.name { run { try await repository.deleteBranch(name) } }
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text("Git refuses if the branch has commits that are not merged.")
        }
    }

    private var popover: some View {
        VStack(spacing: 0) {
            localSection
            if !allRemotes.isEmpty {
                Divider()
                remoteSection
            }
            Divider()
            HStack {
                Button("New Branch…") {
                    isOpen = false
                    repository.requestNewBranch(app: app)
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
        .onAppear { localSearchFocused = true }
    }

    // MARK: - Local and remote sections

    private var localSection: some View {
        VStack(spacing: 0) {
            sectionTitle("Local Branches", count: locals.count)
            searchField("Search local branches", text: $localQuery, focus: $localSearchFocused, id: "branch-menu-search") {
                switchToFirst(allLocals, query: localQuery)
            }
            Divider()
            branchList(locals, emptyText: "No local branches match", height: showsRemotes ? Self.splitListHeight : Self.listHeight)
                .accessibilityIdentifier("branch-menu-local-list")
        }
    }

    /// Folded by default: a header button the user opens on purpose, on a raised background so it reads as apart.
    private var remoteSection: some View {
        VStack(spacing: 0) {
            Button { toggleRemotes() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(showsRemotes ? 90 : 0))
                    sectionTitleText("Remote Branches", count: remotes.count)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showsRemotes ? "Hide remote branches" : "Show remote branches")
            .accessibilityIdentifier("branch-menu-remote-toggle")
            if showsRemotes {
                searchField("Search remote branches", text: $remoteQuery, focus: $remoteSearchFocused, id: "branch-menu-remote-search") {
                    switchToFirst(allRemotes, query: remoteQuery)
                }
                Divider()
                branchList(remotes, emptyText: "No remote branches match", height: Self.splitListHeight)
                    .accessibilityIdentifier("branch-menu-remote-list")
            }
        }
        .background(.theme(.surfaceRaised))
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        sectionTitleText(title, count: count)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func sectionTitleText(_ title: String, count: Int) -> some View {
        Text("\(title) · \(count)").font(.caption.weight(.semibold)).foregroundStyle(.theme(.textSubtle))
    }

    private func searchField(_ prompt: String, text: Binding<String>, focus: FocusState<Bool>.Binding, id: String,
                             onSubmit: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.theme(.textSubtle))
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .focused(focus)
                .onSubmit(onSubmit)
                .accessibilityIdentifier(id)
        }
        .padding(10)
    }

    private func branchList(_ branches: [GitBranch], emptyText: String, height: CGFloat) -> some View {
        List {
            if branches.isEmpty {
                Text(emptyText).foregroundStyle(.theme(.textSubtle))
            }
            ForEach(branches) { branchRow($0) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(height: height)
    }

    private func toggleRemotes() {
        showsRemotes.toggle()
        if showsRemotes { remoteSearchFocused = true } else { localSearchFocused = true }
    }

    private func switchToFirst(_ branches: [GitBranch], query: String) {
        if let first = BranchMenuFilter.firstSwitchable(branches, query: query, name: \.name, isCurrent: \.isCurrent) { choose(first) }
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

/// Fetch, pull and push as top-bar pills: the upstream and when it was last fetched, a filled call to action while
/// the remote has commits this branch lacks, and push with how many commits are waiting.
struct RemoteButtons: View {
    let repository: RepositoryModel
    let app: AppModel

    private static let fetchClockInterval: TimeInterval = 30

    private var isIdle: Bool { !repository.isBusy && repository.operation == nil }

    var body: some View {
        HStack(spacing: 8) {
            PillGroup {
                remoteMenu
                PillDivider()
                if let title = repository.busyTitle {
                    busySegment(title)
                } else {
                    fetchButton
                }
            }
            if !repository.copiedCommits.isEmpty { copiedCommits }
            if repository.status.behind > 0 { upstreamButton }
            pushMenu
        }
    }

    private var remoteName: String {
        if let upstream = repository.status.upstream { return upstream }
        return repository.remotes.isEmpty ? "No remote" : "Not published"
    }

    private var remoteMenu: some View {
        Menu {
            Button("Fetch") { run { try await repository.fetch() } }
            Divider()
            Button("Pull (fast-forward only)") { run { try await repository.pull(.fastForwardOnly) } }
            Button("Pull and merge…") { repository.requestPull(.merge, app: app) }
            Button("Pull and rebase…") { repository.requestPull(.rebase, app: app) }
            Divider()
            Button("Reload") { Task { await repository.refresh(reloadDiffs: true) } }
        } label: {
            Label(remoteName, systemImage: "dot.radiowaves.left.and.right")
                .foregroundStyle(.theme(.textSubtle))
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 10)
        .disabled(!isIdle)
        .help("Fetch, pull or reload")
        .accessibilityIdentifier("remote-menu")
    }

    private var fetchButton: some View {
        Button { run { try await repository.fetch() } } label: {
            TimelineView(.periodic(from: .now, by: Self.fetchClockInterval)) { context in
                Label(Self.fetchedText(repository.lastFetchDate, now: context.date), systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .disabled(!isIdle)
        .help("Fetch from the remote (⌥⌘F)")
        .accessibilityLabel("Fetch")
        .accessibilityIdentifier("fetch")
    }

    private func busySegment(_ title: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(title).foregroundStyle(.theme(.textSubtle)).lineLimit(1)
            if repository.isCancellable {
                Button("Cancel") { repository.cancelBusy() }
                    .help("Stop the running command")
                    .accessibilityIdentifier("cancel-operation")
            }
        }
        .padding(.trailing, repository.isCancellable ? 0 : 10)
        .padding(.leading, 10)
    }

    /// "3 upstream commits": pulls (fast-forward only) in one click.
    private var upstreamButton: some View {
        let behind = repository.status.behind
        return Button("\(behind) upstream commit\(behind == 1 ? "" : "s")") {
            run { try await repository.pull(.fastForwardOnly) }
        }
        .buttonStyle(.prominentPill)
        .disabled(!isIdle)
        .help("Pull them (fast-forward only, ⌥⌘L)")
        .accessibilityIdentifier("pull")
    }

    private var copiedCommits: some View {
        Menu {
            Button("Paste (Cherry-Pick)…") { repository.requestPaste(app: app) }
            Button("Clear") { repository.clearCopiedCommits() }
        } label: {
            Label("\(repository.copiedCommits.count)", systemImage: "doc.on.clipboard")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .pillChrome()
        .disabled(!isIdle)
        .help("\(repository.copiedCommits.count) commit(s) copied for cherry-pick")
        .accessibilityIdentifier("copied-commits")
    }

    private var pushMenu: some View {
        @Bindable var repository = repository
        return Menu {
            Button("Push") { run { try await repository.push() } }
            Button("Force Push (with lease)…") {
                repository.confirm(PendingConfirmation(
                    title: "Force push \(repository.status.branch ?? "this branch")?",
                    message: "The remote branch is overwritten, unless somebody else pushed to it since your last fetch."
                        + (repository.hasPrePushHook && !repository.runsPushHooks
                           ? "\n\npre-push hooks are off for this repository: the guardrails will be skipped." : ""),
                    confirmTitle: "Force Push") { run { try await repository.push(force: true) } })
            }
            if repository.hasPrePushHook {
                Divider()
                Toggle("Run pre-push hooks", isOn: $repository.runsPushHooks)
                    .accessibilityIdentifier("push-run-hooks")
                Button("Show Hook Output") { repository.showsHooksPanel = true }
                    .disabled(repository.hooks.latest == nil)
            }
        } label: {
            HStack(spacing: 4) {
                countLabel("arrow.up", repository.status.ahead, name: "Push")
                if repository.hasPrePushHook, !repository.runsPushHooks {
                    Image(systemName: "shield.slash").foregroundStyle(.orange).help("pre-push hooks are off for this repository")
                        .accessibilityLabel("Hooks off")
                }
            }
        } primaryAction: {
            run { try await repository.push() }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .pillChrome()
        .disabled(!isIdle)
        .help(repository.status.upstream == nil ? "Publish this branch (⌥⌘P)" : "Push (⌥⌘P)")
        .accessibilityIdentifier("push")
    }

    /// "Push", with how many commits are waiting next to it.
    private func countLabel(_ symbol: String, _ count: Int, name: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(name)
            if count > 0 { CountCapsule(count: count) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count > 0 ? "\(name), \(count) commits" : name)
    }

    /// "Never fetched", "Just now" or "5 min ago".
    static func fetchedText(_ date: Date?, now: Date) -> String {
        guard let date else { return "Never fetched" }
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private func run(_ work: @escaping () async throws -> Void) {
        app.run(work)
    }
}

/// The open repository's name; the menu switches to a recent one, opens another or closes this one.
struct ProjectMenu: View {
    let repository: RepositoryModel
    let app: AppModel

    private var others: [String] {
        app.recentRepositories.filter { $0 != repository.root.standardizedFileURL.path }
    }

    var body: some View {
        Menu {
            if !others.isEmpty {
                Section("Recent") {
                    ForEach(others, id: \.self) { path in
                        Button(URL(fileURLWithPath: path).lastPathComponent) { app.open(URL(fileURLWithPath: path)) }
                            .help(path)
                    }
                }
            }
            Button("Open Repository…") { app.chooseRepository() }
            Button("Close Repository") { app.close() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "book.closed")
                Text(repository.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle).frame(maxWidth: 180)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.theme(.textSubtle))
            }
            .foregroundStyle(.theme(.text))
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 10)
        .help(repository.root.path)
        .accessibilityIdentifier("project-menu")
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
                    .buttonStyle(.prominentPill)
                    .disabled(!repository.files.isEmpty || repository.isBusy)
                    .accessibilityIdentifier("operation-continue")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.theme(.surfaceRaised))
            .overlay(alignment: .bottom) { Divider() }
            .confirmationDialog("Abort the \(operation.title.lowercased())?", isPresented: $confirmingAbort, titleVisibility: .visible) {
                Button("Abort \(operation.title)") { run { try await repository.abortOperation() } }
                    .keyboardShortcut(.defaultAction)
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
