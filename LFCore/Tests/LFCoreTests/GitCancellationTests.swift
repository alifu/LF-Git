import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Git cancellation, timeout and command log")
struct GitCancellationTests {
    private static let sleeper = ["-c", "alias.nap=!sleep 30", "nap"]

    @Test("cancelling stops a running command quickly")
    func cancelStops() throws {
        let fixture = try GitFixture()
        let token = GitCancellation()
        Thread.detachNewThread { Thread.sleep(forTimeInterval: 0.3); token.cancel() }
        let started = Date()

        #expect(throws: GitError.cancelled) {
            try fixture.git.run(Self.sleeper, cancellation: token)
        }

        #expect(Date().timeIntervalSince(started) < 25) // the command would sleep for 30 s; the margin covers a loaded machine
    }

    @Test("a token that is already cancelled never starts git")
    func alreadyCancelled() throws {
        let fixture = try GitFixture()
        let token = GitCancellation()
        token.cancel()

        #expect(throws: GitError.cancelled) {
            try fixture.git.run(["status"], cancellation: token)
        }
    }

    @Test("a command that runs too long is stopped with a timeout")
    func timeout() throws {
        let fixture = try GitFixture()
        let started = Date()

        #expect(throws: GitError.timedOut(seconds: 1)) {
            try fixture.git.run(Self.sleeper, timeout: 1)
        }

        #expect(Date().timeIntervalSince(started) < 25) // the command would sleep for 30 s; the margin covers a loaded machine
    }

    @Test("a fast command is not affected by its timeout or an unused token")
    func fastCommand() throws {
        let fixture = try GitFixture()

        let result = try fixture.git.run(["rev-parse", "--git-dir"], timeout: 30, cancellation: GitCancellation())

        #expect(result.text == ".git")
    }

    @Test("fetch reports a timeout instead of hanging")
    func fetchTimeout() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        try fixture.git.run(["config", "core.sshCommand", "sleep 30 #"])
        try fixture.git.run(["remote", "add", "origin", "ssh://example.invalid/repo.git"])
        let client = GitClient(directory: fixture.directory)

        #expect(throws: GitError.timedOut(seconds: 1)) {
            try client.fetch(timeout: 1)
        }
    }

    @Test("the command log records what ran, newest last, and stays bounded")
    func commandLog() throws {
        let fixture = try GitFixture()
        let log = GitCommandLog(capacity: 3)
        let git = Git(directory: fixture.directory, log: log)

        try git.run(["rev-parse", "--git-dir"])
        try git.run(["status", "--short"])
        _ = try? git.run(["no-such-command"])
        try git.run(["branch", "--show-current"])

        let entries = log.entries
        #expect(entries.count == 3)
        #expect(entries.first?.command == "git status --short")
        let failed = entries.first { $0.command == "git no-such-command" }
        #expect(failed?.status != 0)
        #expect(entries.last?.command == "git branch --show-current")
    }

    @Test("clients created with a log share it with their helpers")
    func clientLog() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let log = GitCommandLog()
        let client = GitClient(directory: fixture.directory, log: log)

        _ = try client.status()

        #expect(log.entries.contains { $0.command.hasPrefix("git status") })
    }
}
