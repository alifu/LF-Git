import LFKit
import SwiftUI

/// Where the conflicts are in the file, coloured by state; click to jump.
struct MinimapView: View {
    let editor: EditorModel
    static let width: CGFloat = 14
    private static let tickHeight: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                _ = editor.revision // redraw when choices change
                // Short files: ticks sit next to their rows. Long files: the whole file is scaled to fit.
                let content = CGFloat(max(editor.lineCount, 1)) * EditorMetrics.rowHeight
                let scale = min(1, (size.height - Self.tickHeight) / content)
                var lastY: CGFloat = -1
                for span in editor.spans {
                    let y = CGFloat(span.openLine - 1) * EditorMetrics.rowHeight * scale
                    if y - lastY < 1 && span.index != editor.focusedConflict { continue } // one tick per pixel row
                    lastY = y
                    let rect = CGRect(x: 2, y: y, width: size.width - 4, height: Self.tickHeight)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.theme(token(for: span.index))))
                    if span.index == editor.focusedConflict {
                        context.stroke(Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: 1.5), with: .color(.theme(.text)))
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                jump(to: location.y, height: geometry.size.height)
            }
        }
        .frame(width: Self.width)
        .background(.theme(.surfaceSunken))
        .accessibilityElement()
        .accessibilityLabel("Conflict map, \(editor.unresolvedCount) unresolved")
    }

    private func token(for conflict: Int) -> LFThemeToken {
        switch editor.choice(of: conflict) {
        case .unresolved: .minimapUnresolved
        case .current: .minimapCurrent
        case .incoming: .minimapIncoming
        default: .accent
        }
    }

    private func jump(to y: CGFloat, height: CGFloat) {
        let content = CGFloat(max(editor.lineCount, 1)) * EditorMetrics.rowHeight
        let scale = min(1, (height - Self.tickHeight) / content)
        let line = Int(y / max(scale, .leastNonzeroMagnitude) / EditorMetrics.rowHeight) + 1
        let nearest = editor.spans.min { abs($0.openLine - line) < abs($1.openLine - line) }
        editor.jump(to: nearest?.index)
    }
}
