import AppKit
import LFKit
import SwiftUI

/// The editor surface: an NSTableView with one row per line, rows built on demand from the engine.
struct ConflictTableView: NSViewRepresentable {
    let editor: EditorModel
    var onCompare: (Int) -> Void
    var onEdit: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(editor: editor)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = EditorMetrics.rowHeight
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.backgroundColor = .theme(.background)
        table.style = .plain
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.setAccessibilityIdentifier("conflict-editor")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("code"))
        column.width = EditorMetrics.contentWidth
        table.addTableColumn(column)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.backgroundColor = .theme(.background)
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        // Reading these registers the observation; SwiftUI calls us again when they change.
        let revision = editor.revision
        let focus = editor.focusedConflict
        let scrollRequest = editor.scrollRequest
        context.coordinator.onCompare = onCompare
        context.coordinator.onEdit = onEdit
        context.coordinator.show(editor)
        context.coordinator.update(revision: revision, focus: focus, scrollRequest: scrollRequest)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private(set) var editor: EditorModel
        weak var table: NSTableView?
        var onCompare: (Int) -> Void = { _ in }
        var onEdit: (Int) -> Void = { _ in }
        private var shownRevision = -1
        private var shownFocus: Int?
        private var shownScrollRequest = -1
        private var gutterWidth: CGFloat = 0

        init(editor: EditorModel) {
            self.editor = editor
            super.init()
            gutterWidth = Self.gutterWidth(for: editor)
        }

        private static func gutterWidth(for editor: EditorModel) -> CGFloat {
            let digits = String(repeating: "8", count: max(3, String(editor.lineCount).count))
            return ceil((digits as NSString).size(withAttributes: [.font: EditorMetrics.gutterFont]).width) + 6
        }

        /// Follows the model SwiftUI hands us: a different editor means a different file.
        func show(_ newEditor: EditorModel) {
            guard newEditor !== editor else { return }
            editor = newEditor
            gutterWidth = Self.gutterWidth(for: newEditor)
            shownRevision = -1
            shownFocus = nil
            shownScrollRequest = -1
            table?.reloadData()
        }

        func update(revision: Int, focus: Int?, scrollRequest: Int) {
            guard let table else { return }
            if revision != shownRevision {
                shownRevision = revision
                let visible = table.rows(in: table.visibleRect)
                if visible.length > 0 {
                    table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<NSMaxRange(visible)),
                                     columnIndexes: IndexSet(integer: 0))
                }
                refreshRowBackgrounds(in: table)
            }
            if focus != shownFocus {
                shownFocus = focus
                refreshRowBackgrounds(in: table)
            }
            // Only navigation scrolls; clicking a conflict just focuses it.
            if scrollRequest != shownScrollRequest {
                shownScrollRequest = scrollRequest
                if let focus, editor.spans.indices.contains(focus) {
                    scroll(table, toRow: editor.spans[focus].openLine - 1)
                }
            }
        }

        /// Puts `row` a few rows below the top, like a "go to conflict" in a code editor.
        private func scroll(_ table: NSTableView, toRow row: Int) {
            guard let clip = table.enclosingScrollView?.contentView else { return }
            let margin = EditorMetrics.rowHeight * 4
            var target = clip.bounds
            target.origin.y = max(0, table.rect(ofRow: row).minY - margin)
            clip.setBoundsOrigin(clip.constrainBoundsRect(target).origin) // never past the end of the content
            table.enclosingScrollView?.reflectScrolledClipView(clip)
        }

        private func refreshRowBackgrounds(in table: NSTableView) {
            table.enumerateAvailableRowViews { rowView, row in
                guard let rowView = rowView as? ConflictRowView else { return }
                configure(rowView, row: row)
                rowView.needsDisplay = true
            }
        }

        // MARK: Data source

        func numberOfRows(in tableView: NSTableView) -> Int {
            editor.lineCount
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = ConflictRowView()
            configure(rowView, row: row)
            return rowView
        }

        private func configure(_ rowView: ConflictRowView, row: Int) {
            let role = editor.role(ofLine: row + 1)
            rowView.background = RowStyle.background(for: role)
            rowView.focused = role.conflict != nil && role.conflict == editor.focusedConflict
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let line = row + 1
            let role = editor.role(ofLine: line)
            if case .header(let conflict) = role {
                let cell = tableView.makeView(withIdentifier: ConflictHeaderCell.identifier, owner: nil) as? ConflictHeaderCell
                    ?? ConflictHeaderCell(frame: .zero)
                cell.configure(conflict: conflict, choice: editor.choice(of: conflict),
                               currentLabel: editor.labels(of: conflict).current, hasBase: editor.hasBase(conflict))
                cell.onAction = { [weak self] conflict, action in self?.perform(action, on: conflict) }
                return cell
            }
            let cell = tableView.makeView(withIdentifier: LineCell.identifier, owner: nil) as? LineCell ?? LineCell(frame: .zero)
            cell.configure(line: line, gutter: gutterWidth, text: RowStyle.text(for: role, line: line, editor: editor))
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let table, table.selectedRow >= 0 else { return }
            if let conflict = editor.role(ofLine: table.selectedRow + 1).conflict {
                editor.focusedConflict = conflict
            }
            table.deselectAll(nil)
        }

        private func perform(_ action: ConflictHeaderCell.Action, on conflict: Int) {
            editor.focusedConflict = conflict
            switch action {
            case .current: editor.resolve(conflict, as: .current)
            case .incoming: editor.resolve(conflict, as: .incoming)
            case .both: editor.resolve(conflict, as: .bothCurrentFirst)
            case .base: editor.resolve(conflict, as: .base)
            case .undo: editor.resolve(conflict, as: .unresolved)
            case .edit: onEdit(conflict)
            case .compare: onCompare(conflict)
            }
        }
    }
}

