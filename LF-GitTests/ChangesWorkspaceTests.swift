import CoreGraphics
import Testing
@testable import LF_Git

@MainActor
@Suite("Changes workspace panels")
struct WorkspacePanelsTests {
    private static let file = ChangeSelection(path: "src/app.swift", staged: false)
    private static let other = ChangeSelection(path: "README.md", staged: true)

    @Test("starts with no panel open")
    func startsClosed() {
        #expect(WorkspacePanels.closed.detail == nil)
        #expect(!WorkspacePanels.closed.isOpen)
        #expect(!WorkspacePanels.closed.isFileOpen)
    }

    @Test("opening a panel shows it")
    func opens() {
        let panels = WorkspacePanels.closed.opening(.file(Self.file))

        #expect(panels.detail == .file(Self.file))
        #expect(panels.isOpen)
        #expect(panels.isFileOpen)
    }

    @Test("opening another panel replaces the open one, so only one is ever shown")
    func replaces() {
        let panels = WorkspacePanels.closed.opening(.file(Self.file)).opening(.commit("abc123"))

        #expect(panels.detail == .commit("abc123"))
        #expect(!panels.isFileOpen)
    }

    @Test("closing leaves nothing open and does not change the original value")
    func closes() {
        let open = WorkspacePanels.closed.opening(.commit("abc123"))
        let closed = open.closing()

        #expect(closed == .closed)
        #expect(open.detail == .commit("abc123"))
    }

    @Test("selecting a file opens its diff panel")
    func selectionOpensFile() {
        let panels = WorkspacePanels.closed.following(selectionFrom: nil, to: Self.file)

        #expect(panels.detail == .file(Self.file))
    }

    @Test("a file selected while a commit is previewed replaces the commit panel")
    func selectionReplacesCommit() {
        let panels = WorkspacePanels.closed.opening(.commit("abc123")).following(selectionFrom: nil, to: Self.other)

        #expect(panels.detail == .file(Self.other))
    }

    @Test("a file that moved to the other side keeps the commit preview open")
    func movedFileKeepsCommit() {
        let moved = ChangeSelection(path: Self.file.path, staged: true)
        let panels = WorkspacePanels.closed.opening(.commit("abc123")).following(selectionFrom: Self.file, to: moved)

        #expect(panels.detail == .commit("abc123"))
    }

    @Test("a file panel follows its file when it moves to the other side")
    func filePanelFollowsMove() {
        let moved = ChangeSelection(path: Self.file.path, staged: true)
        let panels = WorkspacePanels.closed.opening(.file(Self.file)).following(selectionFrom: Self.file, to: moved)

        #expect(panels.detail == .file(moved))
    }

    @Test("losing the file selection closes a file panel")
    func deselectionClosesFile() {
        let panels = WorkspacePanels.closed.opening(.file(Self.file)).following(selectionFrom: Self.file, to: nil)

        #expect(panels == .closed)
    }

    @Test("losing the file selection keeps a commit preview")
    func deselectionKeepsCommit() {
        let panels = WorkspacePanels.closed.opening(.commit("abc123")).following(selectionFrom: Self.file, to: nil)

        #expect(panels.detail == .commit("abc123"))
    }

    @Test("the inline card is one list column wide, and widens by a panel while a diff is open")
    func inlineWidth() {
        #expect(WorkspacePanels.closed.inlineCardWidth == Chrome.listColumn)
        #expect(WorkspacePanels.closed.opening(.file(Self.file)).inlineCardWidth == Chrome.listColumn + Chrome.panelWidth)
        #expect(WorkspacePanels.closed.opening(.commit("abc123")).inlineCardWidth == Chrome.listColumn)
    }

    @Test("the canvas holds the lane, and the panel beside it when one is open")
    func canvasWidth() {
        let closed = WorkspacePanels.closed.canvasContentWidth
        let open = WorkspacePanels.closed.opening(.commit("abc123")).canvasContentWidth

        #expect(closed == WorkspacePanels.canvasPadding * 2 + Chrome.laneWidth)
        #expect(open == closed + WorkspacePanels.laneSpacing + Chrome.panelWidth)
    }

    @Test("the minimap shows only when the canvas content is wider than the viewport")
    func minimap() {
        #expect(WorkspacePanels.showsMinimap(contentWidth: 900, viewportWidth: 800))
        #expect(!WorkspacePanels.showsMinimap(contentWidth: 800, viewportWidth: 800))
        #expect(!WorkspacePanels.showsMinimap(contentWidth: 400, viewportWidth: 800))
    }
}

@MainActor
@Suite("Floating panels")
struct FloatingPanelsTests {
    @Test("no floating panel is open at first")
    func startsClosed() {
        #expect(!FloatingPanels.none.showsDiff)
        #expect(!FloatingPanels.none.showsEditor)
    }

    @Test("the diff and the commit editor open and close independently")
    func independent() {
        let both = FloatingPanels.none.with(diff: true).with(editor: true)
        let editorOnly = both.with(diff: false)

        #expect(both.showsDiff && both.showsEditor)
        #expect(!editorOnly.showsDiff && editorOnly.showsEditor)
    }

    @Test("a panel that fits stays where it was dragged")
    func keepsOffsetInside() {
        let offset = FloatingPlacement.clamp(CGSize(width: 50, height: -40), panel: CGSize(width: 400, height: 300),
                                             in: CGSize(width: 1000, height: 800))

        #expect(offset == CGSize(width: 50, height: -40))
    }

    @Test("a panel dragged past the window edge stops at the edge")
    func clampsToWindow() {
        let offset = FloatingPlacement.clamp(CGSize(width: 900, height: -900), panel: CGSize(width: 400, height: 300),
                                             in: CGSize(width: 1000, height: 800))

        #expect(offset == CGSize(width: 300, height: -250))
    }

    @Test("a panel larger than the window stays centred")
    func centresWhenTooLarge() {
        let offset = FloatingPlacement.clamp(CGSize(width: 80, height: 80), panel: CGSize(width: 1200, height: 900),
                                             in: CGSize(width: 1000, height: 800))

        #expect(offset == .zero)
    }

    @Test("a panel is never larger than the window minus a margin")
    func fittedSize() {
        let size = FloatingPlacement.fitted(CGSize(width: 860, height: 627), in: CGSize(width: 700, height: 2000))

        #expect(size == CGSize(width: 700 - FloatingPlacement.margin * 2, height: 627))
    }
}
