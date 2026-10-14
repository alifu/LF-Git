import XCTest

/// Drives the Git client features of the real app against real repositories.
final class GitClientUITests: GitUITestCase {
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

    /// The branch menu is a popover that XCUITest cannot see into, so the test drives it with the keyboard:
    /// the search box has focus when it opens, and Return switches to the first match.
    func testSearchTheBranchMenuAndSwitch() throws {
        try write("a.txt", "1\n")
        try git("add", "-A")
        try git("commit", "-q", "-m", "base")
        try git("branch", "feature/menu")
        try git("branch", "release")

        let app = launch(appearance: "light")
        let menu = app.buttons["branch-menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.click()
        Thread.sleep(forTimeInterval: 1) // the popover animates in; the search box takes focus when it is up
        app.typeText("menu")
        app.typeKey(.return, modifierFlags: [])

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
}
