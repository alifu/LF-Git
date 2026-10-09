import Foundation
import LFKit

struct SessionResult: Equatable {
    var resolved = 0
    var remaining = 0
}

/// Walks through the unresolved conflicts of a document and asks what to do with each.
final class InteractiveSession {
    enum Action: Equatable {
        case choose(LFChoice)
        case edit
        case keep
        case quit
        case help
    }

    private let document: LFDocument
    private let displayName: String
    private let console: Console
    private let editor: ([UInt8]) -> [UInt8]?
    private let renderer: ConflictRenderer

    init(document: LFDocument, displayName: String, console: Console, editor: @escaping ([UInt8]) -> [UInt8]?) {
        self.document = document
        self.displayName = displayName
        self.console = console
        self.editor = editor
        renderer = ConflictRenderer(palette: console.palette)
    }

    static func parse(_ input: String) -> Action? {
        let key = input.trimmingCharacters(in: .whitespaces)
        if key == "B" { return .choose(.bothIncomingFirst) }
        switch key.lowercased() {
        case "c": return .choose(.current)
        case "i": return .choose(.incoming)
        case "b": return .choose(.bothCurrentFirst)
        case "a": return .choose(.base)
        case "e": return .edit
        case "k": return .keep
        case "q": return .quit
        case "?", "h": return .help
        default: return nil
        }
    }

    func run() -> SessionResult {
        var result = SessionResult()
        let total = document.info.conflictCount
        var index = 0
        while index < total {
            guard let conflict = try? document.conflict(at: index) else { break }
            guard conflict.choice == .unresolved else {
                index += 1
                continue
            }
            console.write(renderer.render(document: document, index: index, total: total, conflict: conflict, displayName: displayName))
            switch decide(index: index, conflict: conflict) {
            case .resolved: result.resolved += 1
            case .skipped: break
            case .quit:
                result.remaining = document.info.unresolvedCount
                return result
            }
            index += 1
        }
        result.remaining = document.info.unresolvedCount
        return result
    }

    private enum Outcome {
        case resolved
        case skipped
        case quit
    }

    private func decide(index: Int, conflict: LFConflict) -> Outcome {
        while true {
            guard let line = console.readLine(prompt: prompt(for: conflict)) else {
                return .quit
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            guard let action = Self.parse(line) else {
                console.errorLine("unknown key '\(line)'; press ? for help")
                continue
            }
            switch action {
            case .choose(let choice):
                if apply(choice, to: index) { return .resolved }
            case .edit:
                if edit(index: index, conflict: conflict) { return .resolved }
            case .keep: return .skipped
            case .quit: return .quit
            case .help: console.line(Self.help)
            }
        }
    }

    private func apply(_ choice: LFChoice, to index: Int) -> Bool {
        do {
            try document.resolve(index, as: choice)
            return true
        } catch {
            let reason = choice == .base ? "no base section in this conflict (use merge.conflictStyle=diff3)" : "\(error)"
            console.errorLine(reason)
            return false
        }
    }

    private func edit(index: Int, conflict: LFConflict) -> Bool {
        let initial = document.bytes(in: conflict.current) + document.bytes(in: conflict.incoming)
        guard let edited = editor(initial) else {
            console.errorLine("edit cancelled; the conflict is still open")
            return false
        }
        do {
            try document.setCustom(index, bytes: edited)
            return true
        } catch {
            console.errorLine("\(error)")
            return false
        }
    }

    private func prompt(for conflict: LFConflict) -> String {
        let base = conflict.hasBase ? " [a]ncestor" : ""
        return "[c]urrent [i]ncoming [b]oth [B]oth-reversed\(base) [e]dit [k]eep [q]uit ? "
    }

    private static let help = """
      c  keep the current side          i  keep the incoming side
      b  keep both, current first       B  keep both, incoming first
      a  restore the common ancestor (diff3 only)
      e  edit both sides in $EDITOR     k  leave unresolved and continue
      q  stop; progress so far is saved
    """
}

/// Opens `path`, runs an interactive session and saves the result. Shared by `tui` and `mergetool`.
func resolveInteractively(path: String, displayName: String, markerSize: Int, console: Console,
                          editor: @escaping ([UInt8]) -> [UInt8]?) throws -> Int32 {
    if try LFFileProbe(path: path).kind == .binary {
        console.errorLine("error: \(displayName) is a binary file; use `lfgit resolve --all-current` or `--all-incoming`")
        return 1
    }
    let document = try LFDocument(path: path, markerSize: markerSize)
    guard document.info.conflictCount > 0 else {
        console.line("\(displayName): no conflict markers")
        return 0
    }
    let result = InteractiveSession(document: document, displayName: displayName, console: console, editor: editor).run()
    if result.resolved > 0 {
        try document.save(force: true)
    }
    console.line("\n\(displayName): \(result.resolved) resolved, \(result.remaining) unresolved")
    return result.remaining == 0 ? 0 : 1
}
