import ArgumentParser
import LFKit

public struct LFGitCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "lfgit",
        abstract: "Resolve git conflicts in very large files, including Xcode project files.",
        version: LFKitInfo.version,
        subcommands: [
            StatusCommand.self,
            ResolveCommand.self,
            RemergeCommand.self,
            InteractiveCommand.self,
            MergetoolCommand.self,
            DriverCommand.self,
            InstallCommand.self,
        ]
    )

    public init() {}
}
