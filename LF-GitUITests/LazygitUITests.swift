import XCTest

/// The lazygit-style features: stash, palette, history rewriting, cancel, line staging, command log.
final class LazygitUITests: GitUITestCase {
    private func item(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// A folder row. The list folds the row's label and buttons into one element whose identifier lists them all.
    private func folderRow(_ app: XCUIApplication, _ side: String, _ folder: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "folder-\(side)-\(folder)")).firstMatch
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
        app.menuItems["Merge into Current Branch…"].click()
        app.menuItems["Merge"].firstMatch.click()
        // It says what it is about to do and waits for a yes.
        XCTAssertTrue(app.sheets.staticTexts["Merge ‘topic’ into ‘main’?"].waitForExistence(timeout: 5))
        XCTAssertEqual(try git("log", "-1", "--format=%s"), "base", "nothing happened before the yes")
        app.sheets.buttons["Merge"].click()

        XCTAssertTrue(waitUntil { (try? self.git("log", "-1", "--format=%s")) == "topic-work" })
    }

    func testDoubleClickChecksOutABranch() throws {
        try commitHistory("base")
        try git("branch", "topic")
        let app = launch(appearance: "light")
        showSection("Branches", in: app)

        let row = item(app, "branch-topic")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.doubleClick()

        XCTAssertTrue(waitUntil { (try? self.git("branch", "--show-current")) == "topic" })
    }

    func testBranchSearchNarrowsTheList() throws {
        try commitHistory("base")
        try git("branch", "alpha")
        try git("branch", "beta")
        let app = launch(appearance: "light")
        showSection("Branches", in: app)
        XCTAssertTrue(item(app, "branch-alpha").waitForExistence(timeout: 10))

        let search = app.textFields["branch-search"]
        search.click()
        search.typeText("bet")

        XCTAssertTrue(item(app, "branch-beta").waitForExistence(timeout: 5))
        XCTAssertFalse(item(app, "branch-alpha").exists)
    }

    func testSpaceStagesAndUnstagesTheSelectedFile() throws {
        try commitHistory("base")
        try write("base.txt", "edited\n")
        let app = launch(appearance: "light")
        let row = item(app, "change-unstaged-base.txt")
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        row.click()
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(item(app, "change-staged-base.txt").waitForExistence(timeout: 10), "space stages the file")

        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(item(app, "change-unstaged-base.txt").waitForExistence(timeout: 10), "space unstages it again")
    }

    func testSpaceOnAFolderStagesEveryFileInIt() throws {
        try commitHistory("base")
        try write("src/a.txt", "a\n")
        try write("src/b.txt", "b\n")
        try git("add", "-A")
        try git("commit", "-q", "-m", "src")
        try write("src/a.txt", "a2\n")
        try write("src/b.txt", "b2\n")
        let app = launch(appearance: "light")
                let folder = folderRow(app, "unstaged", "src/")
        XCTAssertTrue(folder.waitForExistence(timeout: 10))

        folder.click()
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(waitUntil { (try? self.git("diff", "--cached", "--name-only")) == "src/a.txt\nsrc/b.txt" },
                      "space on a folder stages all of its files")
    }

    func testDiscardAFolderThrowsAwayEveryChangeInIt() throws {
        try commitHistory("base")
        try write("src/a.txt", "a\n")
        try write("src/b.txt", "b\n")
        try git("add", "-A")
        try git("commit", "-q", "-m", "src")
        try write("src/a.txt", "a2\n")
        try write("src/b.txt", "b2\n")
        let app = launch(appearance: "light")
        let folder = folderRow(app, "unstaged", "src/")
        XCTAssertTrue(folder.waitForExistence(timeout: 10))

        folder.rightClick()
        app.menuItems["Discard Changes in Folder…"].firstMatch.click()
        app.sheets.buttons["Discard Changes"].firstMatch.click()
        XCTAssertTrue(waitUntil { (try? self.git("status", "--porcelain")) == "" },
                      "the files are restored")
    }

    func testStageThenUnstageWithTheButtonsLeavesNoStaleRow() throws {
        try commitHistory("base")
        try write("base.txt", "edited\n")
        let app = launch(appearance: "light")
        let row = item(app, "change-unstaged-base.txt")
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        row.click()
        item(app, "stage-base.txt").click()
        XCTAssertTrue(item(app, "change-staged-base.txt").waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil { !self.item(app, "change-unstaged-base.txt").exists }, "the unstaged row is gone")

        item(app, "unstage-base.txt").click()
        XCTAssertTrue(item(app, "change-unstaged-base.txt").waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil { !self.item(app, "change-staged-base.txt").exists }, "the staged row is gone")
        XCTAssertTrue(item(app, "stage-base.txt").exists, "the button offers Stage again")
        XCTAssertFalse(item(app, "unstage-base.txt").exists, "no Unstage button is left")
        XCTAssertTrue(waitUntil { (try? self.git("diff", "--cached", "--name-only")) == "" })
    }

    func testRibbonMinimizesAndStillSwitchesSections() throws {
        try commitHistory("base")
        let app = launch(appearance: "light")
        XCTAssertTrue(item(app, "section-Changes").waitForExistence(timeout: 10))
        XCTAssertTrue(item(app, "section-Branches").exists, "the expanded ribbon shows every section")

        item(app, "ribbon-toggle").click()
        XCTAssertTrue(item(app, "section-History").waitForExistence(timeout: 5), "the minimized ribbon keeps small buttons")
        item(app, "section-Branches").click()
        XCTAssertTrue(item(app, "branches-list").waitForExistence(timeout: 10), "a small button switches the section")

        item(app, "ribbon-toggle").click()
        XCTAssertTrue(item(app, "section-Tags").waitForExistence(timeout: 5))
    }

    func testChangesFoldersCollapseAndExpand() throws {
        try commitHistory("base")
        try FileManager.default.createDirectory(at: repository.appendingPathComponent("src"), withIntermediateDirectories: true)
        try write("src/a.txt", "a\n")
        try write("src/b.txt", "b\n")
        let app = launch(appearance: "light")
        XCTAssertTrue(item(app, "change-unstaged-src/a.txt").waitForExistence(timeout: 10))

        app.buttons["changes-collapse-all"].click()
        XCTAssertTrue(waitUntil { !self.item(app, "change-unstaged-src/a.txt").exists }, "collapse all hides the files")

        app.buttons["changes-expand-all"].click()
        XCTAssertTrue(item(app, "change-unstaged-src/a.txt").waitForExistence(timeout: 10), "expand all shows them again")
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

        item(app, "log-clear").click()
        XCTAssertTrue(waitUntil(timeout: 5) { !app.staticTexts["git add -- base.txt"].exists }, "Clear empties the panel")
        item(app, "log-close").click()
        XCTAssertTrue(waitUntil(timeout: 5) { !log.exists }, "the panel closes")
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

    func testStageSingleLinesOfANewFile() throws {
        try commitHistory("base")
        try write("new.txt", "alpha\nbeta\ngamma\n")
        let app = launch(appearance: "light")

        item(app, "change-unstaged-new.txt").click()
        let diff = app.tables["diff-view"]
        XCTAssertTrue(diff.waitForExistence(timeout: 10))
        let beta = diff.staticTexts.matching(NSPredicate(format: "value == %@", "+beta")).firstMatch
        XCTAssertTrue(beta.waitForExistence(timeout: 5), "the diff rows can be found")
        beta.click()

        let stageLines = app.buttons["stage-lines"]
        XCTAssertTrue(stageLines.waitForExistence(timeout: 5), "a new file offers line staging")
        stageLines.click()

        XCTAssertTrue(waitUntil { (try? self.git("show", ":new.txt")) == "beta\n" || (try? self.git("show", ":new.txt")) == "beta" })
    }

    func testSettingsHasTabsForAccountNetworkEnvironmentAndTheme() throws {
        try commitHistory("base")
        let app = launch(appearance: "light")
        XCTAssertTrue(item(app, "palette-button").waitForExistence(timeout: 10))

        app.typeKey(",", modifierFlags: .command)

        let window = app.windows["Settings"].exists ? app.windows["Settings"] : app.windows.element(boundBy: 0)
        // macOS reopens Settings on the tab used last, so the tab is chosen here instead of assumed.
        func tab(_ title: String) -> XCUIElement {
            app.buttons[title].exists ? app.buttons[title] : app.radioButtons[title]
        }
        for title in ["Account", "Network", "Environment", "Theme"] {
            XCTAssertTrue(tab(title).waitForExistence(timeout: 10), "\(title) tab exists")
        }
        tab("Account").click()
        XCTAssertTrue(app.textFields["settings-name"].waitForExistence(timeout: 10), "the Account tab edits the commit author")
        tab("Network").click()
        XCTAssertTrue(item(app, "settings-ssl").waitForExistence(timeout: 5))
        tab("Theme").click()
        XCTAssertTrue(item(app, "settings-dark").waitForExistence(timeout: 5))
        attachScreenshot(app, named: "settings-theme")
        _ = window
    }
}
