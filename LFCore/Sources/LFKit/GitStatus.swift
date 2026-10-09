import Foundation

/// How one side (index or work tree) of a path differs from the one before it.
public enum GitFileStatus: Sendable, Equatable {
    case unmodified
    case modified
    case added
    case deleted
    case renamed
    case copied
    case typeChanged
    case unmerged
    case untracked
    case ignored

    /// The letter used by `git status --porcelain` and `git diff --name-status`.
    init(letter: Character) {
        switch letter {
        case "M": self = .modified
        case "A": self = .added
        case "D": self = .deleted
        case "R": self = .renamed
        case "C": self = .copied
        case "T": self = .typeChanged
        case "U": self = .unmerged
        case "?": self = .untracked
        case "!": self = .ignored
        default: self = .unmodified
        }
    }

    /// One-letter label for lists.
    public var symbol: String {
        switch self {
        case .unmodified: ""
        case .modified: "M"
        case .added: "A"
        case .deleted: "D"
        case .renamed: "R"
        case .copied: "C"
        case .typeChanged: "T"
        case .unmerged: "U"
        case .untracked: "?"
        case .ignored: "!"
        }
    }
}

/// One path in `git status`.
public struct GitChange: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case ordinary
        case renamed
        case unmerged
        case untracked
    }

    public let path: String
    /// Where a renamed or copied file came from.
    public let originalPath: String?
    public let kind: Kind
    /// Staged state (index compared with HEAD).
    public let index: GitFileStatus
    /// Unstaged state (work tree compared with the index).
    public let worktree: GitFileStatus

    public var id: String { path }

    public init(path: String, originalPath: String? = nil, kind: Kind, index: GitFileStatus, worktree: GitFileStatus) {
        self.path = path
        self.originalPath = originalPath
        self.kind = kind
        self.index = index
        self.worktree = worktree
    }

    public var isStaged: Bool { (kind == .ordinary || kind == .renamed) && index != .unmodified }
    public var isUnstaged: Bool { kind == .untracked || ((kind == .ordinary || kind == .renamed) && worktree != .unmodified) }
}

/// The result of `git status`: where HEAD is, how it relates to its upstream, and every changed path.
public struct GitStatus: Sendable, Equatable {
    public var branch: String?
    public var isDetached = false
    /// Full hash of HEAD, nil before the first commit.
    public var commitHash: String?
    public var upstream: String?
    public var ahead = 0
    public var behind = 0
    public var entries: [GitChange] = []

    public init() {}

    public var staged: [GitChange] { entries.filter(\.isStaged) }
    public var unstaged: [GitChange] { entries.filter(\.isUnstaged) }
    public var conflicted: [GitChange] { entries.filter { $0.kind == .unmerged } }
    public var isClean: Bool { entries.isEmpty }
}

/// Parser for `git status --porcelain=v2 --branch -z`.
enum GitStatusParser {
    static func parse(_ data: Data) throws -> GitStatus {
        var status = GitStatus()
        let fields = data.split(separator: 0, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
        var index = 0
        while index < fields.count {
            let field = fields[index]
            index += 1
            if field.hasPrefix("# ") {
                parseHeader(String(field.dropFirst(2)), into: &status)
            } else if field.hasPrefix("1 ") {
                status.entries.append(try ordinary(field))
            } else if field.hasPrefix("2 ") {
                guard index < fields.count else { throw GitError.unexpectedOutput("a rename without its original path") }
                status.entries.append(try renamed(field, original: fields[index]))
                index += 1
            } else if field.hasPrefix("u ") {
                status.entries.append(try unmerged(field))
            } else if field.hasPrefix("? ") {
                status.entries.append(GitChange(path: String(field.dropFirst(2)), kind: .untracked, index: .unmodified, worktree: .untracked))
            }
            // "! " (ignored) entries are not requested; anything else is ignored on purpose.
        }
        return status
    }

    private static func parseHeader(_ line: String, into status: inout GitStatus) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        switch parts[0] {
        case "branch.oid":
            status.commitHash = parts[1] == "(initial)" ? nil : parts[1]
        case "branch.head":
            status.isDetached = parts[1] == "(detached)"
            status.branch = status.isDetached ? nil : parts[1]
        case "branch.upstream":
            status.upstream = parts[1]
        case "branch.ab":
            let numbers = parts[1].split(separator: " ").compactMap { Int($0.dropFirst()) }
            if numbers.count == 2 {
                status.ahead = numbers[0]
                status.behind = numbers[1]
            }
        default:
            break
        }
    }

    private static func letters(_ xy: Substring) -> (GitFileStatus, GitFileStatus) {
        let chars = Array(xy)
        return (GitFileStatus(letter: chars.first ?? "."), GitFileStatus(letter: chars.last ?? "."))
    }

    /// "1 XY sub mH mI mW hH hI path": the path is everything after the eighth space.
    private static func ordinary(_ line: String) throws -> GitChange {
        let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
        guard parts.count == 9 else { throw GitError.unexpectedOutput("status entry: \(line)") }
        let (index, worktree) = letters(parts[1])
        return GitChange(path: String(parts[8]), kind: .ordinary, index: index, worktree: worktree)
    }

    /// "2 XY sub mH mI mW hH hI Xscore path" followed by the original path in the next field.
    private static func renamed(_ line: String, original: String) throws -> GitChange {
        let parts = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
        guard parts.count == 10 else { throw GitError.unexpectedOutput("status entry: \(line)") }
        let (index, worktree) = letters(parts[1])
        return GitChange(path: String(parts[9]), originalPath: original, kind: .renamed, index: index, worktree: worktree)
    }

    /// "u XY sub m1 m2 m3 mW h1 h2 h3 path".
    private static func unmerged(_ line: String) throws -> GitChange {
        let parts = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
        guard parts.count == 11 else { throw GitError.unexpectedOutput("status entry: \(line)") }
        return GitChange(path: String(parts[10]), kind: .unmerged, index: .unmerged, worktree: .unmerged)
    }
}
