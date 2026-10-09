import Foundation

public struct GitCommit: Sendable, Equatable, Identifiable {
    public let hash: String
    public let parents: [String]
    public let authorName: String
    public let authorEmail: String
    public let date: Date
    /// Branches and tags pointing here, e.g. `main`, `origin/main`, `tag: v1`.
    public let refs: [String]
    public let subject: String

    public var id: String { hash }
    public var shortHash: String { String(hash.prefix(7)) }
    public var isMerge: Bool { parents.count > 1 }

    public init(hash: String, parents: [String], authorName: String, authorEmail: String, date: Date,
                refs: [String], subject: String) {
        self.hash = hash
        self.parents = parents
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.date = date
        self.refs = refs
        self.subject = subject
    }
}

/// One file changed by a commit.
public struct CommitFileChange: Sendable, Equatable, Identifiable {
    public let path: String
    public let originalPath: String?
    public let status: GitFileStatus

    public var id: String { path }
}

/// What to look for when listing history.
public struct GitLogFilter: Sendable, Equatable {
    public var path: String?
    public var author: String?
    /// Text in the commit message (plain text, not a pattern).
    public var message: String?
    /// Start from this branch/tag/commit instead of HEAD.
    public var revision: String?
    public var followRenames = false
    public var includeMerges = true

    public init(path: String? = nil, author: String? = nil, message: String? = nil, revision: String? = nil,
                followRenames: Bool = false, includeMerges: Bool = true) {
        self.path = path
        self.author = author
        self.message = message
        self.revision = revision
        self.followRenames = followRenames
        self.includeMerges = includeMerges
    }

    public var isEmpty: Bool { self == GitLogFilter() }
}

extension GitClient {
    private static let fieldSeparator = "\u{1F}"

    /// Commits of the current branch, newest first; `allBranches` includes every ref.
    public func log(maxCount: Int? = nil, skip: Int = 0, allBranches: Bool = false,
                    filter: GitLogFilter = GitLogFilter()) throws -> [GitCommit] {
        // -z ends every record with NUL, which a commit subject cannot contain. --topo-order lists every
        // commit before its parents, which the graph layout relies on (dates alone can be skewed).
        let format = ["%H", "%P", "%an", "%ae", "%at", "%D", "%s"].joined(separator: "%x1f")
        var arguments = ["log", "-z", "--topo-order", "--decorate=short", "--format=\(format)"]
        if let maxCount { arguments.append("--max-count=\(maxCount)") }
        if skip > 0 { arguments.append("--skip=\(skip)") }
        if allBranches { arguments.append("--all") }
        // Search text travels inside a single `--option=value` argument, so it can never be read as an option.
        if let author = filter.author, !author.isEmpty { arguments.append("--author=\(author)") }
        if let message = filter.message, !message.isEmpty { arguments += ["--grep=\(message)", "--fixed-strings", "--regexp-ignore-case"] }
        if !filter.includeMerges { arguments.append("--no-merges") }
        if let revision = filter.revision {
            try requireName(revision, what: "revision")
            arguments.append(revision)
        }
        if let path = filter.path, !path.isEmpty {
            if filter.followRenames { arguments.append("--follow") }
            arguments += ["--", path]
        }
        let result = try git.run(arguments, allowedStatuses: [0, 128])
        if result.status == 128 {
            if result.stderr.contains("does not have any commits") { return [] }
            throw GitError.failed(arguments: arguments, status: 128, stderr: result.stderr)
        }
        return result.stdout.split(separator: 0, omittingEmptySubsequences: true)
            .compactMap { Self.commit(fromRecord: String(decoding: $0, as: UTF8.self)) }
    }

