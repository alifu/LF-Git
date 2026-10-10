import Foundation
import LFKit

/// One line in the log panel: a git command that ran, or something the app did or hit.
struct LogEvent: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A git (or custom) command; `succeeded` is its exit status.
        case git
        /// An action the user started or finished (Fetching…, Pull, Merge).
        case action
        /// Something that happened on its own, such as a reload after an outside edit.
        case info
        case error
    }

    let id: Int
    let date: Date
    let kind: Kind
    let text: String
    let succeeded: Bool
    let duration: TimeInterval?

    var isProblem: Bool { kind == .error || (kind == .git && !succeeded) }
}

/// What the log panel shows.
enum LogFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case git = "Git"
    case actions = "Actions"
    case problems = "Problems"

    var id: String { rawValue }

    func includes(_ event: LogEvent) -> Bool {
        switch self {
        case .all: true
        case .git: event.kind == .git
        case .actions: event.kind == .action || event.kind == .info
        case .problems: event.isProblem
        }
    }
}

extension LogEvent {
    /// The panel's text for copying: one line per event.
    static func transcript(_ events: [LogEvent]) -> String {
        events.map { event in
            let time = event.date.formatted(.dateTime.hour().minute().second())
            return "\(time)  \(event.text)"
        }.joined(separator: "\n")
    }
}
