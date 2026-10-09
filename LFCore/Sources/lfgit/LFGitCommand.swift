import ArgumentParser
import LFKit

@main
struct LFGitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lfgit",
        abstract: "Resolve git conflicts in very large files, including Xcode project files.",
        version: LFKitInfo.version
    )
}
