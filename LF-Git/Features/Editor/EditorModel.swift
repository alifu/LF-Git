import Foundation
import LFKit
import Observation

/// Owns an engine document so it can be handed to a background save.
///
/// Thread-safety contract: the document is used from the main actor, except during `EditorModel.save()`,
/// which writes it on a background thread while every mutation is blocked (`isSaving`). Concurrent reads
/// (rows being drawn) are safe because saving only reads the document.
nonisolated final class DocumentBox: @unchecked Sendable {
    let document: LFDocument

    init(_ document: LFDocument) {
        self.document = document
    }
}

/// Per-conflict facts read once when a file opens.
nonisolated struct DocumentSnapshot: Sendable {
    var lineCount = 0
    var spans: [ConflictSpan] = []
    var choices: [LFChoice] = []
    var labels: [EditorModel.Labels] = []
    var hasBase: [Bool] = []
}

/// One conflicted text file being resolved: rows come straight from the C engine on demand, so the
/// model holds only per-conflict state (spans, choices, undo history), never per-line state.
@Observable
final class EditorModel {
    nonisolated struct Labels: Sendable, Equatable {
        let current: String
        let incoming: String
    }

    struct Sides: Equatable {
        let current: String
        let base: String?
        let incoming: String
        let currentLabel: String
        let incomingLabel: String
    }

    /// One user action; accept-all is one action covering many conflicts.
    private struct Change {
        let entries: [(index: Int, from: LFChoice, to: LFChoice)]
    }

    static let maxDisplayedColumns = 4000
    /// Bytes read for one row at most; longer lines are cut before decoding.
    private static let maxDisplayedBytes = maxDisplayedColumns * 4

    let displayPath: String
    let path: String
    let language: SyntaxLanguage
    /// Repository root, when the file belongs to one: saving a fully resolved file stages it.
    let repository: URL?
    let lineCount: Int
    let spans: [ConflictSpan]
    private let classifier: LineClassifier
    private let labelList: [Labels]
    private let hasBaseSection: [Bool]

    private let box: DocumentBox
    private var document: LFDocument { box.document }
    private(set) var choices: [LFChoice]
    private var savedChoices: [LFChoice]
    private var undoStack: [Change] = []
    private var redoStack: [Change] = []

    /// The conflict keyboard commands act on and the editor highlights. Setting it does not scroll.
    var focusedConflict: Int?
    /// Bumped by navigation (next/previous, map, initial focus): the editor scrolls to the focused conflict.
    private(set) var scrollRequest = 0
    var stageOnSave = true
    /// Bumped on every change, so views can refresh just the visible rows.
    private(set) var revision = 0
    private(set) var isSaving = false
    private(set) var lastError: String?

    private init(box: DocumentBox, snapshot: DocumentSnapshot, path: String, displayPath: String, repository: URL?) {
        self.box = box
        self.path = path
        self.displayPath = displayPath
        self.repository = repository
        language = SyntaxLanguage.forPath(displayPath)
        lineCount = snapshot.lineCount
        spans = snapshot.spans
        choices = snapshot.choices
        savedChoices = snapshot.choices
        labelList = snapshot.labels
        hasBaseSection = snapshot.hasBase
        classifier = LineClassifier(spans: snapshot.spans)
    }

    /// Opens and scans the file, and reads every conflict, away from the main thread.
    static func load(path: String, displayPath: String, repository: URL?) async throws -> EditorModel {
        let (box, snapshot) = try await openDocument(path: path, repository: repository)
        return EditorModel(box: box, snapshot: snapshot, path: path, displayPath: displayPath, repository: repository)
    }

    @concurrent
    nonisolated private static func openDocument(path: String, repository: URL?) async throws -> (DocumentBox, DocumentSnapshot) {
        let markerSize = repository.map { Git(directory: $0).markerSize(forPath: path) } ?? Int(LFDefaults.markerSize)
        let document = try LFDocument(path: path, markerSize: markerSize)
        let info = document.info
        var snapshot = DocumentSnapshot(lineCount: info.lineCount)
        for index in 0..<info.conflictCount {
            let conflict = try document.conflict(at: index) // a gap would misalign every later conflict
            snapshot.spans.append(ConflictSpan(index: index, openLine: conflict.openLine, baseLine: conflict.baseLine,
                                               separatorLine: conflict.separatorLine, closeLine: conflict.closeLine))
            snapshot.choices.append(conflict.choice)
            snapshot.labels.append(Labels(current: text(document.bytes(in: conflict.currentLabel)),
                                          incoming: text(document.bytes(in: conflict.incomingLabel))))
            snapshot.hasBase.append(conflict.hasBase)
        }
        return (DocumentBox(document), snapshot)
    }

    nonisolated private static func text(_ bytes: [UInt8]) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Reading

    var unresolvedCount: Int { choices.lazy.filter { $0 == .unresolved }.count }
    var conflictCount: Int { spans.count }
    var hasUnsavedChanges: Bool { choices != savedChoices }
    var canUndo: Bool { !undoStack.isEmpty && !isSaving }
    var canRedo: Bool { !redoStack.isEmpty && !isSaving }

    func role(ofLine line: Int) -> LineRole {
        classifier.role(ofLine: line)
    }

    func choice(of conflict: Int) -> LFChoice {
        choices.indices.contains(conflict) ? choices[conflict] : .unresolved
    }

