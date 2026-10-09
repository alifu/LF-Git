import LFKit
import SwiftUI

/// Who last changed each line of a file.
struct BlameView: View {
    let lines: [GitBlameLine]
    /// A blame of a huge file would build millions of views; the rest is cut off with a note.
    private static let shownLimit = 20_000

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines.prefix(Self.shownLimit)) { line in
                    HStack(spacing: 8) {
                        Text(line.isUncommitted ? "not committed" : line.shortHash)
                            .foregroundStyle(.theme(.accentText))
                            .frame(width: 90, alignment: .leading)
                        Text(line.author).lineLimit(1).frame(width: 120, alignment: .leading)
                            .foregroundStyle(.theme(.textSubtle))
                        Text("\(line.number)").frame(width: 44, alignment: .trailing)
                            .foregroundStyle(.theme(.textSubtle))
                        Text(line.content).foregroundStyle(.theme(.text))
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .help(line.summary)
                    .frame(height: 18)
                }
                if lines.count > Self.shownLimit {
                    Text("Showing the first \(Self.shownLimit.formatted()) of \(lines.count.formatted()) lines.")
                        .font(.caption).foregroundStyle(.theme(.textSubtle)).padding(8)
                }
            }
            .padding(.horizontal, 8)
        }
        .background(.theme(.background))
        .accessibilityIdentifier("blame-view")
    }
}
