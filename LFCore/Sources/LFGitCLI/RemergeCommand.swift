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
        guard MergeStrategy.forPath(path) == .pbxproj else {
            console.errorLine("error: \(path): only Xcode project files can be re-merged; use `lfgit resolve` or `lfgit tui`")
            return false
        }
        let absolute = root.appendingPathComponent(path).path
        do {
            if !force, try !hasMarkers(absolute, git: git) {
                console.errorLine("error: \(path) has no conflict markers (already resolved?); use --force to re-merge it from the index")
                return false
            }
            let versions = [try stage(1, of: path, git: git), try stage(2, of: path, git: git), try stage(3, of: path, git: git)]
            let result = try PbxprojMerge.merge(
                base: versions[0], ours: versions[1], theirs: versions[2], markerSize: git.markerSize(forPath: absolute)
            )
            let merged = try apply(result, to: path, absolute: absolute, git: git, console: console)
            warnAboutDeletedFiles(result: result, versions: versions, git: git, console: console)
            return merged
        } catch {
            console.errorLine("error: \(path): \(error)")
            return false
        }
    }

    /// A file reference can only be judged from the project file. If the file itself is in a modify/delete
    /// conflict and the merge dropped its reference, keeping the file means adding it back: say so.
    private func warnAboutDeletedFiles(result: LFMergeResult, versions: [[UInt8]], git: Git, console: Console) {
        guard let paths = try? git.modifyDeletePaths(), !paths.isEmpty else { return }
        let merged = String(decoding: result.bytes, as: UTF8.self)
        let inputs = versions.map { String(decoding: $0, as: UTF8.self) }
        for path in paths {
            let name = (path as NSString).lastPathComponent
            let reference = "/* \(name) */ = {isa = PBXFileReference"
            if !merged.contains(reference), inputs.contains(where: { $0.contains(reference) }) {
                console.errorLine("warning: \(path) has a modify/delete conflict and the merged project no longer lists it; if you keep the file, add it back to the project in Xcode")
            }
        }
    }

    /// Copies the working file to <file>.orig before it is replaced. Returns the backup's name.
    private func keepBackup(of absolute: String) throws -> String? {
        guard !noBackup, let current = FileManager.default.contents(atPath: absolute) else { return nil }
        let backup = absolute + ".orig"
        try current.write(to: URL(fileURLWithPath: backup), options: .atomic)
        return (backup as NSString).lastPathComponent
    }

    private func hasMarkers(_ absolute: String, git: Git) throws -> Bool {
        guard FileManager.default.fileExists(atPath: absolute) else { return true }
        return try LFDocument(path: absolute, markerSize: git.markerSize(forPath: absolute)).info.conflictCount > 0
    }

    private func stage(_ number: Int, of path: String, git: Git) throws -> [UInt8] {
        let result = try git.run(["show", ":\(number):\(path)"], allowedStatuses: [0, 128])
        guard result.status == 0 else {
            throw CLIError("not unmerged in the index (stage \(number) is missing); re-merging needs a conflicted merge, rebase or cherry-pick")
        }
        return Array(result.stdout)
    }

    private func apply(_ result: LFMergeResult, to path: String, absolute: String, git: Git, console: Console) throws -> Bool {
        let combined = plural(result.mergedObjectCount, "object") + " combined"
        let summary = result.isClean ? "cleanly (\(combined))" : "(\(combined), \(plural(result.conflictCount, "conflict")) left)"
        guard !dryRun else {
            console.line("would merge \(path) \(summary)")
            return result.isClean
        }
        guard !result.isClean || PropertyListCheck.isValid(result.bytes) else {
            throw CLIError("the merged project did not validate as a property list; nothing was written")
        }
        let backup = try keepBackup(of: absolute)
        try Data(result.bytes).write(to: URL(fileURLWithPath: absolute), options: .atomic)
        console.line("merged \(path) \(summary)" + (backup.map { "; previous version saved as \($0)" } ?? ""))
        if result.isClean && stage {
            try git.stage([path])
        }
        return result.isClean
    }
}
