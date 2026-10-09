import ArgumentParser
import Foundation
import LFKit

public struct OpenCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Open the repository (and optionally one file) in the LF-Git app.",
        discussion: """
        The app is found through $LFGIT_APP, then an LF-Git.app next to the lfgit binary \
        (the Homebrew layout), then macOS's usual application lookup.
        """
    )

    static let appName = "LF-Git"

    @OptionGroup public var global: GlobalOptions

    @Argument(help: "A conflicted file to select.")
    var file: String?

    public init() {}

    public func run() throws {
        // Bundle.main gives the real path even when lfgit was started by name through PATH.
        let executable = Bundle.main.executablePath ?? CommandLine.arguments.first ?? "lfgit"
        let code = try execute(
            console: StandardConsole(), environment: ProcessInfo.processInfo.environment,
            executablePath: executable, launch: Self.openWithLaunchServices
        )
        try finish(code)
    }

    /// `launch` receives the arguments for /usr/bin/open and returns its exit status.
    public func execute(console: Console, environment: [String: String], executablePath: String,
                        launch: ([String]) throws -> Int32) throws -> Int32 {
        let root = try global.git.repositoryRoot()
        // A URL reaches the app whether or not it is already running (launch arguments only reach a new process).
        var url = URLComponents()
        url.scheme = "lfgit"
        url.host = "open"
        url.queryItems = [URLQueryItem(name: "repo", value: root.path)]
        if let file {
            url.queryItems?.append(URLQueryItem(name: "file", value: try Git(directory: root).repositoryRelativePath(of: global.absolutePath(file))))
        }
        guard let link = url.string else {
            throw CLIError("cannot build an lfgit:// link for \(root.path)")
        }
        let status = try launch(["-a", Self.application(environment: environment, executablePath: executablePath), link])
        if status != 0 {
            console.errorLine("error: could not open \(Self.appName); install the app or set LFGIT_APP to its path")
        }
        return status
    }

    static func application(environment: [String: String], executablePath: String) -> String {
        if let override = environment["LFGIT_APP"], !override.isEmpty {
            return override
        }
        // Homebrew: <prefix>/bin/lfgit is a symlink into the Cellar, where LF-Git.app sits next to bin/.
        let binary = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
        let bundled = binary.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("\(appName).app")
        if FileManager.default.fileExists(atPath: bundled.path) {
            return bundled.path
        }
        return appName
    }

    private static func openWithLaunchServices(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
