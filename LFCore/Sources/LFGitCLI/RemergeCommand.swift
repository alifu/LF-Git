import ArgumentParser
import Foundation
import LFKit

public struct RemergeCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "remerge",
        abstract: "Re-merge conflicted Xcode project files object by object, from git's index.",
        discussion: """
        After a merge, rebase or cherry-pick that left project.pbxproj full of line-based conflicts, \
        this reads the three versions git keeps in the index (base, ours, theirs) and merges them \
        object by object. Usually nothing is left to resolve; otherwise only the real disagreements \
        remain, as small conflict blocks. A file whose markers are already gone is not touched \
        unless --force is given. The working file is replaced as a whole, so the version it \
        replaces (including any hunks you already resolved by hand) is kept as <file>.orig.
        """
    )

    @OptionGroup public var global: GlobalOptions

    @Flag(help: "Run `git add` on each file that merged completely.")
    var stage = false
    @Flag(name: .customLong("dry-run"), help: "Show what would happen without writing anything.")
    var dryRun = false
    @Flag(help: "Re-merge even if the file no longer contains conflict markers.")
    var force = false
    @Flag(name: .customLong("no-backup"), help: "Do not keep the replaced working file as <file>.orig.")
    var noBackup = false

    @Argument(help: "Project files to re-merge. Defaults to every conflicted *.pbxproj.")
    var files: [String] = []

    public init() {}

    public func run() throws {
        try finish(execute(console: StandardConsole()))
    }

    public func execute(console: Console) throws -> Int32 {
        let root = try global.git.repositoryRoot()
        let git = Git(directory: root)
        var failures = 0
        var paths: [String] = []
        if files.isEmpty {
            paths = try git.conflictedPaths().filter { MergeStrategy.forPath($0) == .pbxproj }
            if paths.isEmpty {
                console.line("No conflicted Xcode project files.")
                return 0
            }
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
        for path in paths where !remerge(path, root: root, git: git, console: console) {
            failures += 1
        }
        return failures == 0 ? 0 : 1
    }

    /// True when the file ends up (or would end up) completely merged.
    private func remerge(_ path: String, root: URL, git: Git, console: Console) -> Bool {
        let options = ProjectRemerge.Options(force: force, dryRun: dryRun, backup: !noBackup, stage: stage)
        do {
            let outcome = try ProjectRemerge(root: root).run(path, options: options)
            report(outcome, console: console)
            return outcome.isClean
        } catch ProjectRemerge.Failure.notAProjectFile {
            console.errorLine("error: \(path): only Xcode project files can be re-merged; use `lfgit resolve` or `lfgit tui`")
        } catch ProjectRemerge.Failure.noConflictMarkers {
            console.errorLine("error: \(path) has no conflict markers (already resolved?); use --force to re-merge it from the index")
        } catch {
            console.errorLine("error: \(path): \(error)")
        }
        return false
    }

    private func report(_ outcome: ProjectRemerge.Outcome, console: Console) {
        let result = outcome.result
        let combined = plural(result.mergedObjectCount, "object") + " combined"
        let summary = result.isClean ? "cleanly (\(combined))" : "(\(combined), \(plural(result.conflictCount, "conflict")) left)"
        if outcome.wrote {
            console.line("merged \(outcome.path) \(summary)" + (outcome.backupName.map { "; previous version saved as \($0)" } ?? ""))
        } else {
            console.line("would merge \(outcome.path) \(summary)")
        }
        for file in outcome.filesToReAdd {
            console.errorLine("warning: \(file) has a modify/delete conflict and the merged project no longer lists it; if you keep the file, add it back to the project in Xcode")
        }
    }
}
