import Foundation

/// The settings of the user's terminal that git depends on, which an app started from the Dock does not get:
/// a `PATH` with Homebrew tools (`gh`, `git-credential-manager`), the SSH agent, and tokens exported in `.zshrc`.
public enum LoginEnvironment {
    public static let beginMarker = "__LFGIT_ENV_BEGIN__"
    public static let endMarker = "__LFGIT_ENV_END__"

    /// Only these are taken. Variables such as `GIT_DIR` or `GIT_INDEX_FILE` would point git at the wrong
    /// repository, and everything else is none of git's business.
    private static let allowedNames: Set<String> = [
        "PATH", "SSH_AUTH_SOCK", "SSH_ASKPASS", "SSH_ASKPASS_REQUIRE", "GIT_ASKPASS", "GIT_SSH", "GIT_SSH_COMMAND",
        "GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN", "GH_HOST",
        "GITLAB_TOKEN", "GITLAB_ACCESS_TOKEN", "GLAB_TOKEN", "BITBUCKET_TOKEN",
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "all_proxy", "no_proxy",
    ]
    private static let allowedPrefixes = ["GCM_"]

    /// Asks the user's login shell for its environment (with a time limit: a slow `.zshrc` must not stall the app).
    /// Returns nothing when the shell cannot be run, times out or prints nothing recognizable.
    public static func capture(shell: String? = nil, timeout: TimeInterval = 8) -> [String: String] {
        let shell = shell ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("lfgit-env-\(UUID().uuidString).out")
        guard FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              let handle = try? FileHandle(forWritingTo: output) else { return [:] }
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: output)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -l reads the login files and -i the interactive ones (.zshrc), where most people export PATH and tokens.
        process.arguments = ["-l", "-i", "-c", "printf '%s' '\(beginMarker)'; /usr/bin/env -0; printf '%s' '\(endMarker)'"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [:] }
        let pid = process.processIdentifier
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { if process.isRunning { kill(pid, SIGKILL) } }
        timer.resume()
        process.waitUntilExit()
        timer.cancel()
        guard process.terminationReason == .exit, let data = try? Data(contentsOf: output) else { return [:] }
        return parse(data)
    }

    private static func parse(_ data: Data) -> [String: String] {
        let text = String(decoding: data, as: UTF8.self)
        guard let begin = text.range(of: beginMarker), let end = text.range(of: endMarker, range: begin.upperBound..<text.endIndex) else {
            return [:]
        }
        var result: [String: String] = [:]
        for entry in text[begin.upperBound..<end.lowerBound].split(separator: "\0") {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            let name = String(entry[..<equals])
            guard isAllowed(name) else { continue }
            result[name] = String(entry[entry.index(after: equals)...])
        }
        return result
    }

    private static func isAllowed(_ name: String) -> Bool {
        allowedNames.contains(name) || allowedPrefixes.contains { name.hasPrefix($0) }
    }
}

/// The captured terminal settings that every git command runs with.
public final class GitEnvironment: @unchecked Sendable {
    public static let shared = GitEnvironment()

    private let lock = NSLock()
    private var values: [String: String] = [:]

    public var current: [String: String] {
        lock.withLock { values }
    }

    public func set(_ newValues: [String: String]) {
        lock.withLock { values = newValues }
    }
}

extension GitEnvironment {
    /// Which `git` the app runs and its version, for the settings screen.
    public func gitLocation() -> (path: String, version: String)? {
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["git"]
        which.environment = ProcessInfo.processInfo.environment.merging(current) { _, new in new }
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = FileHandle.nullDevice
        guard (try? which.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        which.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty,
              let version = try? Git(directory: FileManager.default.temporaryDirectory).run(["--version"]).text else { return nil }
        return (path, version)
    }
}
