import AppKit
import LFKit
import SwiftUI

/// What the hunk header's button does ("Stage Hunk" / "Unstage Hunk").
struct HunkAction {
    let title: String
    /// Receives the diff the hunk belongs to, so a stale click can be recognised.
    let perform: (GitDiffFile, DiffHunk) -> Void
}

/// A unified diff as a table with one fixed-height row per line, read from the engine on demand.
struct DiffTableView: NSViewRepresentable {
    let diff: GitDiffFile
    var hunkAction: HunkAction?
    /// The diff lines (1-based) the user selected, when lines can be picked (staging single lines).
    var selection: Binding<Set<Int>>?

    func makeCoordinator() -> Coordinator {
        Coordinator(diff: diff)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = EditorMetrics.rowHeight
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = selection == nil ? .none : .regular
        table.allowsMultipleSelection = selection != nil
        table.backgroundColor = .theme(.background)
        table.style = .plain
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.setAccessibilityIdentifier("diff-view")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("diff"))
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
        context.coordinator.hunkAction = hunkAction
        context.coordinator.selection = selection
        context.coordinator.show(diff)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private(set) var diff: GitDiffFile
        weak var table: NSTableView?
        var hunkAction: HunkAction?
        var selection: Binding<Set<Int>>?
        private var hunkAtHeader: [Int: DiffHunk] = [:]
        private var gutterWidth: CGFloat = 40

        init(diff: GitDiffFile) {
            self.diff = diff
            super.init()
            prepare()
        }

        private func prepare() {
            hunkAtHeader = Dictionary(uniqueKeysWithValues: diff.index.hunks.map { ($0.headerLine, $0) })
            let largest = diff.index.hunks.map { max($0.oldStart + $0.oldCount, $0.newStart + $0.newCount) }.max() ?? 0
            let digits = String(repeating: "8", count: max(3, String(largest).count))
            gutterWidth = ceil((digits as NSString).size(withAttributes: [.font: EditorMetrics.gutterFont]).width) + 6
        }

        func show(_ newDiff: GitDiffFile) {
            guard newDiff !== diff else {
                refreshVisibleHunkButtons()
                return
            }
            diff = newDiff
            prepare()
            table?.deselectAll(nil)
            table?.reloadData()
            table?.scroll(.zero)
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let selection, let table else { return }
            let lines = Set(table.selectedRowIndexes.map { $0 + 1 })
            if lines != selection.wrappedValue { selection.wrappedValue = lines }
        }

        private func refreshVisibleHunkButtons() {
            guard let table else { return }
            let visible = table.rows(in: table.visibleRect)
            guard visible.length > 0 else { return }
            table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<NSMaxRange(visible)), columnIndexes: IndexSet(integer: 0))
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            diff.lineCount
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = ConflictRowView()
            rowView.background = background(forLine: row + 1)
            return rowView
        }

        private func isFileHeader(_ line: Int) -> Bool {
            line <= diff.index.fileHeaderLineCount
        }

        private func background(forLine line: Int) -> LFThemeToken? {
            if hunkAtHeader[line] != nil { return .diffHunkHeader }
            if isFileHeader(line) { return nil }
            switch diff.text(ofLine: line).first {
            case "+": return .diffAddedBody
            case "-": return .diffRemovedBody
            default: return nil
            }
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let line = row + 1
            if let hunk = hunkAtHeader[line] {
                let cell = tableView.makeView(withIdentifier: DiffHunkCell.identifier, owner: nil) as? DiffHunkCell
                    ?? DiffHunkCell(frame: .zero)
                cell.configure(hunk: hunk, actionTitle: hunkAction?.title, identifier: "hunk-action-\(hunk.headerLine)")
                cell.onAction = { [weak self] in
                    guard let self else { return }
                    self.hunkAction?.perform(self.diff, hunk)
                }
                return cell
            }
            let cell = tableView.makeView(withIdentifier: DiffLineCell.identifier, owner: nil) as? DiffLineCell
                ?? DiffLineCell(frame: .zero)
            let text = diff.text(ofLine: line)
            let numbers = diff.numbers(ofLine: line)
            cell.configure(old: numbers.old, new: numbers.new, gutter: gutterWidth, text: styled(text, line: line))
            return cell
        }

        private func styled(_ text: String, line: Int) -> NSAttributedString {
            let isMeta = isFileHeader(line) || text.hasPrefix("\\")
            let color: NSColor = isMeta ? .theme(.textSubtle) : .theme(.text)
            return NSAttributedString(string: text, attributes: [.font: EditorMetrics.codeFont, .foregroundColor: color])
        }
    }
}
