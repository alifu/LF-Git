import Foundation
import LFKit
import LFTestSupport
import Testing

/// Real pushes whose `pre-push` hook launches Terminal the common ways. The hook points the "real" `open` and
/// `osascript` at a recorder, so a test can never open Terminal: a call that is not caught only leaves a note.
@Suite("Hook shims")
struct HookShimsTests {
    private struct Setup {
        let fixture: GitFixture
        let client: GitClient
        let shims: URL
        let recorder: URL

        func file(_ name: String) -> URL { fixture.directory.appendingPathComponent(".git/\(name)") }
        var passedThrough: String { (try? String(contentsOf: file("passed-through"), encoding: .utf8)) ?? "" }
    }

    private func setUp() throws -> Setup {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "one")
        _ = try fixture.addOrigin()
        try fixture.commit("a.txt", "2\n", message: "two")
        let shims = try HookShims.install(in: fixture.directory.appendingPathComponent(".git/shims"))
        let recorder = fixture.directory.appendingPathComponent(".git/recorder")
        let note = fixture.directory.appendingPathComponent(".git/passed-through").path
        try executable(recorder, "#!/bin/sh\nprintf '%s\\n' \"$(basename \"$0\") $*\" >> '\(note)'\n")
        return Setup(fixture: fixture, client: GitClient(directory: fixture.directory), shims: shims, recorder: recorder)
    }

    private func executable(_ url: URL, _ text: String) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// A guardrail script that prints, records that it ran with its arguments, and exits with `status`.
    private func guardrail(_ setup: Setup, named name: String, status: Int = 0) throws -> URL {
        let url = setup.file(name)
        let marker = setup.file("ran").path
        try executable(url, "#!/bin/sh\necho \"guardrail ran: $*\"\nprintf '%s\\n' \"$*\" > '\(marker)'\nexit \(status)\n")
        return url
    }

    /// Installs a `pre-push` hook whose body is `line`, then pushes and returns what the hooks printed.
    private func push(_ setup: Setup, hookLine line: String) throws -> String {
        try executable(setup.file("hooks/pre-push"), """
            #!/bin/sh
            export LFGIT_REAL_OPEN='\(setup.recorder.path)' LFGIT_REAL_OSASCRIPT='\(setup.recorder.path)'
            echo "hook: before"
            \(line)
            echo "hook: after"
            """)
        let output = Collected()
        try setup.client.push(hookShims: setup.shims, onOutput: { output.add($0) })
        return output.text
    }

    private func ran(_ setup: Setup) -> String? {
        try? String(contentsOf: setup.file("ran"), encoding: .utf8).trimmingCharacters(in: .newlines)
    }

    @Test("open -a Terminal runs the script inline, in order, and the hook carries on")
    func openWithTerminal() throws {
        let setup = try setUp()
        let script = try guardrail(setup, named: "guardrails.command")

        let output = try push(setup, hookLine: "open -a Terminal '\(script.path)'")

        #expect(ran(setup) == "")
        #expect(setup.passedThrough.isEmpty)
        let lines = output.split(separator: "\n").map(String.init)
        #expect(lines == ["hook: before", "── Terminal action: \(script.path) ──", "guardrail ran: ",
                          "── finished (exit 0) ──", "hook: after"])
    }

    @Test("terminal apps by name, path and bundle id, with --args and a path with spaces")
    func terminalForms() throws {
        let setup = try setUp()
        let script = try guardrail(setup, named: "my checks.sh")
        let forms = [
            "open -a iTerm '\(script.path)' --args one 'two words'",
            "open -a /System/Applications/Utilities/Terminal.app '\(script.path)' --args one 'two words'",
            "open -b com.apple.Terminal -n '\(script.path)' --args one 'two words'",
        ]
        for form in forms {
            try? FileManager.default.removeItem(at: setup.file("ran"))

            let output = try push(setup, hookLine: form)

            #expect(ran(setup) == "one two words", "\(form)")
            #expect(output.contains("finished (exit 0)"), "\(form)")
            try setup.fixture.git.run(["reset", "-q", "--hard", "HEAD"])
            try setup.fixture.commit("a.txt", "\(form.count)\n", message: "next")
        }
        #expect(setup.passedThrough.isEmpty)
    }

    @Test("a .command file opened on its own runs inline")
    func commandFile() throws {
        let setup = try setUp()
        let script = try guardrail(setup, named: "scan.command")

        _ = try push(setup, hookLine: "open '\(script.path)'")

        #expect(ran(setup) == "")
        #expect(setup.passedThrough.isEmpty)
    }

    @Test("a failing action is reported but does not fail the hook, as with the real open")
    func failingAction() throws {
        let setup = try setUp()
        let script = try guardrail(setup, named: "lint.command", status: 3)

        let output = try push(setup, hookLine: "open -a Terminal '\(script.path)'")

        #expect(output.contains("── finished (exit 3) ──"))
        #expect(output.contains("hook: after"))
    }

    @Test("osascript do script in Terminal and write text in iTerm run inline")
    func osascriptForms() throws {
        let setup = try setUp()
        let marker = setup.file("ran").path
        let forms = [
            #"osascript -e 'tell application "Terminal" to do script "echo \"quoted\" > \#(marker)"'"#,
            #"osascript -e 'tell application "Terminal"' -e 'activate' -e 'do script "echo \"quoted\" > \#(marker)"' -e 'end tell'"#,
            #"osascript -e 'tell application "iTerm2" to tell current session of current window to write text "echo \"quoted\" > \#(marker)"'"#,
        ]
        for form in forms {
            try? FileManager.default.removeItem(at: setup.file("ran"))

            let output = try push(setup, hookLine: form)

            #expect(ran(setup) == "quoted", "\(form)")
            #expect(output.contains("finished (exit 0)"), "\(form)")
            try setup.fixture.commit("a.txt", "\(form.count)\n", message: "next")
        }
        #expect(setup.passedThrough.isEmpty)
    }

    @Test("everything else goes to the real command unchanged")
    func passThrough() throws {
        let setup = try setUp()
        let text = setup.file("notes.txt")
        try "x".write(to: text, atomically: true, encoding: .utf8)

        _ = try push(setup, hookLine: """
            open https://example.com
            open -a Preview '\(text.path)'
            open -a Terminal '\(setup.fixture.directory.path)'
            osascript -e 'display notification "done"'
            osascript -e 'tell application "Terminal" to activate'
            """)

        #expect(ran(setup) == nil)
        #expect(setup.passedThrough.split(separator: "\n") == [
            "recorder https://example.com",
            "recorder -a Preview \(text.path)",
            "recorder -a Terminal \(setup.fixture.directory.path)",
            "recorder -e display notification \"done\"",
            "recorder -e tell application \"Terminal\" to activate",
        ])
    }

    @Test("without shims the hook's PATH is untouched")
    func noShims() throws {
        let setup = try setUp()
        try executable(setup.file("hooks/pre-push"), "#!/bin/sh\necho \"$PATH\"\n")
        let output = Collected()

        try setup.client.push(onOutput: { output.add($0) })

        #expect(!output.text.contains(setup.shims.path))
    }

    @Test("install writes executable scripts and leaves unchanged ones alone")
    func install() throws {
        let sandbox = Sandbox()
        let directory = URL(fileURLWithPath: sandbox.path("shims"))

        try HookShims.install(in: directory)
        let open = directory.appendingPathComponent("open")
        let written = try FileManager.default.attributesOfItem(atPath: open.path)[.modificationDate] as? Date
        try HookShims.install(in: directory)

        #expect(FileManager.default.isExecutableFile(atPath: open.path))
        #expect(FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent("osascript").path))
        #expect(try FileManager.default.attributesOfItem(atPath: open.path)[.modificationDate] as? Date == written)
    }
}

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    var text: String { lock.withLock { value } }
    func add(_ chunk: String) { lock.withLock { value += chunk } }
}
