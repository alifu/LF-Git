import LFKit

/// Actions shared by buttons and menu commands.
enum EditorActions {
    static func save(_ editor: EditorModel, repository: RepositoryModel?, app: AppModel) {
        Task {
            do {
                try await editor.save()
            } catch let error as LFError {
                app.errorMessage = error.message
            } catch {
                app.report(error)
            }
            await repository?.refresh()
        }
    }

    /// Accepts `choice` for the focused conflict (or the first unresolved one) and moves on.
    static func accept(_ choice: LFChoice, in editor: EditorModel) {
        guard let target = editor.targetConflict else { return }
        editor.resolve(target, as: choice)
        editor.focusedConflict = target
        if editor.unresolvedCount > 0 {
            editor.focusNext()
        }
    }
}