    static func commit(fromRecord record: String) -> GitCommit? {
        let fields = record.components(separatedBy: fieldSeparator)
        guard fields.count >= 7, !fields[0].isEmpty else { return nil }
        // The subject is last; if it contains the field separator itself, put it back together.
        let subject = fields[6...].joined(separator: fieldSeparator)
        let refs = fields[5].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("HEAD -> ") ? String($0.dropFirst("HEAD -> ".count)) : $0 }
        return GitCommit(
            hash: fields[0], parents: fields[1].split(separator: " ").map(String.init), authorName: fields[2],
            authorEmail: fields[3], date: Date(timeIntervalSince1970: TimeInterval(fields[4]) ?? 0), refs: refs,
            subject: subject
        )
    }

    /// The files a commit changed (a merge commit is compared with its first parent).
    public func changedFiles(in commit: GitCommit) throws -> [CommitFileChange] {
        try nameStatus(from: try baseRevision(of: commit), to: commit.hash)
    }

    /// The files that differ between two revisions.
    public func changedFiles(from: String, to: String) throws -> [CommitFileChange] {
        try requireName(from, what: "revision")
        try requireName(to, what: "revision")
        return try nameStatus(from: from, to: to)
    }

    private func nameStatus(from base: String, to target: String) throws -> [CommitFileChange] {
        let result = try git.run(["diff", "--name-status", "-z", "-M", base, target])
        let fields = result.stdout.split(separator: 0, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
        var changes: [CommitFileChange] = []
        var index = 0
        while index < fields.count {
            let status = GitFileStatus(letter: fields[index].first ?? " ")
            index += 1
            let pathCount = (status == .renamed || status == .copied) ? 2 : 1
            guard index + pathCount <= fields.count else { throw GitError.unexpectedOutput("diff --name-status") }
            changes.append(CommitFileChange(
                path: fields[index + pathCount - 1], originalPath: pathCount == 2 ? fields[index] : nil, status: status
            ))
            index += pathCount
        }
        return changes
    }

    /// What a commit is compared with: its first parent, or the empty tree for a root commit.
    func baseRevision(of commit: GitCommit) throws -> String {
        if let parent = commit.parents.first { return parent }
        return try git.run(["hash-object", "-t", "tree", "/dev/null"]).text
    }
}

/// Lays commits out in lanes for drawing a history graph. Commits must be appended newest first,
/// in pages if needed: the layout continues exactly where the previous page ended.
public struct CommitGraph: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        /// The lane the commit's dot sits in.
        public let lane: Int
        /// How many lanes this row needs.
        public let laneCount: Int
        /// A line comes into the dot from above (a child commit exists).
        public let hasLineAbove: Bool
        /// A line leaves the dot downwards (the first parent exists).
        public let continuesDown: Bool
        /// Other lanes with a vertical line running straight through this row.
        public let passingLanes: [Int]
        /// Other lanes whose line ends in this commit (branches that start here).
        public let mergedLanes: [Int]
        /// Other lanes that start at this commit, towards its further parents (a merge).
        public let branchedLanes: [Int]
    }

    public private(set) var rows: [Row] = []
    /// The commit each lane is waiting for, nil for a free lane.
    private var lanes: [String?] = []

    public init() {}

    public mutating func append(_ commits: [GitCommit]) {
        for commit in commits {
            rows.append(place(commit))
        }
    }

    private mutating func firstFreeLane(avoiding taken: Int? = nil) -> Int {
        if let free = lanes.indices.first(where: { lanes[$0] == nil && $0 != taken }) {
            return free
        }
        lanes.append(nil)
        return lanes.count - 1
    }

    private mutating func place(_ commit: GitCommit) -> Row {
        let waiting = lanes.indices.filter { lanes[$0] == commit.hash }
        let hasLineAbove = !waiting.isEmpty
        let lane = waiting.first ?? firstFreeLane()
        let merged = Array(waiting.dropFirst())
        let passing = lanes.indices.filter { $0 != lane && lanes[$0] != nil && !merged.contains($0) }
        var widest = lanes.count

        for lane in merged { lanes[lane] = nil }
        lanes[lane] = commit.parents.first
        var branched: [Int] = []
        for parent in commit.parents.dropFirst() {
            if let existing = lanes.indices.first(where: { lanes[$0] == parent }) {
                branched.append(existing)
            } else {
                let free = firstFreeLane(avoiding: lane)
                lanes[free] = parent
                branched.append(free)
            }
        }
        widest = max(widest, lanes.count)
        while lanes.last == .some(nil) { lanes.removeLast() }

        return Row(lane: lane, laneCount: widest, hasLineAbove: hasLineAbove, continuesDown: !commit.parents.isEmpty,
                   passingLanes: passing, mergedLanes: merged, branchedLanes: branched.sorted())
    }
}

extension GitClient {
    /// One commit by hash, tag or branch name.
    public func commit(for revision: String) throws -> GitCommit? {
        try requireName(revision, what: "revision")
        let format = ["%H", "%P", "%an", "%ae", "%at", "%D", "%s"].joined(separator: "%x1f")
        let result = try git.run(["log", "-1", "-z", "--decorate=short", "--format=\(format)", revision, "--"],
                                 allowedStatuses: [0, 128])
        guard result.status == 0 else { return nil }
        return Self.commit(fromRecord: String(decoding: result.stdout.prefix { $0 != 0 }, as: UTF8.self))
    }
}

extension GitClient {
    /// The whole message of a commit (subject and body).
    public func message(of commit: GitCommit) throws -> String {
        try git.run(["log", "-1", "--format=%B", commit.hash, "--"]).text
    }
}
