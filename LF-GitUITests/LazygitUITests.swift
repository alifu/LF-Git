import XCTest

/// The lazygit-style features: stash, palette, history rewriting, cancel, line staging, command log.
final class LazygitUITests: GitUITestCase {
    private func item(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func commitHistory(_ subjects: String...) throws {
        for subject in subjects {
            try write("\(subject).txt", "\(subject)\n")
            try git("add", "-A")
            try git("commit", "-q", "-m", subject)
        }
    }

    func testStashFromTheSectionAndApplyFromTheContextMenu() throws {
        try commitHistory("base")
        try write("base.txt", "edited\n")
        let app = launch(appearance: "light")
        showSection("Stash", in: app)

        let menu = app.menuButtons["stash-menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.click()
        app.menuItems["Stash All Changes…"].click()
        let field = app.sheets.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("my work")
        app.sheets.buttons["Stash"].click()

        XCTAssertTrue(waitUntil { (try? self.git("stash", "list")) ?? "" != "" })
        XCTAssertEqual(try git("status", "--porcelain"), "")
        let row = item(app, "stash-my work")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.rightClick()
        app.menuItems["Apply"].click()
        XCTAssertTrue(waitUntil { (try? self.git("status", "--porcelain")) == "M base.txt" })
        attachScreenshot(app, named: "stash")
    }

    func testCommandPaletteStagesEverything() throws {
        try commitHistory("base")
        try write("base.txt", "edited\n")
        try write("new.txt", "new\n")
        let app = launch(appearance: "dark")
        XCTAssertTrue(item(app, "change-unstaged-base.txt").waitForExistence(timeout: 10))

        app.buttons["palette-button"].click()
        let field = app.textFields["palette-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("stage all")
        attachScreenshot(app, named: "palette")
        field.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(waitUntil { (try? self.git("status", "--porcelain")) == "M  base.txt\nA  new.txt" })
    }

    func testDropACommitFromTheHistoryContextMenu() throws {
        try commitHistory("one", "two", "three")
        let app = launch(appearance: "light")
        showSection("History", in: app)

        let row = item(app, "commit-two")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.rightClick()
        app.menuItems["Drop…"].click()
        app.sheets.buttons["Drop Commit"].click()

        XCTAssertTrue(waitUntil(timeout: 12) { (try? self.git("log", "--format=%s")) == "three\none" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.appendingPathComponent("two.txt").path))
    }

    func testBranchContextMenuMergesIntoTheCurrentBranch() throws {
        try commitHistory("base")
        try git("checkout", "-q", "-b", "topic")
        try commitHistory("topic-work")
        try git("checkout", "-q", "main")
        let app = launch(appearance: "light")
        showSection("Branches", in: app)

        let row = item(app, "branch-topic")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.rightClick()
        app.menuItems["Merge into Current Branch"].click()
        app.menuItems["Merge"].firstMatch.click()

        XCTAssertTrue(waitUntil { (try? self.git("log", "-1", "--format=%s")) == "topic-work" })
    }

    func testCancellingARunningFetch() throws {
        try commitHistory("base")
        try git("config", "core.sshCommand", "sleep 60 #")
        try git("remote", "add", "origin", "ssh://example.invalid/repo.git")
        let app = launch(appearance: "light")

        let fetch = app.buttons["fetch"]
        XCTAssertTrue(fetch.waitForExistence(timeout: 10))
        fetch.click()
        let cancel = app.buttons["cancel-operation"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "a running fetch can be cancelled")
        attachScreenshot(app, named: "fetching")
        cancel.click()

        XCTAssertTrue(waitUntil(timeout: 10) { !cancel.exists }, "the toolbar is idle again")
        XCTAssertFalse(app.alerts.firstMatch.exists, "cancelling is not an error")
    }

    func testCommandLogShowsTheGitCommands() throws {
        try commitHistory("base")
        try write("base.txt", "edited\n")
        let app = launch(appearance: "light")
        let stage = app.buttons["stage-base.txt"]
        XCTAssertTrue(stage.waitForExistence(timeout: 10))
        stage.click()
        XCTAssertTrue(item(app, "change-staged-base.txt").waitForExistence(timeout: 10))

        app.typeKey("l", modifierFlags: [.command, .shift])

        let log = item(app, "command-log")
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["git add -- base.txt"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "command-log")
    }

    func testReflogUndoBringsTheCommitBack() throws {
        try commitHistory("one", "two")
        let app = launch(appearance: "light")
        showSection("Reflog", in: app)

        let undo = app.buttons["reflog-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        undo.click()

        XCTAssertTrue(waitUntil { (try? self.git("log", "--format=%s")) == "one" })
        undo.click() // the same call redoes it
        XCTAssertTrue(waitUntil { (try? self.git("log", "--format=%s")) == "two\none" })
    }

    func testStageTwoLinesOfAHunk() throws {
        let original = (1...12).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try write("f.txt", original)
        try git("add", "-A")
        try git("commit", "-q", "-m", "base")
        try write("f.txt", original.replacingOccurrences(of: "line 3\n", with: "line 3 changed\n")
            .replacingOccurrences(of: "line 5\n", with: "line 5 changed\n"))
        let app = launch(appearance: "light")

        item(app, "change-unstaged-f.txt").click()
        let diff = app.tables["diff-view"]
        XCTAssertTrue(diff.waitForExistence(timeout: 10))
        // Rows: 4 header lines, the @@ line, then context. Pick the "-line 3" and "+line 3 changed" rows.
        let rows = diff.tableRows
        XCTAssertTrue(rows.element(boundBy: 8).waitForExistence(timeout: 5))
        let removed = diff.staticTexts.matching(NSPredicate(format: "value == %@", "-line 3")).firstMatch
        let added = diff.staticTexts.matching(NSPredicate(format: "value == %@", "+line 3 changed")).firstMatch
        XCTAssertTrue(removed.exists && added.exists, "the diff rows can be found")
        removed.click()
        app.typeKey(.downArrow, modifierFlags: .shift) // the "+" row follows the "-" row

        let stageLines = app.buttons["stage-lines"]
        XCTAssertTrue(stageLines.waitForExistence(timeout: 5))
        attachScreenshot(app, named: "line-selection")
        stageLines.click()

        XCTAssertTrue(waitUntil { (try? self.git("diff", "--cached", "-U0")) ?? "" != "" })
        let staged = try git("diff", "--cached", "-U0")
        XCTAssertTrue(staged.contains("+line 3 changed"))
        XCTAssertFalse(staged.contains("line 5"))
    }
}
