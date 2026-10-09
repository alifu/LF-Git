import XCTest

/// Drives the Git client features of the real app against real repositories.
final class GitClientUITests: XCTestCase {
    private var repository: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        repository = FileManager.default.temporaryDirectory.appendingPathComponent("lfgit-ui-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main")
        try git("config", "user.name", "UI Test")
        try git("config", "user.email", "ui@example.com")
        try git("config", "commit.gpgsign", "false")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repository)
    }

    private static let original = (1...40).map { "line \($0)" }.joined(separator: "\n") + "\n"
    private static let edited = original
        .replacingOccurrences(of: "line 3\n", with: "line 3 changed\n")
        .replacingOccurrences(of: "line 38\n", with: "line 38 changed\n")

    func testStageOneHunkAndCommit() throws {
        try write("f.txt", Self.original)
        try git("add", "-A")
        try git("commit", "-q", "-m", "base")
        try write("f.txt", Self.edited)
        try write("new.txt", "brand new\n")

        let app = launch(appearance: "light")
        let row = app.descendants(matching: .any)["change-unstaged-f.txt"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the modified file is listed")
        row.click()
        let firstHunk = app.buttons["hunk-action-5"]
        XCTAssertTrue(firstHunk.waitForExistence(timeout: 10), "the diff shows a button on the first hunk")
        attachScreenshot(app, named: "changes-light")

        firstHunk.click() // stage only the first hunk
        XCTAssertTrue(app.descendants(matching: .any)["change-staged-f.txt"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["change-unstaged-f.txt"].exists, "the second hunk is still unstaged")

        app.buttons["stage-new.txt"].click()
        XCTAssertTrue(app.descendants(matching: .any)["change-staged-new.txt"].waitForExistence(timeout: 10))

        let message = app.textViews["commit-message"]
        message.click()
        message.typeText("Change line 3 and add a file")
        attachScreenshot(app, named: "ready-to-commit")
        app.buttons["commit-button"].click()

        XCTAssertTrue(waitUntil { (try? self.git("log", "-1", "--format=%s")) == "Change line 3 and add a file" })
        XCTAssertEqual(try git("show", "HEAD:new.txt"), "brand new")
        let committed = try git("show", "HEAD:f.txt")
        XCTAssertTrue(committed.contains("line 3 changed"))
        XCTAssertFalse(committed.contains("line 38 changed"), "the unstaged hunk was not committed")
        XCTAssertEqual(try git("status", "--porcelain"), "M f.txt", "the second hunk is still a pending edit")
        XCTAssertTrue(app.descendants(matching: .any)["change-unstaged-f.txt"].waitForExistence(timeout: 10))
    }

    func testHistoryShowsTheGraphAndCommitDetails() throws {
        try write("a.txt", "1\n")
        try git("add", "-A")
        try git("commit", "-q", "-m", "first commit")
        try git("checkout", "-q", "-b", "feature")
        try write("b.txt", "feature work\n")
        try git("add", "-A")
        try git("commit", "-q", "-m", "work on the feature")
        try git("checkout", "-q", "main")
        try write("c.txt", "main work\n")
        try git("add", "-A")
        try git("commit", "-q", "-m", "work on main")
        try git("merge", "-q", "--no-ff", "-m", "merge the feature", "feature")

        let app = launch(appearance: "dark")
        showSection("History", in: app)

        let merge = app.descendants(matching: .any)["commit-merge the feature"]
        XCTAssertTrue(merge.waitForExistence(timeout: 10), "the history lists the merge commit")
        XCTAssertTrue(app.descendants(matching: .any)["commit-first commit"].exists)
        app.descendants(matching: .any)["commit-work on the feature"].click()
        XCTAssertTrue(app.descendants(matching: .any)["commit-file-b.txt"].waitForExistence(timeout: 10), "the commit's files are listed")
        attachScreenshot(app, named: "history-dark")
    }

    func testCreateABranchFromTheMenu() throws {
        try write("a.txt", "1\n")
        try git("add", "-A")
        try git("commit", "-q", "-m", "base")

        let app = launch(appearance: "light")
        let menu = app.menuButtons["branch-menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.click()
        app.menuItems["New Branch…"].click()
        let field = app.sheets.textFields.firstMatch // a SwiftUI alert with a text field is a sheet on macOS
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("feature/menu")
        app.sheets.buttons["Create"].click()

        XCTAssertTrue(waitUntil { (try? self.git("branch", "--show-current")) == "feature/menu" })
    }

    func testFinishAConflictedMergeWithContinue() throws {
        try write("a.txt", "a\nb\nc\n")
        try git("add", "-A")
        try git("commit", "-q", "-m", "base")
        try git("checkout", "-q", "-b", "feature")
        try write("a.txt", "a\nb-feature\nc\n")
        try git("commit", "-q", "-am", "feature change")
        try git("checkout", "-q", "main")
        try write("a.txt", "a\nb-main\nc\n")
        try git("commit", "-q", "-am", "main change")
        try git("merge", "feature", allowFailure: true)

        let app = launch(appearance: "light")
        XCTAssertTrue(app.staticTexts["Merge in progress"].waitForExistence(timeout: 10), "the banner says a merge is waiting")
        XCTAssertFalse(app.buttons["operation-continue"].isEnabled, "Continue waits for the conflicts")
        let accept = app.buttons["accept-incoming-0"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10))
        accept.click()
        app.buttons["save"].click() // saving a fully resolved file stages it

        XCTAssertTrue(waitUntil { app.buttons["operation-continue"].isEnabled }, "Continue is available once nothing conflicts")
        attachScreenshot(app, named: "merge-ready-to-continue")
        app.buttons["operation-continue"].click()

        XCTAssertTrue(waitUntil(timeout: 10) { (try? self.git("rev-list", "--merges", "--count", "HEAD")) == "1" })
        XCTAssertEqual(try git("show", "HEAD:a.txt"), "a\nb-feature\nc")
        XCTAssertFalse(app.staticTexts["Merge in progress"].waitForExistence(timeout: 3), "the banner goes away")
    }

    // MARK: - Helpers

    private func launch(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--repo", repository.path, "-appearance", appearance]
        app.launch()
        return app
    }

    private func showSection(_ title: String, in app: XCUIApplication) {
        let picker = app.descendants(matching: .any)["section-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let button = picker.radioButtons[title].firstMatch.exists ? picker.radioButtons[title].firstMatch : picker.buttons[title].firstMatch
        button.click()
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitUntil(timeout: TimeInterval = 8, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    private func write(_ path: String, _ text: String) throws {
        let url = repository.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The UI test runner is sandboxed, and /usr/bin/git is an xcrun shim that refuses to run there.
    private static let gitExecutable: String = {
        let candidates = [
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/git"
    }()

    @discardableResult
    private func git(_ arguments: String..., allowFailure: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.gitExecutable)
        process.arguments = arguments
        process.currentDirectoryURL = repository
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_OPTIONAL_LOCKS": "0"]) { _, new in new }
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        if process.terminationStatus != 0 && !allowFailure {
            throw NSError(domain: "git \(arguments.joined(separator: " "))", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
