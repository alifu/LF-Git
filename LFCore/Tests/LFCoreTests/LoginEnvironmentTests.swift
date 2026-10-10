import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Terminal environment")
struct LoginEnvironmentTests {
    /// A stand-in for the user's shell: prints what a real one would, ignoring its arguments.
    private func fakeShell(_ body: String, in sandbox: Sandbox) throws -> String {
        let path = sandbox.path("fake-shell")
        try "#!/bin/sh\n\(body)\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    private static let begin = LoginEnvironment.beginMarker
    private static let end = LoginEnvironment.endMarker

    @Test("only the variables git needs come back, and noise around them is ignored")
    func filters() throws {
        let sandbox = Sandbox()
        let shell = try fakeShell("""
            echo 'Welcome to my fancy prompt'
            printf '%s' '\(Self.begin)'
            printf 'PATH=/opt/homebrew/bin:/usr/bin\\0SSH_AUTH_SOCK=/tmp/agent.sock\\0GITHUB_TOKEN=ghp_example\\0GIT_DIR=/etc\\0GIT_WORK_TREE=/x\\0HOME=/nobody\\0EDITOR=vim\\0https_proxy=http://proxy:3128\\0GCM_CREDENTIAL_STORE=keychain\\0'
            printf '%s' '\(Self.end)'
            echo 'bye'
            """, in: sandbox)

        let captured = LoginEnvironment.capture(shell: shell, timeout: 10)

        #expect(captured["PATH"] == "/opt/homebrew/bin:/usr/bin")
        #expect(captured["SSH_AUTH_SOCK"] == "/tmp/agent.sock")
        #expect(captured["GITHUB_TOKEN"] == "ghp_example")
        #expect(captured["https_proxy"] == "http://proxy:3128")
        #expect(captured["GCM_CREDENTIAL_STORE"] == "keychain")
        #expect(captured["GIT_DIR"] == nil, "variables that would point git at another repository are never taken")
        #expect(captured["GIT_WORK_TREE"] == nil)
        #expect(captured["HOME"] == nil)
        #expect(captured["EDITOR"] == nil)
    }

    @Test("a value with equals signs and spaces stays whole")
    func values() throws {
        let sandbox = Sandbox()
        let shell = try fakeShell("""
            printf '%s' '\(Self.begin)'
            printf 'GIT_SSH_COMMAND=ssh -o IdentityAgent=/a b/agent -i key=1\\0'
            printf '%s' '\(Self.end)'
            """, in: sandbox)

        #expect(LoginEnvironment.capture(shell: shell, timeout: 10)["GIT_SSH_COMMAND"] == "ssh -o IdentityAgent=/a b/agent -i key=1")
    }

    @Test("a shell that hangs is stopped and gives nothing")
    func timesOut() throws {
        let sandbox = Sandbox()
        let shell = try fakeShell("sleep 30", in: sandbox)
        let started = Date()

        #expect(LoginEnvironment.capture(shell: shell, timeout: 1).isEmpty)
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test("a missing shell, or one that prints no markers, gives nothing")
    func failures() throws {
        let sandbox = Sandbox()
        #expect(LoginEnvironment.capture(shell: "/no/such/shell", timeout: 5).isEmpty)
        #expect(LoginEnvironment.capture(shell: try fakeShell("echo hello", in: sandbox), timeout: 5).isEmpty)
    }

    @Test("git runs with the captured environment, under the app's own settings")
    func gitUsesIt() throws {
        let sandbox = Sandbox()
        GitEnvironment.shared.set(["GH_HOST": "example.test", "GIT_TERMINAL_PROMPT": "1"])
        defer { GitEnvironment.shared.set([:]) }
        let git = Git(directory: sandbox.root)

        let result = try git.run(["-c", "alias.show-env=!echo $GH_HOST $GIT_TERMINAL_PROMPT", "show-env"])

        #expect(result.text == "example.test 0", "the app always keeps git from prompting")
    }

    @Test("a failed login says what to do about it")
    func hint() {
        let error = GitError.failed(arguments: ["fetch"], status: 128,
                                    stderr: "fatal: could not read Username for 'https://git.example.com': terminal prompts disabled")
        #expect(error.description.contains("access token"))
        let other = GitError.failed(arguments: ["status"], status: 1, stderr: "fatal: nope")
        #expect(!other.description.contains("access token"))
    }
}
