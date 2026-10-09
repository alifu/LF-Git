import ArgumentParser
import Foundation
import LFKit

public struct InteractiveCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "tui",
        abstract: "Resolve the conflicts of one file interactively in the terminal."
    )

    @OptionGroup public var global: GlobalOptions

    @Flag(help: "Run `git add` on the file once every conflict is resolved.")
    var stage = false

    @Argument(help: "The conflicted file.")
    var file: String

    public init() {}

    public func run() throws {
        try finish(execute(console: StandardConsole()))
    }

    public func execute(console: Console, editor: @escaping ([UInt8]) -> [UInt8]? = ExternalEditor.edit) throws -> Int32 {
        let absolute = global.absolutePath(file)
        let git = global.git
        let code = try resolveInteractively(
            path: absolute, displayName: file, markerSize: git.markerSize(forPath: absolute), console: console, editor: editor
        )
        if code == 0 && stage {
            try git.stage([git.repositoryRelativePath(of: absolute)])
        }
        return code
    }
}
