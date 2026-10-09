import Foundation
import LFKit

/// Draws one conflict for the terminal: labelled sides, truncated to keep the screen readable.
struct ConflictRenderer {
    let palette: TerminalPalette?

    static let maxLinesPerSide = 12
    static let maxColumns = 200

    func render(document: LFDocument, index: Int, total: Int, conflict: LFConflict, displayName: String) -> String {
        var out = "\n" + heading("── conflict \(index + 1) of \(total) · \(displayName):\(conflict.openLine) ──") + "\n"
        out += side(
            "◀ Current", label: document.bytes(in: conflict.currentLabel), content: document.bytes(in: conflict.current),
            color: palette?.current
        )
        if conflict.hasBase {
            out += side("◇ Base", label: [], content: document.bytes(in: conflict.base), color: palette?.base)
        }
        out += side(
            "▶ Incoming", label: document.bytes(in: conflict.incomingLabel), content: document.bytes(in: conflict.incoming),
            color: palette?.incoming
        )
        return out
    }

    private func heading(_ text: String) -> String {
        guard let palette else { return text }
        return palette.paint(text, palette.muted, bold: true)
    }

    private func tint(_ text: String, _ color: TerminalPalette.RGB?, bold: Bool = false) -> String {
        guard let palette, let color else { return text }
        return palette.paint(text, color, bold: bold)
    }

    private func side(_ title: String, label: [UInt8], content: [UInt8], color: TerminalPalette.RGB?) -> String {
        let name = String(decoding: label, as: UTF8.self)
        var out = tint(name.isEmpty ? title : "\(title) (\(name))", color, bold: true) + "\n"
        let lines = Self.lines(of: content)
        if lines.isEmpty {
            return out + tint("│ (empty)", palette?.muted) + "\n"
        }
        for line in lines.prefix(Self.maxLinesPerSide) {
            out += tint("│ ", color) + line + "\n"
        }
        let hidden = lines.count - Self.maxLinesPerSide
        if hidden > 0 {
            out += tint("│ … \(plural(hidden, "more line"))", palette?.muted) + "\n"
        }
        return out
    }

    static func lines(of bytes: [UInt8]) -> [String] {
        guard !bytes.isEmpty else { return [] }
        var lines = String(decoding: bytes, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.map { line in
            let trimmed = line.hasSuffix("\r") ? String(line.dropLast()) : String(line)
            return trimmed.count > maxColumns ? String(trimmed.prefix(maxColumns)) + "…" : trimmed
        }
    }
}
