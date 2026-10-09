import ArgumentParser
import Foundation
import LFKit

/// The `-C <dir>` option shared by every command, as in git.
public struct GlobalOptions: ParsableArguments {
    @Option(name: [.customShort("C")], help: ArgumentHelp("Run as if started in <directory>.", valueName: "directory"))
    public var directory: String?

    public init() {}

    var workingDirectory: URL {
        URL(fileURLWithPath: directory ?? FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    var git: Git { Git(directory: workingDirectory) }

    /// Absolute path of a user-supplied path (relative paths are relative to `-C`).
    func absolutePath(_ path: String) -> String {
        URL(fileURLWithPath: path, relativeTo: workingDirectory).standardizedFileURL.path
    }
}

extension Git {
    /// Path of `absolutePath` relative to the repository root, for git commands that take pathspecs.
    func repositoryRelativePath(of absolutePath: String) throws -> String {
        let root = try repositoryRoot().resolvingSymlinksInPath().path
        let resolved = URL(fileURLWithPath: absolutePath).resolvingSymlinksInPath().path
        guard resolved.hasPrefix(root + "/") else {
            throw CLIError("outside the repository (\(root))")
        }
        return String(resolved.dropFirst(root.count + 1))
    }
}