/// Colours and text of a row, from the theme tokens.
enum RowStyle {
    static func background(for role: LineRole) -> LFThemeToken? {
        switch role {
        case .plain: nil
        case .header: .conflictCurrentHeader
        case .current: .conflictCurrentBody
        case .baseHeader: .conflictBaseHeader
        case .base: .conflictBaseBody
        case .separator, .footer: .conflictIncomingHeader
        case .incoming: .conflictIncomingBody
        }
    }

    /// Whether a side survives the chosen resolution (discarded sides are drawn dimmed).
    static func isKept(_ role: LineRole, choice: LFChoice) -> Bool {
        switch (role, choice) {
        case (_, .unresolved): true
        case (.current, .current), (.current, .bothCurrentFirst), (.current, .bothIncomingFirst): true
        case (.incoming, .incoming), (.incoming, .bothCurrentFirst), (.incoming, .bothIncomingFirst): true
        case (.base, .base): true
        default: false
        }
    }

    static func text(for role: LineRole, line: Int, editor: EditorModel) -> NSAttributedString {
        let font = EditorMetrics.codeFont
        func label(_ text: String) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: EditorMetrics.headerFont, .foregroundColor: NSColor.theme(.text)])
        }
        switch role {
        case .baseHeader:
            return label("◇ Base (common ancestor)")
        case .separator(let conflict):
            let name = editor.labels(of: conflict).incoming
            return label(name.isEmpty ? "▶ Incoming" : "▶ Incoming (\(name))")
        case .footer:
            return NSAttributedString(string: "end of conflict", attributes: [
                .font: EditorMetrics.gutterFont, .foregroundColor: NSColor.theme(.textSubtle),
            ])
        default:
            break
        }
        let text = editor.text(ofLine: line)
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.theme(.text)])
        for token in SyntaxHighlighter.tokens(in: text, language: editor.language) where token.range.upperBound <= attributed.length {
            attributed.addAttribute(.foregroundColor, value: NSColor.theme(color(for: token.kind)),
                                    range: NSRange(location: token.range.lowerBound, length: token.range.count))
        }
        if let conflict = role.conflict, !isKept(role, choice: editor.choice(of: conflict)) {
            let range = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(.foregroundColor, value: NSColor.theme(.text).withAlphaComponent(EditorMetrics.dimmedAlpha), range: range)
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        return attributed
    }

    private static func color(for kind: SyntaxToken.Kind) -> LFThemeToken {
        switch kind {
        case .keyword: .syntaxKeyword
        case .string: .syntaxString
        case .number: .syntaxNumber
        case .comment: .syntaxComment
        case .type: .syntaxType
        case .identifier: .syntaxIdentifier
        }
    }
}
