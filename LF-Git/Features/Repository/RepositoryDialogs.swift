import LFKit
import SwiftUI

/// The questions, sheets and panels any part of the window can ask for through the model.
struct RepositoryDialogs: ViewModifier {
    @Bindable var repository: RepositoryModel
    let app: AppModel
    @Binding var promptText: String
    @Binding var messageText: String

    func body(content: Content) -> some View {
        content
            .alert(repository.prompt?.title ?? "", isPresented: Binding(
                get: { repository.prompt != nil }, set: { if !$0 { repository.prompt = nil } }), presenting: repository.prompt) { prompt in
                TextField(prompt.placeholder, text: $promptText)
                Button(prompt.confirmTitle) { prompt.action(promptText) }
                Button("Cancel", role: .cancel) {}
            } message: { prompt in
                Text(prompt.message)
            }
            .onChange(of: repository.prompt?.id) { promptText = repository.prompt?.initialText ?? "" }
            .confirmationDialog(
                repository.confirmation?.title ?? "", isPresented: Binding(
                    get: { repository.confirmation != nil }, set: { if !$0 { repository.confirmation = nil } }),
                titleVisibility: .visible, presenting: repository.confirmation
            ) { confirmation in
                Button(confirmation.confirmTitle, role: confirmation.isDestructive ? .destructive : nil, action: confirmation.action)
            } message: { confirmation in
                Text(confirmation.message)
            }
            .sheet(item: $repository.messageEdit) { edit in
                MessageEditorSheet(edit: edit, text: $messageText) { repository.messageEdit = nil }
            }
            .onChange(of: repository.messageEdit?.id) { messageText = repository.messageEdit?.initialText ?? "" }
            .sheet(isPresented: $repository.showsPalette) { CommandPaletteView(repository: repository, app: app) }
            .sheet(isPresented: $repository.showsHelp) { KeyboardHelpView(repository: repository) }
    }
}

private struct MessageEditorSheet: View {
    let edit: PendingMessageEdit
    @Binding var text: String
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(edit.title).font(.headline)
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .frame(minWidth: 480, minHeight: 200)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.theme(.border)))
                .accessibilityIdentifier("message-editor")
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: dismiss).keyboardShortcut(.cancelAction)
                Button(edit.confirmTitle) {
                    edit.action(text)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("message-editor-confirm")
            }
        }
        .padding(16)
    }
}

/// Bisect in progress: say whether the commit being tested is good or bad.
struct BisectBanner: View {
    let repository: RepositoryModel
    let app: AppModel

    var body: some View {
        if repository.isBisecting {
            HStack(spacing: 12) {
                Image(systemName: "scope").foregroundStyle(.theme(.info))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bisecting").font(.headline)
                    Text("Test the code at \(String(repository.bisectCandidate?.prefix(7) ?? "")), then answer.")
                        .font(.caption).foregroundStyle(.theme(.textSubtle))
                }
                Spacer()
                Button("Good") { app.run { try await repository.answerBisect(.good) } }.accessibilityIdentifier("bisect-good")
                Button("Bad") { app.run { try await repository.answerBisect(.bad) } }.accessibilityIdentifier("bisect-bad")
                Button("Skip") { app.run { try await repository.answerBisect(.skip) } }
                Button("Stop", role: .destructive) { app.run { try await repository.resetBisect() } }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.theme(.surfaceRaised))
            .overlay(alignment: .bottom) { Divider() }
            .disabled(repository.isBusy)
        } else if repository.bisectBad != nil || repository.bisectGood != nil {
            HStack(spacing: 12) {
                Image(systemName: "scope").foregroundStyle(.theme(.info))
                Text(repository.bisectBad == nil ? "Now mark a bad commit." : "Now mark a good (older) commit.")
                Spacer()
                Button("Cancel") {
                    repository.bisectBad = nil
                    repository.bisectGood = nil
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.theme(.surfaceRaised))
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

#if DEBUG
#Preview("Bisect banner") {
    PreviewRepository(width: 700) { repository, app in
        BisectBanner(repository: repository, app: app)
    }
}
#endif

#if DEBUG
#Preview("Edit commit message") {
    @Previewable @State var text = "Fix the greeting\n\nLonger explanation of why."
    MessageEditorSheet(edit: PendingMessageEdit(title: "Reword Commit", initialText: text, confirmTitle: "Reword", action: { _ in }),
                       text: $text, dismiss: {})
}
#endif
