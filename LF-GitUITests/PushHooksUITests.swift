import XCTest

/// A push whose `pre-push` hook runs guardrails the way some team repos do: it prints, launches a script with
/// `open -a Terminal`, and runs checks. LF-Git runs that script inside the hook (no Terminal window opens) and shows
/// all of it in its own panel.
final class PushHooksUITests: GitUITestCase {
    private var origin: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        origin = repository.appendingPathExtension("origin")
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        try runGit(["init", "-q", "--bare", "-b", "main"], in: origin)
        try commit("one", files: ["a.txt": "1\n"])
        try git("remote", "add", "origin", origin.path)
        try git("push", "-q", "-u", "origin", "main")
        try commit("two", files: ["a.txt": "2\n"])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: origin)
        try super.tearDownWithError()
    }

    func testPushRunsTheGuardrailTerminalActionInsideTheApp() throws {
        // The runner is sandboxed: hooks it writes are quarantined and git refuses to exec them. The fixture
        // scripts live in the source tree instead, as a real repository's hooks would.
        let hooks = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/guardrail-hooks")
        try git("config", "core.hooksPath", hooks.path)
        let terminal = XCUIApplication(bundleIdentifier: "com.apple.Terminal")
        let terminalWindowsBefore = terminalWindowCount(terminal)
        let app = launch(appearance: "light")

        let push = app.descendants(matching: .any)["push"].firstMatch
        XCTAssertTrue(push.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil { push.isEnabled })
        // The pill is a pop-up button: a click on its middle can open the menu. ⌥⌘P is the Push command itself.
        app.typeKey("p", modifierFlags: [.option, .command])

        let panel = app.descendants(matching: .any)["hook-output"].firstMatch
        let opened = panel.waitForExistence(timeout: 15)
        if !opened {
            let ahead = (try? git("rev-list", "--count", "origin/main..main")) ?? "?"
            add(XCTAttachment(string: "commits not on origin: \(ahead)\n\n\(app.debugDescription)"))
        }
        XCTAssertTrue(opened, "the hook panel opens inside LF-Git")
        let output = panel.staticTexts.containing(NSPredicate(format: "value CONTAINS 'secret scan ok' OR label CONTAINS 'secret scan ok'")).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 20), "stdout and stderr of the hook both reach the panel")
        let action = panel.staticTexts.containing(NSPredicate(
            format: "value CONTAINS 'guardrail-in-terminal' AND value CONTAINS 'finished (exit 0)'")).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 20), "the Terminal action ran inside the hook and its output is shown")
        let passed = panel.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Push passed' OR value BEGINSWITH 'Push passed'")).firstMatch
        XCTAssertTrue(passed.waitForExistence(timeout: 20), "the run ends as passed")
        XCTAssertTrue(waitUntil(timeout: 10) { (try? self.git("rev-list", "--count", "origin/main..main")) == "0" },
                      "the push reached the remote")
        attachScreenshot(app, named: "push-hook-panel")

        XCTAssertEqual(terminalWindowCount(terminal), terminalWindowsBefore, "no Terminal window was opened")
    }

    private func terminalWindowCount(_ terminal: XCUIApplication) -> Int {
        terminal.state == .notRunning ? 0 : terminal.windows.count
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.gitExecutable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments.joined(separator: " "))")
    }
}
