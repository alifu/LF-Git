import LFKit
import SwiftUI

/// Side-by-side view of one conflict, with the accept actions.
struct CompareView: View {
    let editor: EditorModel
    let conflict: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let sides = editor.sides(of: conflict)
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                column(title: sides.currentLabel.isEmpty ? "Current" : "Current (\(sides.currentLabel))", text: sides.current,
                       header: .conflictCurrentHeader, body: .conflictCurrentBody, action: ("Accept Current", .current))
                if let base = sides.base {
                    column(title: "Base", text: base, header: .conflictBaseHeader, body: .conflictBaseBody, action: ("Accept Base", .base))
                }
                column(title: sides.incomingLabel.isEmpty ? "Incoming" : "Incoming (\(sides.incomingLabel))", text: sides.incoming,
                       header: .conflictIncomingHeader, body: .conflictIncomingBody, action: ("Accept Incoming", .incoming))
            }
            .background(.theme(.border))
            Divider()
            HStack {
                Text("Conflict \(conflict + 1) of \(editor.conflictCount) · \(editor.displayPath):\(editor.spans[conflict].openLine)")
                    .font(.caption)
                    .foregroundStyle(.theme(.textSubtle))
                Spacer()
                Button("Accept Both") { accept(.bothCurrentFirst) }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 760, minHeight: 420)
        .background(.theme(.background))
    }

    private func column(title: String, text: String, header: LFThemeToken, body: LFThemeToken,
                        action: (String, LFChoice)) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                Button(action.0) { accept(action.1) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(8)
            .background(.theme(header))
            ScrollView([.vertical, .horizontal]) {
                Text(text.isEmpty ? "(empty)" : text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(8)
            }
            .background(.theme(body))
        }
        .foregroundStyle(.theme(.text))
    }

    private func accept(_ choice: LFChoice) {
        editor.resolve(conflict, as: choice)
        dismiss()
    }
}
