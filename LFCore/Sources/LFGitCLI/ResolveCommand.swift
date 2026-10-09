import ArgumentParser
import Foundation
import LFKit

public struct ResolveCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "resolve",
        abstract: "Resolve every conflict in the given files (or all conflicted files) the same way.",
        discussion: """
        Text files take the chosen side of every conflict. Binary files take a whole side \
        (--all-current or --all-incoming only). Current is the side marked HEAD, incoming the other branch.
        """
    )

    @OptionGroup public var global: GlobalOptions

    @Flag(name: .customLong("all-current"), help: "Keep the current (HEAD) side.")
    var allCurrent = false
    @Flag(name: .customLong("all-incoming"), help: "Keep the incoming side.")
    var allIncoming = false
    @Flag(name: .customLong("all-both"), help: "Keep both sides, current first.")
    var allBoth = false
    @Flag(name: .customLong("all-both-incoming-first"), help: "Keep both sides, incoming first.")
    var allBothIncomingFirst = false
    @Flag(name: .customLong("all-base"), help: "Restore the common ancestor (needs merge.conflictStyle=diff3).")
    var allBase = false

    @Flag(help: "Run `git add` on each resolved file.")
    var stage = false
    @Flag(name: .customLong("dry-run"), help: "Show what would happen without writing anything.")
    var dryRun = false

    @Argument(help: "Files to resolve. Defaults to every conflicted file in the repository.")
    var files: [String] = []

    public init() {}

    public mutating func validate() throws {
        let chosen = [allCurrent, allIncoming, allBoth, allBothIncomingFirst, allBase].filter { $0 }.count
        guard chosen == 1 else {
            throw ValidationError(
                "choose exactly one of --all-current, --all-incoming, --all-both, --all-both-incoming-first, --all-base"
            )
        }
    }

    private var choice: LFChoice {
        if allIncoming { return .incoming }
        if allBoth { return .bothCurrentFirst }
        if allBothIncomingFirst { return .bothIncomingFirst }
        if allBase { return .base }
        return .current
    }

    public func run() throws {
        try finish(execute(console: StandardConsole()))
    }

    public func execute(console: Console) throws -> Int32 {
        let root = try global.git.repositoryRoot()
        let git = Git(directory: root)
        var failures = 0
        var paths: [String] = []
        if files.isEmpty {
            paths = try git.conflictedPaths()
        } else {
            for file in files {
                do {
                    paths.append(try git.repositoryRelativePath(of: global.absolutePath(file)))
                } catch {
                    console.errorLine("error: \(file): \(error)")
                    failures += 1
                }
            }
        }
        guard !paths.isEmpty || failures > 0 else {
            console.line("No conflicted files.")
            return 0
        }
        for path in paths where !resolve(path, root: root, git: git, console: console) {
            failures += 1
        }
        if failures > 0 {
            console.errorLine("\(plural(failures, "file")) could not be resolved.")
        }
        return failures == 0 ? 0 : 1
    }

    private func resolve(_ path: String, root: URL, git: Git, console: Console) -> Bool {
        let absolute = root.appendingPathComponent(path).path
        do {
            if try LFFileProbe(path: absolute).kind == .binary {
                try resolveBinary(path, git: git, console: console)
            } else {
                try resolveText(path, absolute: absolute, git: git, console: console)
            }
            return true
        } catch {
            console.errorLine("error: \(path): \(error)")
            return false
        }
    }

    private func resolveText(_ path: String, absolute: String, git: Git, console: Console) throws {
        let document = try LFDocument(path: absolute, markerSize: git.markerSize(forPath: absolute))
        let count = document.info.conflictCount
        guard count > 0 else {
            // Not staged: a file that is still unmerged but has no markers may be a failed merge, not a resolved one.
            console.line("\(path): no conflict markers, skipped (run `git add \(path)` if it is already resolved)")
            return
        }
        try document.resolveAll(as: choice)
        guard !dryRun else {
            console.line("would resolve \(plural(count, "conflict")) in \(path)")
            return
        }
        try document.save()
        console.line("resolved \(plural(count, "conflict")) in \(path)")
        try stageIfRequested(path, git: git)
    }

    private func resolveBinary(_ path: String, git: Git, console: Console) throws {
        let side: Git.Side
        let name: String
        switch choice {
        case .current: (side, name) = (.ours, "current")
        case .incoming: (side, name) = (.theirs, "incoming")
        default:
            throw CLIError("binary file: only --all-current or --all-incoming can resolve it")
        }
        guard !dryRun else {
            console.line("would take the \(name) version of \(path)")
            return
        }
        try git.checkout(side, path: path)
        console.line("took the \(name) version of \(path)")
        try stageIfRequested(path, git: git)
    }

    private func stageIfRequested(_ path: String, git: Git) throws {
        if stage && !dryRun {
            try git.stage([path])
        }
    }
}
