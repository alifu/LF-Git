import SwiftUI

/// Write the resolution by hand: start from either side or both, then change anything.
struct EditConflictView: View {
    let editor: EditorModel
    let conflict: Int
    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(editor: EditorModel, conflict: Int) {
        self.editor = editor
        self.conflict = conflict
        _text = State(initialValue: editor.initialEditText(of: conflict))
    }

    var body: some View {
        let sides = editor.sides(of: conflict)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Edit Conflict \(conflict + 1) of \(editor.conflictCount)").font(.headline)
                Spacer()
                Text("Start from").font(.caption).foregroundStyle(.theme(.textSubtle))
                Button("Current") { text = sides.current }.accessibilityIdentifier("edit-start-current")
                Button("Incoming") { text = sides.incoming }.accessibilityIdentifier("edit-start-incoming")
                Button("Both") { text = sides.current + sides.incoming }.accessibilityIdentifier("edit-start-both")
                if let base = sides.base { Button("Base") { text = base }.accessibilityIdentifier("edit-start-base") }
            }
            .controlSize(.small)
            .padding(12)
            Divider()
            HStack(spacing: 1) {
                reference(sides.currentLabel.isEmpty ? "Current" : "Current (\(sides.currentLabel))", sides.current,
                          header: .conflictCurrentHeader, body: .conflictCurrentBody, identifier: "current")
                reference(sides.incomingLabel.isEmpty ? "Incoming" : "Incoming (\(sides.incomingLabel))", sides.incoming,
                          header: .conflictIncomingHeader, body: .conflictIncomingBody, identifier: "incoming")
            }
            .frame(height: 130)
            .background(.theme(.border))
            Divider()
            CodeTextEditor(text: $text)
            Divider()
            HStack {
                Text("Type, paste or select here; this text replaces the whole conflict when you apply it. ⌘Z undoes typing.")
                    .font(.caption).foregroundStyle(.theme(.textSubtle))
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("edit-cancel")
                Button("Apply") {
                    editor.edit(conflict, text: text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("edit-apply")
            }
            .padding(12)
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(.theme(.background))
    }

    /// One side of the conflict: select any of it and copy, or add all of it to the result.
    private func reference(_ title: String, _ text: String, header: LFThemeToken, body: LFThemeToken, identifier: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer()
                Button("Copy") { Clipboard.copy(text) }
                    .accessibilityIdentifier("edit-copy-\(identifier)")
                Button("Add to Result") { self.text += (self.text.isEmpty || self.text.hasSuffix("\n") ? "" : "\n") + text }
                    .accessibilityIdentifier("edit-add-\(identifier)")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(text.isEmpty)
            .frame(maxWidth: .infinity, alignment: .leading).padding(6).background(.theme(header))
            ScrollView([.vertical, .horizontal]) {
                Text(text.isEmpty ? "(empty)" : text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(6)
            }
            .background(.theme(body))
        }
        .foregroundStyle(.theme(.text))
    }
}
