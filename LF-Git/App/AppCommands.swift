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
            Button("Reload Conflicted Files") { Task { await repository?.refresh() } }
                .keyboardShortcut("r")
                .disabled(repository == nil)
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
