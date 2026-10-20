import Foundation
import LFKit
import Observation

/// What the dashboard shows about a repository in the recent list, read without opening it.
nonisolated struct RepositorySummary: Sendable, Equatable {
    var branch: String?
    var changeCount = 0
    var conflictCount = 0
    var ahead = 0
    var behind = 0
    /// A merge, rebase, cherry-pick or revert stopped in the middle.
    var hasUnfinishedOperation = false
    var isMissing = false

    var needsAttention: Bool { conflictCount > 0 || hasUnfinishedOperation }

    static let missing = RepositorySummary(isMissing: true)

    /// Counts the entries of `git status --porcelain=v2 --branch -z`. It only counts: a folder with a hundred thousand
    /// changes must not cost more than a pass over the text.
    static func parse(_ output: Data) -> RepositorySummary {
        var summary = RepositorySummary()
        for field in output.split(separator: 0, omittingEmptySubsequences: true) {
            guard let first = field.first else { continue }
            switch first {
            case UInt8(ascii: "1"), UInt8(ascii: "2"), UInt8(ascii: "?"):
                if field.dropFirst().first == UInt8(ascii: " ") { summary.changeCount += 1 }
            case UInt8(ascii: "u"):
                if field.dropFirst().first == UInt8(ascii: " ") { summary.conflictCount += 1 }
            case UInt8(ascii: "#"):
                summary.readHeader(String(decoding: field.dropFirst(2), as: UTF8.self))
            default:
                break
            }
        }
        return summary
    }

    private mutating func readHeader(_ line: String) {
        if line.hasPrefix("branch.head ") {
            let name = String(line.dropFirst("branch.head ".count))
            branch = name == "(detached)" ? nil : name
        } else if line.hasPrefix("branch.ab ") {
            let numbers = line.dropFirst("branch.ab ".count).split(separator: " ").compactMap { Int($0.dropFirst()) }
            if numbers.count == 2 {
                ahead = numbers[0]
                behind = numbers[1]
            }
        }
    }

    private static let operationMarkers = ["MERGE_HEAD", "rebase-merge", "rebase-apply", "CHERRY_PICK_HEAD", "REVERT_HEAD"]
    /// A summary should answer quickly or not at all; a repository on a sleeping network drive just shows no chips.
    private static let timeout: TimeInterval = 2

    /// Reads one repository. Never throws: a folder that is gone is `missing`, any other failure is an empty summary.
    static func load(path: String) -> RepositorySummary {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return .missing }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        guard let result = try? Git(directory: directory)
            .run(["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=normal"], timeout: timeout) else {
            return RepositorySummary()
        }
        var summary = parse(result.stdout)
        let gitDirectory = directory.appendingPathComponent(".git")
        summary.hasUnfinishedOperation = operationMarkers.contains { manager.fileExists(atPath: gitDirectory.appendingPathComponent($0).path) }
        return summary
    }
}

/// The summaries of the recent repositories, filled in as each one arrives.
@Observable
final class RepositorySummaries {
    private(set) var byPath: [String: RepositorySummary] = [:]
    /// Repositories read at the same time: enough to feel instant, few enough to leave the disk alone.
    private static let parallelism = 3

    func summary(for path: String) -> RepositorySummary? { byPath[path] }

    func refresh(_ paths: [String]) async {
        await withTaskGroup(of: (String, RepositorySummary).self) { group in
            var pending = paths.makeIterator()
            func startNext() {
                guard !Task.isCancelled, let path = pending.next() else { return }
                group.addTask { (path, await Self.load(path)) }
            }
            for _ in 0..<Self.parallelism { startNext() }
            for await (path, summary) in group {
                byPath[path] = summary
                startNext()
            }
        }
    }

    @concurrent
    nonisolated private static func load(_ path: String) async -> RepositorySummary {
        RepositorySummary.load(path: path)
    }
}
