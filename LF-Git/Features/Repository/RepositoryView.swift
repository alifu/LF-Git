import SwiftUI

/// Sidebar of conflicted files next to the selected file.
struct RepositoryView: View {
    let repository: RepositoryModel
    let app: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(repository: repository)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
        } detail: {
            if let file = repository.selectedFile {
                FileDetailView(repository: repository, file: file, app: app)
                    .id(file.id)
            } else {
                ContentUnavailableView(
                    repository.files.isEmpty ? "No conflicts left" : "Select a file",
                    systemImage: repository.files.isEmpty ? "checkmark.seal" : "doc.text",
                    description: Text(repository.files.isEmpty
                        ? "Every conflicted file in \(repository.name) is resolved. Commit when you are ready."
                        : "Choose a conflicted file in the sidebar.")
                )
                .background(.theme(.background))
            }
        }
        .navigationTitle(repository.name)
        .focusedSceneValue(\.repositoryModel, repository)
    }
}

struct SidebarView: View {
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
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await repository.refresh() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .help("Reload conflicted files (⌘R)")
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
