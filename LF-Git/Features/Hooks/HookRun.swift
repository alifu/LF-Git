import Foundation
import LFKit

/// One command whose hooks ran inside LF-Git (a push, a commit), with what the hooks printed.
struct HookRun: Identifiable, Equatable {
    enum State: Equatable {
        case running
        case passed
        case failed(String)
    }

    let id: Int
    let title: String
    let started: Date
    private(set) var text = ""
    private(set) var state = State.running
    private(set) var ended: Date?
    private(set) var isTruncated = false

    /// Output kept per run. A chatty guardrail must not grow memory without bound.
    static let characterLimit = 400_000

    init(id: Int, title: String, started: Date = Date()) {
        self.id = id
        self.title = title
        self.started = started
    }

    func appending(_ chunk: String) -> HookRun {
        var copy = self
        let cleaned = Self.stripControlSequences(chunk)
        let room = Self.characterLimit - text.count
        if cleaned.count > room {
            copy.text += String(cleaned.prefix(max(room, 0)))
            copy.isTruncated = true
        } else {
            copy.text += cleaned
        }
        return copy
    }

    func finished(_ state: State, at date: Date = Date()) -> HookRun {
        var copy = self
        copy.state = state
        copy.ended = date
        return copy
    }

    var duration: TimeInterval? { ended.map { $0.timeIntervalSince(started) } }

    /// Removes ANSI colour and cursor codes, and turns carriage-return progress redraws into plain lines.
    static func stripControlSequences(_ text: String) -> String {
        let withoutEscapes = text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
        return withoutEscapes.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

/// The recent hook runs of one repository window.
@Observable
final class HookRunStore {
    static let capacity = 20

    private(set) var runs: [HookRun] = []
    private var counter = 0

    var latest: HookRun? { runs.last }

    /// Starts a run and returns its id.
    @discardableResult
    func begin(title: String, at date: Date = Date()) -> Int {
        counter += 1
        runs = Array((runs + [HookRun(id: counter, title: title, started: date)]).suffix(Self.capacity))
        return counter
    }

    func append(_ chunk: String, to id: Int) {
        guard !chunk.isEmpty else { return }
        update(id) { $0.appending(chunk) }
    }

    func finish(_ id: Int, error: Error?, at date: Date = Date()) {
        let state: HookRun.State
        if let error {
            state = (error as? GitError) == .cancelled ? .failed("cancelled") : .failed("\(error)")
        } else {
            state = .passed
        }
        update(id) { $0.finished(state, at: date) }
    }

    func clear() {
        runs = runs.filter { $0.state == .running }
    }

    private func update(_ id: Int, _ change: (HookRun) -> HookRun) {
        runs = runs.map { $0.id == id ? change($0) : $0 }
    }
}
