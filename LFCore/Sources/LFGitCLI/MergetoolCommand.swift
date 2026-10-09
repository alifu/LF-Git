import ArgumentParser
import Foundation
import LFKit

public struct MergetoolCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "mergetool",
        abstract: "Entry point for `git mergetool` (see `lfgit install`).",
        discussion: """
        Git passes the four files of a merge. The result is written to MERGED, and the exit status \
        tells git whether the merge is complete. BASE, LOCAL and REMOTE are accepted for compatibility; \
        the conflicts are taken from the markers already in MERGED.
        """
    )

    @OptionGroup public var global: GlobalOptions

    @Argument(help: "Common ancestor ($BASE).") var base: String
    @Argument(help: "Our version ($LOCAL).") var local: String
    @Argument(help: "Their version ($REMOTE).") var remote: String
    @Argument(help: "The file with conflict markers, which receives the result ($MERGED).") var merged: String

    public init() {}

    public func run() throws {
        try finish(execute(console: StandardConsole()))
    }

    public func execute(console: Console, editor: @escaping ([UInt8]) -> [UInt8]? = ExternalEditor.edit) throws -> Int32 {
        let absolute = global.absolutePath(merged)
        return try resolveInteractively(
            path: absolute, displayName: merged, markerSize: global.git.markerSize(forPath: absolute), console: console,
            editor: editor
        )
    }
}
