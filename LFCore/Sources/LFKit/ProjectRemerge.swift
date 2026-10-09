import Foundation

/// Re-merges a conflicted Xcode project file object by object, from the three versions git keeps in
/// the index (stage 1 = base, 2 = ours, 3 = theirs). Shared by `lfgit remerge` and the app.
public struct ProjectRemerge: Sendable {
    public struct Options: Sendable {
        /// Re-merge even if the working file no longer has conflict markers.
        public var force = false
        /// Compute the result but write nothing.
        public var dryRun = false
        /// Keep the replaced working file as `<file>.orig`.
        public var backup = true
        /// `git add` the file when the result has no conflicts left.
        public var stage = false

        public init(force: Bool = false, dryRun: Bool = false, backup: Bool = true, stage: Bool = false) {
            self.force = force
            self.dryRun = dryRun
            self.backup = backup
            self.stage = stage
        }
    }

    public struct Outcome: Sendable {
        public let path: String
        public let result: LFMergeResult
        public let wrote: Bool
        /// File name of the `.orig` copy, if one was written.
        public let backupName: String?
        /// Files in a modify/delete conflict whose project entry the merge removed: keeping such a
        /// file means adding it back to the project.
        public let filesToReAdd: [String]

        public var isClean: Bool { result.isClean }
    }

    public enum Failure: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
        case notAProjectFile(String)
        case noConflictMarkers(String)
        case notUnmerged(path: String, stage: Int)
        case invalidResult(String)

        public var description: String {
            switch self {
            case .notAProjectFile(let path):
                "\(path) is not an Xcode project file"
            case .noConflictMarkers(let path):
                "\(path) has no conflict markers (already resolved?)"
            case .notUnmerged(let path, let stage):
                "\(path) is not unmerged in the index (stage \(stage) is missing); re-merging needs a conflicted merge, rebase or cherry-pick"
            case .invalidResult(let path):
                "the merged \(path) did not validate as a property list; nothing was written"
            }
        }

        public var errorDescription: String? { description }
    }

    public let root: URL

    /// `root` is the repository's top-level directory; paths are relative to it.
    public init(root: URL) {
        self.root = root
    }

    private var git: Git { Git(directory: root) }

    public func run(_ path: String, options: Options = Options()) throws -> Outcome {
        guard MergeStrategy.forPath(path) == .pbxproj else {
            throw Failure.notAProjectFile(path)
        }
        let absolute = root.appendingPathComponent(path).path
        if !options.force, try !hasMarkers(absolute) {
            throw Failure.noConflictMarkers(path)
        }
        let versions = [try stage(1, of: path), try stage(2, of: path), try stage(3, of: path)]
        let result = try PbxprojMerge.merge(
            base: versions[0], ours: versions[1], theirs: versions[2], markerSize: git.markerSize(forPath: absolute)
        )
        let reAdd = filesToReAdd(result: result, versions: versions)
        guard !options.dryRun else {
            return Outcome(path: path, result: result, wrote: false, backupName: nil, filesToReAdd: reAdd)
        }
        guard !result.isClean || PropertyListCheck.isValid(result.bytes) else {
            throw Failure.invalidResult(path)
        }
        let backup = options.backup ? try keepBackup(of: absolute) : nil
        try Data(result.bytes).write(to: URL(fileURLWithPath: absolute), options: .atomic)
        if result.isClean && options.stage {
            try git.stage([path])
        }
        return Outcome(path: path, result: result, wrote: true, backupName: backup, filesToReAdd: reAdd)
    }

    private func hasMarkers(_ absolute: String) throws -> Bool {
        guard FileManager.default.fileExists(atPath: absolute) else { return true }
        return try LFDocument(path: absolute, markerSize: git.markerSize(forPath: absolute)).info.conflictCount > 0
    }

    private func stage(_ number: Int, of path: String) throws -> [UInt8] {
        let result = try git.run(["show", ":\(number):\(path)"], allowedStatuses: [0, 128])
        guard result.status == 0 else {
            throw Failure.notUnmerged(path: path, stage: number)
        }
        return Array(result.stdout)
    }

    /// A file reference can only be judged from the project file. If the file itself is in a modify/delete
    /// conflict and the merge dropped its reference, keeping the file means adding it back.
    private func filesToReAdd(result: LFMergeResult, versions: [[UInt8]]) -> [String] {
        guard let paths = try? git.modifyDeletePaths(), !paths.isEmpty else { return [] }
        let merged = String(decoding: result.bytes, as: UTF8.self)
        let inputs = versions.map { String(decoding: $0, as: UTF8.self) }
        return paths.filter { path in
            let reference = "/* \((path as NSString).lastPathComponent) */ = {isa = PBXFileReference"
            return !merged.contains(reference) && inputs.contains { $0.contains(reference) }
        }
    }

    private func keepBackup(of absolute: String) throws -> String? {
        guard let current = FileManager.default.contents(atPath: absolute) else { return nil }
        let backup = absolute + ".orig"
        try current.write(to: URL(fileURLWithPath: backup), options: .atomic)
        return (backup as NSString).lastPathComponent
    }
}
