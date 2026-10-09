import LFKit
import SwiftUI

/// Header bar, the conflict table and the conflict map for one text file.
struct EditorView: View {
    @Bindable var editor: EditorModel
    let file: ConflictedFile
    let repository: RepositoryModel
    let app: AppModel
    @State private var comparing: ComparedConflict?
    @State private var remergeMessage: String?
    @State private var confirmRemerge = false

    struct ComparedConflict: Identifiable {
        let id: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                ConflictTableView(editor: editor) { comparing = ComparedConflict(id: $0) }
                Divider()
                MinimapView(editor: editor)
            }
        }
        .background(.theme(.background))
        .focusedSceneValue(\.editorModel, editor)
        .sheet(item: $comparing) { CompareView(editor: editor, conflict: $0.id) }
        .alert("Re-merge", isPresented: Binding(get: { remergeMessage != nil }, set: { if !$0 { remergeMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(remergeMessage ?? "")
        }
        .onAppear { if editor.focusedConflict == nil { editor.focusNext() } }
        .confirmationDialog("Re-merge \(file.name)?", isPresented: $confirmRemerge) {
            Button("Re-merge and discard my resolutions", role: .destructive) { remerge() }
        } message: {
            Text("Re-merging rewrites the file from git's index; the resolutions you have not saved are lost.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(.headline).foregroundStyle(.theme(.text))
                Text(file.folder.isEmpty ? repository.name : file.folder)
                    .font(.caption).foregroundStyle(.theme(.textSubtle)).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            status
            ControlGroup {
                Button { editor.focusPrevious() } label: { Label("Previous", systemImage: "chevron.up") }
                    .help("Previous conflict (⌥⌘↑)")
                Button { editor.focusNext() } label: { Label("Next", systemImage: "chevron.down") }
                    .help("Next conflict (⌥⌘↓)")
            }
            .fixedSize()
            .disabled(editor.conflictCount == 0)
            Menu("Accept All") {
                Button("All Current") { editor.resolveAll(as: .current) }
                Button("All Incoming") { editor.resolveAll(as: .incoming) }
                Button("All Both (current first)") { editor.resolveAll(as: .bothCurrentFirst) }
            }
            .fixedSize()
            .disabled(editor.conflictCount == 0)
            if file.kind == .project {
                Button("Re-merge Project") {
                    if editor.hasUnsavedChanges { confirmRemerge = true } else { remerge() }
                }
                    .help("Merge project.pbxproj object by object from git's index")
                    .accessibilityIdentifier("remerge-project")
            }
            Toggle("Stage on save", isOn: $editor.stageOnSave)
                .toggleStyle(.checkbox)
                .help("Run git add when the file is saved with every conflict resolved")
            if editor.conflictCount == 0 || (editor.unresolvedCount == 0 && !editor.hasUnsavedChanges) {
                Button("Mark Resolved") { markResolved() }
                    .help("Stage the file with git add")
                    .accessibilityIdentifier("mark-resolved")
            }
            Button("Save") { EditorActions.save(editor, repository: repository, app: app) }
                .buttonStyle(.borderedProminent)
                .disabled(!editor.hasUnsavedChanges || editor.isSaving)
                .accessibilityIdentifier("save")
            if editor.isSaving {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.theme(.surfaceRaised))
    }

    private var status: some View {
        Group {
            if editor.conflictCount == 0 {
                Text("No conflict markers")
            } else if editor.unresolvedCount == 0 {
                Label("All \(editor.conflictCount) resolved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.theme(.accentText))
            } else {
                Text("\(editor.unresolvedCount) of \(editor.conflictCount) unresolved")
                    .foregroundStyle(.theme(.danger))
            }
        }
        .font(.callout.monospacedDigit())
        .accessibilityIdentifier("conflict-status")
    }

    private func markResolved() {
        Task {
            do { try await repository.markResolved(file.path) } catch { app.report(error) }
        }
    }

    private func remerge() {
        Task {
            do {
                let outcome = try await repository.remergeProject(file.path)
                remergeMessage = outcome.isClean
                    ? "Merged cleanly (\(outcome.result.mergedObjectCount) objects combined) and staged."
                    : "\(outcome.result.conflictCount) conflict(s) left; resolve them here."
                if !outcome.filesToReAdd.isEmpty {
                    remergeMessage! += "\n\nIf you keep \(outcome.filesToReAdd.joined(separator: ", ")), add it back to the project in Xcode."
                }
            } catch {
                app.report(error)
            }
        }
    }
}

/// Loads the right view for the selected file. Editors live in the repository model, so switching
/// files or reloading the list never throws away unsaved resolutions.
struct FileDetailView: View {
    let repository: RepositoryModel
    let file: ConflictedFile
    let app: AppModel
    @State private var editor: EditorModel?
    @State private var loadError: String?

    var body: some View {
        Group {
            if file.kind == .binary {
                BinaryFileView(repository: repository, file: file, app: app)
            } else if let editor {
                EditorView(editor: editor, file: file, repository: repository, app: app)
                    .id(ObjectIdentifier(editor))
            } else if let loadError {
                ContentUnavailableView("Cannot open \(file.name)", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else {
                ProgressView("Opening \(file.name)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.theme(.background))
        .task(id: file) {
            guard file.kind != .binary else { return }
            do {
                editor = try await repository.editor(for: file.path)
                loadError = nil
            } catch let error as LFError {
                loadError = error.message
            } catch {
                loadError = "\(error)"
            }
        }
    }
}
