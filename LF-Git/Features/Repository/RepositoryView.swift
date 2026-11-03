import LFKit
import SwiftUI

/// One repository window: the side menu on the left, then the section's list and detail as two cards on the
/// window color, with the remote, project, branch and actions as pills in the toolbar.
struct RepositoryView: View {
    @Bindable var repository: RepositoryModel
    let app: AppModel
    @State private var promptText = ""
    @State private var messageText = ""

    var body: some View {
        HStack(spacing: 0) {
            SectionRail(repository: repository)
            splitView
        }
        .background(.theme(.surfaceSunken))
        .toolbar { toolbarContent }
        .toolbarBackground(Color.theme(.surfaceSunken), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .navigationTitle(repository.name)
        .modifier(HidesWindowTitle())
        .focusedSceneValue(\.repositoryModel, repository)
        .onAppear { repository.startWatching() }
        .onDisappear { repository.stopWatching() }
        .modifier(RepositoryDialogs(repository: repository, app: app, promptText: $promptText, messageText: $messageText))
    }

    private var splitView: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                CardHeader(repository.section.rawValue, symbol: repository.section.symbol,
                           count: repository.badgeCount(for: repository.section))
                sidebar
            }
            .scrollContentBackground(.hidden)
            .background(.theme(.background))
            .lfCard()
            .padding(.vertical, Chrome.gutter)
            .padding(.trailing, Chrome.gutter / 2)
            .background(.theme(.surfaceSunken))
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        OperationBanner(repository: repository, app: app)
                        BisectBanner(repository: repository, app: app)
                    }
                }
                .lfCard()
                .padding(.vertical, Chrome.gutter)
                .padding(.leading, Chrome.gutter / 2)
                .padding(.trailing, Chrome.gutter)
                .background(.theme(.surfaceSunken))
        }
        .navigationSplitViewStyle(.balanced)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if repository.showsLogPanel {
                LogPanelView(repository: repository)
                    .lfCard()
                    .padding([.leading, .trailing, .bottom], Chrome.gutter)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            RemoteButtons(repository: repository, app: app)
        }
        ToolbarItem(placement: .principal) {
            PillGroup {
                ProjectMenu(repository: repository, app: app)
                PillDivider()
                BranchMenu(repository: repository, app: app)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 8) {
                Button { repository.requestNewBranch(app: app) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("New branch")
                        Text("⌘B").foregroundStyle(.theme(.textSubtle))
                    }
                }
                .buttonStyle(.pill)
                .disabled(repository.isBusy || repository.operation != nil)
                .help("Create a branch at the current commit (⌘B)")
                .accessibilityIdentifier("new-branch-button")
                Button { repository.showsPalette = true } label: {
                    Image(systemName: "sparkle.magnifyingglass")
                }
                .buttonStyle(.pill)
                .help("Command palette (⌘K)")
                .accessibilityLabel("Commands")
                .accessibilityIdentifier("palette-button")
                Button { app.close() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.pill)
                .help("Close this repository and go back to the dashboard (⇧⌘W)")
                .accessibilityLabel("Close Repository")
                .accessibilityIdentifier("close-repository-button")
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        switch repository.section {
        case .changes: ChangesSidebar(repository: repository, app: app)
        case .branches: BranchesSidebar(repository: repository, app: app)
        case .history: HistorySidebar(repository: repository, app: app)
        case .stash: StashSidebar(repository: repository, app: app)
        case .tags: TagsSidebar(repository: repository, app: app)
        case .remotes: RemotesSidebar(repository: repository, app: app)
        case .reflog: ReflogSidebar(repository: repository, app: app)
        case .worktrees: WorktreesSidebar(repository: repository, app: app)
        case .submodules: SubmodulesSidebar(repository: repository, app: app)
        case .conflicts: ConflictsSidebar(repository: repository)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch repository.section {
        case .changes:
            ChangesDetailView(repository: repository, app: app)
        case .branches:
            BranchesDetail(repository: repository, app: app)
        case .history:
            HistoryDetailView(repository: repository, app: app, model: repository.history)
        case .stash:
            CommitViewerDetail(repository: repository, app: app, emptyTitle: "Select a stash")
        case .tags:
            CommitViewerDetail(repository: repository, app: app, emptyTitle: "Select a tag")
        case .reflog:
            CommitViewerDetail(repository: repository, app: app, emptyTitle: "Select a reflog entry")
        case .remotes:
            RemotesDetail(repository: repository, app: app)
        case .worktrees:
            EmptyPane("Worktrees", symbol: "square.stack.3d.up",
                      message: "Each worktree is another checkout of this repository. Right-click one to open it.")
                .background(DotGridBackground())
        case .submodules:
            EmptyPane("Submodules", symbol: "shippingbox",
                      message: "Repositories nested inside this one. Right-click one to update or open it.")
                .background(DotGridBackground())
        case .conflicts:
            if let file = repository.selectedFile {
                FileDetailView(repository: repository, file: file, app: app)
                    .id(file.id)
            } else {
                EmptyPane(
                    repository.files.isEmpty ? "No conflicts" : "Select a file",
                    symbol: repository.files.isEmpty ? "checkmark.seal" : "doc.text",
                    message: repository.files.isEmpty
                        ? "Every conflicted file in \(repository.name) is resolved."
                        : "Choose a conflicted file in the list."
                )
                .background(DotGridBackground())
            }
        }
    }
}

/// The project menu in the top bar already names the repository, so the window title is hidden where the OS allows.
private struct HidesWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

struct ConflictsSidebar: View {
    @Bindable var repository: RepositoryModel

    var body: some View {
        List(selection: $repository.selection) {
            Section {
                ForEach(repository.files) { file in
                    FileRow(file: file).tag(file.id)
                }
            } header: {
                Text(repository.files.isEmpty ? "No conflicted files" : "\(repository.files.count) conflicted")
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if repository.isLoading && repository.files.isEmpty {
                ProgressView()
            }
        }
        .accessibilityIdentifier("conflicted-files")
    }
}

private struct FileRow: View {
    let file: ConflictedFile

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.theme(file.kind == .binary ? .warning : .accentText))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).lineLimit(1)
                if !file.folder.isEmpty {
                    Text(file.folder)
                        .font(.caption)
                        .foregroundStyle(.theme(.textSubtle))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 4)
            badge
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("file-\(file.path)")
    }

    private var icon: String {
        switch file.kind {
        case .text: "doc.text"
        case .project: "hammer"
        case .binary: "photo"
        }
    }

    @ViewBuilder
    private var badge: some View {
        if file.problem != nil {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.theme(.danger))
        } else if file.kind == .binary {
            Text("binary").font(.caption).foregroundStyle(.theme(.textSubtle))
        } else if file.conflictCount > 0 {
            Text("\(file.conflictCount)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(.theme(.danger)))
                .foregroundStyle(.theme(.onAccent))
                .accessibilityLabel("\(file.conflictCount) conflicts")
        } else {
            Image(systemName: "checkmark").foregroundStyle(.theme(.accentText)).accessibilityLabel("no markers left")
        }
    }
}

#if DEBUG
#Preview("Repository window") {
    PreviewRepository(width: 1200, height: 800) { repository, app in
        RepositoryView(repository: repository, app: app)
    }
}
#endif
