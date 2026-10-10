import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Custom commands")
struct CustomCommandTests {
    @Test("a command runs in the repository with its environment, and its output and status come back")
    func runs() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let log = GitCommandLog()
        let client = GitClient(directory: fixture.directory, log: log)

        let result = try client.run(CustomCommand(name: "probe", command: "ls; echo \"branch=$LFGIT_BRANCH\"; exit 3"), branch: "main")

        #expect(result.status == 3)
        #expect(result.output.contains("a.txt"))
        #expect(result.output.contains("branch=main"))
        #expect(log.entries.last?.status == 3)
    }

    @Test("a command that hangs is stopped by the timeout or by cancelling")
    func stops() throws {
        let fixture = try GitFixture()
        let client = GitClient(directory: fixture.directory)
        let sleeper = CustomCommand(name: "sleep", command: "sleep 30")

        #expect(throws: GitError.timedOut(seconds: 1)) { try client.run(sleeper, timeout: 1) }

        let token = GitCancellation()
        Thread.detachNewThread { Thread.sleep(forTimeInterval: 0.3); token.cancel() }
        #expect(throws: GitError.cancelled) { try client.run(sleeper, cancellation: token) }
    }

    @Test("the configuration is read from JSON; a missing file is empty and a broken one is an error")
    func configuration() throws {
        let sandbox = Sandbox()
        let good = sandbox.write("config.json", #"{"customCommands":[{"name":"Hello","command":"echo hi"}]}"#)
        let bad = sandbox.write("bad.json", "{not json")

        #expect(try CustomCommandConfig.load(from: URL(fileURLWithPath: good)).customCommands.map(\.name) == ["Hello"])
        #expect(try CustomCommandConfig.load(from: sandbox.root.appendingPathComponent("missing.json")).customCommands.isEmpty)
        #expect(throws: GitClientError.self) { try CustomCommandConfig.load(from: URL(fileURLWithPath: bad)) }
    }
}
