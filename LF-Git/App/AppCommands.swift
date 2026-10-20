import LFKit
import SwiftUI

struct AppCommands: Commands {
    let app: AppModel
    @FocusedValue(\.editorModel) private var editor
    @FocusedValue(\.repositoryModel) private var repository

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Repository…") { app.chooseRepository() }
                .keyboardShortcut("o")
            Button("Clone Repository…") { app.showsClone = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(app.repository != nil)
            Button("Close Repository") { app.close() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(app.repository == nil)
            Menu("Open Recent") {
                ForEach(app.recentRepositories, id: \.self) { path in
                    Button(path) { app.open(URL(fileURLWithPath: path)) }
                }
                if !app.recentRepositories.isEmpty {
                    Divider()
                    Button("Clear Menu") { app.clearRecentRepositories() }
                }
            }
            .disabled(app.recentRepositories.isEmpty)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                if let editor { EditorActions.save(editor, repository: repository, app: app) }
            }
            .keyboardShortcut("s")
            .disabled(editor?.hasUnsavedChanges != true || editor?.isSaving == true)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Resolution") { editor?.undo() }
                .keyboardShortcut("z")
                .disabled(editor?.canUndo != true)
            Button("Redo Resolution") { editor?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(editor?.canRedo != true)
        }
        CommandMenu("Repository") {
            Button("Command Palette…") { repository?.showsPalette = true }
                .keyboardShortcut("k")
                .disabled(repository == nil)
            Button("Toggle Log Panel") { repository?.showsLogPanel.toggle() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(repository == nil)
            Button("Keyboard Shortcuts") { repository?.showsHelp = true }
                .keyboardShortcut("/")
                .disabled(repository == nil)
            Divider()
            ForEach(Array(RepositorySection.allCases.enumerated()), id: \.element) { index, section in
                Button("Show \(section.rawValue)") { repository?.section = section }
                    .keyboardShortcut(KeyEquivalent(Character(index < 9 ? "\(index + 1)" : "0")), modifiers: .control)
                    .disabled(repository == nil)
            }
            Divider()
            Button("Undo Last Git Move") { run { try await $0.undoHeadMove() } }
                .keyboardShortcut("z", modifiers: [.command, .option])
            Divider()
            Button("Fetch") { run { try await $0.fetch() } }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Button("Pull") { run { try await $0.pull() } }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Button("Push") { run { try await $0.push() } }
                .keyboardShortcut("p", modifiers: [.command, .option])
        }
        CommandMenu("Conflict") {
            Button("Next Conflict") { editor?.focusNext() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Previous Conflict") { editor?.focusPrevious() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Divider()
            acceptButton("Accept Current", .current, key: "1")
            acceptButton("Accept Incoming", .incoming, key: "2")
            acceptButton("Accept Both", .bothCurrentFirst, key: "3")
            acceptButton("Accept Base", .base, key: "4")
                .disabled(editor?.targetConflict.map { editor?.hasBase($0) == true } != true)
            Divider()
            Button("Accept All Current") { editor?.resolveAll(as: .current) }
                .keyboardShortcut("1", modifiers: [.command, .shift])
            Button("Accept All Incoming") { editor?.resolveAll(as: .incoming) }
                .keyboardShortcut("2", modifiers: [.command, .shift])
            Divider()
            Button("Reload") { Task { await repository?.refresh(reloadDiffs: true) } }
                .keyboardShortcut("r")
                .disabled(repository == nil)
        }
    }

    private func run(_ work: @escaping (RepositoryModel) async throws -> Void) {
        guard let repository, !repository.isBusy, repository.operation == nil else { return }
        Task {
            do { try await work(repository) } catch { app.report(error) }
        }
    }

    private func acceptButton(_ title: String, _ choice: LFChoice, key: KeyEquivalent) -> some View {
        Button(title) {
            if let editor { EditorActions.accept(choice, in: editor) }
        }
        .keyboardShortcut(key)
        .disabled(editor?.targetConflict == nil)
    }
}