    func hasBase(_ conflict: Int) -> Bool {
        hasBaseSection.indices.contains(conflict) && hasBaseSection[conflict]
    }

    func labels(of conflict: Int) -> Labels {
        labelList.indices.contains(conflict) ? labelList[conflict] : Labels(current: "", incoming: "")
    }

    /// Text of a 1-based line without its terminator, cut at `maxDisplayedColumns` characters.
    func text(ofLine line: Int) -> String {
        guard line >= 1, line <= lineCount, let start = try? document.lineOffset(line),
              let end = try? document.lineOffset(line + 1) else { return "" }
        let cut = end - start > Self.maxDisplayedBytes
        var bytes = document.bytes(in: LFRange(offset: start, length: min(end - start, Self.maxDisplayedBytes)))
        if cut {
            while let last = bytes.last, last & 0xC0 == 0x80 { bytes.removeLast() } // continuation bytes
            if let last = bytes.last, last >= 0xC0 { bytes.removeLast() } // a lead byte without its tail
        }
        while let last = bytes.last, last == 0x0A || last == 0x0D { bytes.removeLast() }
        let text = Self.text(bytes)
        if cut || text.count > Self.maxDisplayedColumns {
            return String(text.prefix(Self.maxDisplayedColumns)) + "…"
        }
        return text
    }

    func sides(of conflict: Int) -> Sides {
        guard let raw = try? document.conflict(at: conflict) else {
            return Sides(current: "", base: nil, incoming: "", currentLabel: "", incomingLabel: "")
        }
        return Sides(
            current: Self.text(document.bytes(in: raw.current)),
            base: raw.hasBase ? Self.text(document.bytes(in: raw.base)) : nil,
            incoming: Self.text(document.bytes(in: raw.incoming)),
            currentLabel: Self.text(document.bytes(in: raw.currentLabel)),
            incomingLabel: Self.text(document.bytes(in: raw.incomingLabel))
        )
    }

    // MARK: - Resolving

    func resolve(_ conflict: Int, as choice: LFChoice) {
        apply(Change(entries: [(conflict, self.choice(of: conflict), choice)]), record: true)
    }

    /// Applies one choice to every conflict as a single undo step. The base choice skips conflicts without a base.
    func resolveAll(as choice: LFChoice) {
        let entries = choices.indices
            .filter { choice != .base || hasBase($0) }
            .map { (index: $0, from: choices[$0], to: choice) }
        apply(Change(entries: entries), record: true)
    }

    func undo() {
        guard canUndo, let change = undoStack.popLast() else { return }
        apply(Change(entries: change.entries.reversed().map { ($0.index, $0.to, $0.from) }), record: false)
        redoStack.append(change)
    }

    func redo() {
        guard canRedo, let change = redoStack.popLast() else { return }
        apply(change, record: false)
        undoStack.append(change)
    }

    private func apply(_ change: Change, record: Bool) {
        guard !isSaving else { return } // the document is being written; see DocumentBox
        var applied: [(index: Int, from: LFChoice, to: LFChoice)] = []
        for entry in change.entries where choices.indices.contains(entry.index) && entry.from != entry.to {
            do {
                try document.resolve(entry.index, as: entry.to)
                choices[entry.index] = entry.to
                applied.append(entry)
            } catch {
                lastError = error.message
            }
        }
        guard !applied.isEmpty else { return }
        if record {
            undoStack.append(Change(entries: applied))
            redoStack.removeAll()
        }
        revision += 1
    }

    // MARK: - Navigation

    func focusNext() { jump(to: neighbour(step: 1)) }
    func focusPrevious() { jump(to: neighbour(step: -1)) }

    /// Focuses a conflict and scrolls the editor to it.
    func jump(to conflict: Int?) {
        focusedConflict = conflict
        scrollRequest += 1
    }

    /// The next conflict in `step` direction, wrapping; unresolved conflicts first.
    private func neighbour(step: Int) -> Int? {
        let count = spans.count
        guard count > 0 else { return nil }
        let wanted: (Int) -> Bool = unresolvedCount > 0 ? { self.choices[$0] == .unresolved } : { _ in true }
        let start = focusedConflict ?? (step > 0 ? -1 : count)
        for distance in 1...count {
            let index = ((start + step * distance) % count + count) % count
            if wanted(index) { return index }
        }
        return nil
    }

    /// The conflict that keyboard commands act on: the focused one, else the first unresolved one.
    var targetConflict: Int? {
        focusedConflict ?? choices.firstIndex(of: .unresolved) ?? (spans.isEmpty ? nil : 0)
    }

    // MARK: - Saving

    /// Writes the file away from the main thread (open conflicts stay as markers) and stages it when
    /// everything is resolved. Edits are blocked until it finishes.
    func save() async throws {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let snapshot = choices
        try await Self.write(box)
        savedChoices = snapshot
        revision += 1
        if stageOnSave, unresolvedCount == 0, let repository {
            try await Self.stage(displayPath, in: repository)
        }
    }

    @concurrent
    nonisolated private static func write(_ box: DocumentBox) async throws {
        try box.document.save(force: true)
    }

    @concurrent
    nonisolated private static func stage(_ path: String, in repository: URL) async throws {
        try Git(directory: repository).stage([path])
    }
}
