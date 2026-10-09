import ArgumentParser
import Foundation
import LFKit

public struct DriverCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "driver",
        abstract: "Git merge driver (see `lfgit install --attributes`).",
        discussion: """
        Merges OTHER into CURRENT using ANCESTOR as the base and writes the result to CURRENT. \
        Exits 0 when the merge is clean and 1 when conflicts remain. Xcode project files \
        (*.pbxproj) are merged object by object; other files, and project files in an unknown \
        layout, line by line. Conflicts use diff3 markers, so the common ancestor stays \
        available to `lfgit resolve --all-base` and the merge tools.
        """
    )

    private static let maxConflictStatus: Int32 = 127
    private static let internalErrorStatus: Int32 = 2

    @Argument(help: "Common ancestor (%O).") var ancestor: String
    @Argument(help: "Current version, overwritten with the result (%A).") var current: String
    @Argument(help: "Other branch's version (%B).") var other: String
    @Argument(help: "Conflict marker size (%L).") var markerSize: Int
    @Argument(help: "Path of the file in the repository (%P).") var pathname: String

    public init() {}

    public func run() throws {
        try finish(execute(console: StandardConsole()))
    }

    public func execute(console: Console) throws -> Int32 {
        if MergeStrategy.forPath(pathname) == .pbxproj, let code = mergeProject(console: console) {
            return code
        }
        return mergeLines(console: console)
    }

    /// Object-level merge; nil means "use the line-based merge instead".
    private func mergeProject(console: Console) -> Int32? {
        do {
            let result = try PbxprojMerge.merge(
                base: try readBytes(ancestor), ours: try readBytes(current), theirs: try readBytes(other),
                markerSize: max(markerSize, 1)
            )
            guard !result.isClean || PropertyListCheck.isValid(result.bytes) else {
                console.errorLine("lfgit: \(pathname): the merged project did not validate; using a line-based merge")
                return nil
            }
            try Data(result.bytes).write(to: URL(fileURLWithPath: current), options: .atomic)
            return result.isClean ? 0 : 1
        } catch {
            console.errorLine("lfgit: \(pathname): \(error); using a line-based merge")
            return nil
        }
    }

    private func readBytes(_ path: String) throws -> [UInt8] {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw CLIError("cannot read \(path)")
        }
        return Array(data)
    }

    private func mergeLines(console: Console) -> Int32 {
        let directory = URL(fileURLWithPath: current).deletingLastPathComponent()
        let arguments = [
            "merge-file", "--diff3", "--marker-size=\(max(markerSize, 1))",
            "-L", "HEAD", "-L", "base", "-L", "incoming", current, ancestor, other,
        ]
        let result: GitResult
        do {
            result = try Git(directory: directory).run(arguments, allowedStatuses: Set(0...255))
        } catch {
            console.errorLine("error: \(pathname): \(error)")
            return Self.internalErrorStatus
        }
        switch result.status {
        case 0:
            return 0
        case 1...Self.maxConflictStatus:
            return 1
        default:
            console.errorLine("error: \(pathname): git merge-file failed: \(result.stderr)")
            return Self.internalErrorStatus
        }
    }
}
