import XCTest

/// Not a check of behaviour: opens the demo project once per layout choice (Settings › Layout, passed as launch
/// arguments so nothing stored is changed) and keeps a screenshot of each, as attachments named `layout-…`.
/// Export them with `PREFIX=layout OUT=<folder> Scripts/docs/export-screenshots.sh <result>`.
final class LayoutTourUITests: GitUITestCase {
    private func item(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func launchDemo(_ arguments: [String]) -> XCUIApplication {
        launch(appearance: "light", arguments: arguments)
    }

    private func selectGreeterChange(_ app: XCUIApplication) {
        let row = item(app, "change-unstaged-Sources/Greeter.swift")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.click()
        XCTAssertTrue(item(app, "diff-view").waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.8)
    }

    // MARK: - Changes: L1 Classic, L4 Inline preview, L3 Lanes

    func testChangesLayouts() throws {
        try buildDemoProject()
        for (layout, name) in [("classic", "L1-changes-classic"), ("inline", "L4-changes-inline"), ("lanes", "L3-changes-lanes")] {
            let app = launchDemo(["-layout.changes", layout])
            selectGreeterChange(app)
            shot(app, name)
            if layout == "lanes" { try shootLaneCommitPreview(app) }
            app.terminate()
        }
    }

    private func shootLaneCommitPreview(_ app: XCUIApplication) throws {
        let commits = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'lane-commit-' AND identifier != 'lane-commit-panel'"))
        guard commits.firstMatch.waitForExistence(timeout: 10) else { return }
        commits.firstMatch.click()
        _ = item(app, "lane-commit-panel").waitForExistence(timeout: 10)
        Thread.sleep(forTimeInterval: 1)
        shot(app, "L3-lanes-commit-preview")
    }

    // MARK: - L5 Floating panels (over Classic)

    func testFloatingPanels() throws {
        try buildDemoProject()
        let app = launchDemo(["-layout.changes", "classic"])
        selectGreeterChange(app)

        let popDiff = item(app, "pop-out-diff")
        XCTAssertTrue(popDiff.waitForExistence(timeout: 10))
        popDiff.click()
        Thread.sleep(forTimeInterval: 1)
        shot(app, "L5-floating-diff")
        if item(app, "floating-diff-close").exists { item(app, "floating-diff-close").click() }

        let popEditor = item(app, "pop-out-commit-editor")
        XCTAssertTrue(popEditor.waitForExistence(timeout: 10))
        popEditor.click()
        Thread.sleep(forTimeInterval: 1)
        shot(app, "L5-floating-commit-editor")
    }

    // MARK: - Branches and History: L1 Classic, L2 Three columns

    func testListsLayouts() throws {
        try buildDemoProject()
        for (layout, prefix) in [("classic", "L1"), ("threeColumn", "L2")] {
            let app = launchDemo(["-layout.lists", layout])
            shootBranches(app, name: "\(prefix)-branches-\(layout)")
            shootHistory(app, name: "\(prefix)-history-\(layout)")
            app.terminate()
        }
    }

    private func shootBranches(_ app: XCUIApplication, name: String) {
        showSection("Branches", in: app)
        XCTAssertTrue(item(app, "branches-list").waitForExistence(timeout: 10))
        let branch = item(app, "branch-feature/shout")
        if branch.waitForExistence(timeout: 5) { branch.click() }
        Thread.sleep(forTimeInterval: 1.5)
        shot(app, name)
    }

    private func shootHistory(_ app: XCUIApplication, name: String) {
        showSection("History", in: app)
        let commit = item(app, "commit-Add the greeter")
        XCTAssertTrue(commit.waitForExistence(timeout: 10))
        commit.click()
        let file = item(app, "commit-file-Sources/Greeter.swift")
        if file.waitForExistence(timeout: 10) { file.click() }
        Thread.sleep(forTimeInterval: 1.5)
        shot(app, name)
    }

    // MARK: - Reflog: list or L7 timeline

    func testReflogLayouts() throws {
        try buildDemoProject()
        for (timeline, name) in [("NO", "L1-reflog-list"), ("YES", "L7-reflog-timeline")] {
            let app = launchDemo(["-layout.timeline", timeline])
            showSection("Reflog", in: app)
            XCTAssertTrue(item(app, "reflog-list").waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 1)
            shot(app, name)
            app.terminate()
        }
    }

    // MARK: - L6 Hero pane (dashboard with no recent repositories) and L8 Settings

    func testDashboardHero() throws {
        let app = XCUIApplication()
        // An empty recents list for this run only (the argument domain is not saved).
        app.launchArguments = ["-LFNoRestore", "-recentRepositories", "()", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["open-repository"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.8)
        shot(app, "L6-dashboard-hero")
    }

    func testSettingsSidebar() throws {
        let app = launchDemo([])
        XCTAssertTrue(item(app, "section-picker").waitForExistence(timeout: 15))
        app.typeKey(",", modifierFlags: .command)
        for (tab, name) in [("layout", "L8-settings-layout"), ("general", "L8-settings-general")] {
            let row = item(app, "settings-tab-\(tab)")
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.click()
            Thread.sleep(forTimeInterval: 0.8)
            shot(app, name, window: "Settings")
        }
    }

    private func shot(_ app: XCUIApplication, _ name: String, window: String? = nil) {
        let target = window.flatMap { app.windows[$0].exists ? app.windows[$0] : nil } ?? app.windows.firstMatch
        let attachment = XCTAttachment(screenshot: target.screenshot())
        attachment.name = "layout-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
