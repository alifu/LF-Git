import Foundation
@testable import LFGitCLI
import LFKit
import LFTestSupport
import Testing

@Suite("lfgit open")
struct OpenCommandTests {
    private final class Recorder: @unchecked Sendable {
        var arguments: [String] = []
    }

    private func run(_ arguments: [String], environment: [String: String] = [:], executable: String = "/usr/local/bin/lfgit")
        throws -> (code: Int32, launched: [String], console: BufferConsole) {
        let recorder = Recorder()
        let console = BufferConsole()
        let code = try OpenCommand.parse(arguments).execute(
            console: console, environment: environment, executablePath: executable
        ) { recorder.arguments = $0; return 0 }
        return (code, recorder.arguments, console)
    }

    @Test("opens the repository root in the app")
    func opensRepository() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("sub/a.txt")])

        let result = try run(["-C", fixture.sandbox.path("sub")])

        let root = try fixture.git.repositoryRoot().path
        #expect(result.code == 0)
        #expect(result.launched.count == 3)
        #expect(Array(result.launched.prefix(2)) == ["-a", "LF-Git"])
        let url = try #require(URLComponents(string: result.launched[2]))
        #expect(url.scheme == "lfgit")
        #expect(url.queryItems?.first { $0.name == "repo" }?.value == root)
    }

    @Test("a file argument is passed relative to the repository root")
    func opensFile() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("sub/a.txt")])

        let result = try run(["-C", fixture.sandbox.path("sub"), "a.txt"])

        let link = try #require(result.launched.last)
        let url = try #require(URLComponents(string: link))
        #expect(url.queryItems?.first { $0.name == "file" }?.value == "sub/a.txt")
    }

    @Test("LFGIT_APP points at a specific app bundle")
    func environmentOverride() throws {
        let fixture = try GitFixture()

        let result = try run(["-C", fixture.path], environment: ["LFGIT_APP": "/opt/LF-Git.app"])

        #expect(Array(result.launched.prefix(2)) == ["-a", "/opt/LF-Git.app"])
    }

    @Test("an app bundle next to the installed binary is preferred (Homebrew layout)")
    func bundledApp() throws {
        let fixture = try GitFixture()
        let prefix = Sandbox()
        try FileManager.default.createDirectory(atPath: prefix.path("LF-Git.app/Contents"), withIntermediateDirectories: true)
        let binary = prefix.write("bin/lfgit", "")

        let result = try run(["-C", fixture.path], executable: binary)

        #expect(Array(result.launched.prefix(2)) == ["-a", prefix.path("LF-Git.app")])
    }

    @Test("outside a repository nothing is launched")
    func notARepository() throws {
        let box = Sandbox()

        #expect(throws: GitError.self) { _ = try run(["-C", box.root.path]) }
    }
}
