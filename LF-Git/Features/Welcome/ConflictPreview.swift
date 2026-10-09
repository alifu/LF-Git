import SwiftUI

/// Static sample of an inline conflict block, used to show the theme on the welcome screen.
/// The real large-file editor is AppKit-based (Phase 4).
struct ConflictPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ConflictSection(
                label: "Current (ours)",
                lines: ["isa = PBXFileReference; path = Login.swift;"],
                header: .conflictCurrentHeader,
                lineBackground: .conflictCurrentBody
            )
            ConflictSection(
                label: "Incoming (theirs)",
                lines: ["isa = PBXFileReference; path = Signup.swift;"],
                header: .conflictIncomingHeader,
                lineBackground: .conflictIncomingBody
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.theme(.border)))
    }
}

private struct ConflictSection: View {
    let label: String
    let lines: [String]
    let header: LFThemeToken
    let lineBackground: LFThemeToken

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.theme(header))
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.theme(lineBackground))
            }
        }
        .foregroundStyle(.theme(.text))
        .accessibilityElement(children: .combine)
    }
}
