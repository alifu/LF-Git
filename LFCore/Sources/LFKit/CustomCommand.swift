import Foundation

/// A command the user defined in `~/.config/lfgit/config.json`:
///
///     { "customCommands": [ { "name": "Prune merged branches", "command": "git branch --merged | grep -v '\\*' | xargs git branch -d" } ] }
///
/// It runs in the repository through `/bin/sh -c`, with `LFGIT_REPO` and `LFGIT_BRANCH` set. The file belongs
/// to the user, who is the only one able to add commands to it.
public struct CustomCommand: Codable, Sendable, Equatable, Identifiable {
    public let name: String
    public let command: String
    public let description: String?

    public var id: String { name }

    public init(name: String, command: String, description: String? = nil) {
        self.name = name
        self.command = command
        self.description = description
    }
}

public struct CustomCommandConfig: Codable, Sendable, Equatable {
    public var customCommands: [CustomCommand] = []

    public static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/lfgit/config.json")

    /// The user's commands; a missing file means none, a broken file is an error worth showing.
    public static func load(from url: URL = defaultURL) throws -> CustomCommandConfig {
        guard let data = try? Data(contentsOf: url) else { return CustomCommandConfig() }
        do {
            return try JSONDecoder().decode(CustomCommandConfig.self, from: data)
        } catch {
            throw GitClientError.unsupported("\(url.path) is not valid: \(error.localizedDescription)")
        }
    }
}

public struct CustomCommandResult: Sendable, Equatable {
    public let status: Int32
    /// Standard output and error together, cut to the last part when very long.
    public let output: String
}

extension GitClient {
    private static let maxOutputBytes = 64_000

    /// Runs a user-defined command in the repository.
    public func run(_ custom: CustomCommand, timeout: TimeInterval? = 600, cancellation: GitCancellation? = nil,
                    branch: String? = nil) throws -> CustomCommandResult {
        let started = Date()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("lfgit-custom-\(UUID().uuidString).out")
        guard FileManager.default.createFile(atPath: output.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: output) else {
            throw GitError.launchFailed("cannot create a temporary file for the command's output")
        }
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: output)
        }
        if cancellation?.isCancelled == true { throw GitError.cancelled }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", custom.command]
        process.currentDirectoryURL = git.directory
        process.environment = ProcessInfo.processInfo.environment.merging(GitEnvironment.shared.current) { _, new in new }.merging([
            "LFGIT_REPO": git.directory.path, "LFGIT_BRANCH": branch ?? "", "GIT_TERMINAL_PROMPT": "0",
        ]) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        let stopper = ProcessStopper(process: process, gracePeriod: 2)
        do { try process.run() } catch { throw GitError.launchFailed(error.localizedDescription) }
        let key = cancellation?.onCancel { stopper.stop(.cancelled) }
        let timer = timeout.map { seconds in Watchdog(after: seconds) { stopper.stop(.timedOut(seconds: seconds)) } }
        process.waitUntilExit()
        timer?.cancel()
        if let key { cancellation?.remove(key) }
        let stopped = stopper.reason != nil && (process.terminationReason == .uncaughtSignal || process.terminationStatus != 0)
        let status = stopped ? -1 : process.terminationStatus
        git.log?.record(command: custom.command, status: status, duration: Date().timeIntervalSince(started))
        if stopped, let reason = stopper.reason { throw reason }

        let data = (try? Data(contentsOf: output)) ?? Data()
        let tail = data.suffix(Self.maxOutputBytes)
        return CustomCommandResult(status: process.terminationStatus,
                                   output: String(decoding: tail, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
