import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Git hooks")
struct GitHooksTests {
    private func install(_ name: String, script: String, in fixture: GitFixture, executable: Bool = true) throws {
        let url = fixture.directory.appendingPathComponent(".git/hooks/\(name)")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
    }

    private func pushReady() throws -> (GitFixture, GitClient) {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "one")
        _ = try fixture.addOrigin()
        return (fixture, GitClient(directory: fixture.directory))
    }

    @Test("hooks are listed, samples are ignored and a non-executable hook is flagged")
    func listing() throws {
        let fixture = try GitFixture()
        try install("pre-push", script: "#!/bin/sh\n", in: fixture)
        try install("commit-msg", script: "#!/bin/sh\n", in: fixture, executable: false)
        try install("pre-commit.sample", script: "#!/bin/sh\n", in: fixture)
        let client = GitClient(directory: fixture.directory)

        let hooks = try client.hooks()

        #expect(hooks.map(\.name) == ["commit-msg", "pre-push"])
        #expect(hooks.map(\.isExecutable) == [false, true])
        #expect(client.hasHook(named: "pre-push"))
        #expect(!client.hasHook(named: "commit-msg"))
    }

    @Test("core.hooksPath is honoured")
    func customHooksPath() throws {
        let fixture = try GitFixture()
        let directory = fixture.directory.appendingPathComponent(".husky")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("pre-push")
        try "#!/bin/sh\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try fixture.git.run(["config", "core.hooksPath", ".husky"])

        #expect(try GitClient(directory: fixture.directory).hooks().map(\.name) == ["pre-push"])
    }

    @Test("a pre-push hook runs and its output is delivered")
    func pushRunsHook() throws {
        let (fixture, client) = try pushReady()
        try install("pre-push", script: "#!/bin/sh\necho guardrail-ran\ntouch \"$(git rev-parse --show-toplevel)/marker\"\n", in: fixture)
        let collected = Collected()

        try client.push(onOutput: { collected.add($0) })

        #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("marker").path))
        #expect(collected.text.contains("guardrail-ran"))
    }

    @Test("push without hooks skips the pre-push hook")
    func pushSkipsHook() throws {
        let (fixture, client) = try pushReady()
        try install("pre-push", script: "#!/bin/sh\ntouch \"$(git rev-parse --show-toplevel)/marker\"\nexit 1\n", in: fixture)

        try client.push(runHooks: false)

        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("marker").path))
    }

    @Test("a failing pre-push hook rejects the push and says why")
    func failingHook() throws {
        let (fixture, client) = try pushReady()
        try install("pre-push", script: "#!/bin/sh\necho 'lint failed' >&2\nexit 1\n", in: fixture)

        #expect(throws: GitError.self) { try client.push() }
    }

    @Test("commit hook output is delivered")
    func commitHookOutput() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "one")
        try install("pre-commit", script: "#!/bin/sh\necho checking\n", in: fixture)
        let client = GitClient(directory: fixture.directory)
        fixture.sandbox.write("b.txt", "x\n")
        try client.stage(["b.txt"])
        let collected = Collected()

        try client.commit(message: "two", onOutput: { collected.add($0) })

        #expect(collected.text.contains("checking"))
    }
}

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    var text: String { lock.withLock { value } }
    func add(_ chunk: String) { lock.withLock { value += chunk } }
}
