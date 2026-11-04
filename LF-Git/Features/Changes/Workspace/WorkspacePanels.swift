import CoreGraphics

/// Which detail panel the Inline (L4) and Lanes (L3) layouts show beside the changes. Only one at a time: opening
/// another replaces it. A pure value; every transition returns a new value. All members are O(1).
nonisolated struct WorkspacePanels: Equatable, Sendable {
    enum Detail: Equatable, Sendable {
        /// The diff of a changed file (the selection of `ChangesModel`).
        case file(ChangeSelection)
        /// A commit of the current branch: its files and diff.
        case commit(String)
    }

    /// Space around the lane on the canvas, and between the lane and its panel (Figma: 12 and 10).
    static let canvasPadding: CGFloat = 12
    static let laneSpacing: CGFloat = 10

    let detail: Detail?

    static let closed = WorkspacePanels(detail: nil)

    var isOpen: Bool { detail != nil }

    var isFileOpen: Bool {
        if case .file = detail { return true }
        return false
    }

    /// Shows `newDetail`, replacing whatever was open.
    func opening(_ newDetail: Detail) -> WorkspacePanels {
        WorkspacePanels(detail: newDetail)
    }

    func closing() -> WorkspacePanels {
        .closed
    }

    /// The panel after the file selection moved from `old` to `new`, by a click or by the model (a file that was
    /// staged moves to the other side). A selected file opens its diff; a file that only moved sides leaves a commit
    /// preview alone; losing the selection closes a file panel but not a commit preview.
    func following(selectionFrom old: ChangeSelection?, to new: ChangeSelection?) -> WorkspacePanels {
        guard let new else { return isFileOpen ? closing() : self }
        if case .commit = detail, old?.path == new.path { return self }
        return opening(.file(new))
    }

    /// The inline card: one list column, widened by a panel while a diff is open.
    var inlineCardWidth: CGFloat {
        isFileOpen ? Chrome.listColumn + Chrome.panelWidth : Chrome.listColumn
    }

    /// What the lanes canvas holds: its padding, the lane and, while open, the panel beside it.
    var canvasContentWidth: CGFloat {
        let lane = Self.canvasPadding * 2 + Chrome.laneWidth
        return isOpen ? lane + Self.laneSpacing + Chrome.panelWidth : lane
    }

    /// The minimap is only worth showing when the canvas cannot show everything at once.
    static func showsMinimap(contentWidth: CGFloat, viewportWidth: CGFloat) -> Bool {
        contentWidth > viewportWidth
    }
}

/// The floating panels (L5) over the Changes section: the popped-out diff and the commit message editor. O(1).
nonisolated struct FloatingPanels: Equatable, Sendable {
    let showsDiff: Bool
    let showsEditor: Bool

    static let none = FloatingPanels(showsDiff: false, showsEditor: false)

    func with(diff: Bool) -> FloatingPanels {
        FloatingPanels(showsDiff: diff, showsEditor: showsEditor)
    }

    func with(editor: Bool) -> FloatingPanels {
        FloatingPanels(showsDiff: showsDiff, showsEditor: editor)
    }
}
