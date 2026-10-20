import XCTest

/// The dashboard, the clone sheet and closing a repository, in the real app.
final class CloneAndDashboardUITests: GitUITestCase {
    private func launchOnDashboard() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LFNoRestore"]
        app.launch()
        return app
    }

    /// A bare repository with `main` and `topic`, standing in for a server.
    private func makeRemote() throws -> URL {
        try write("a.txt", "1\n")
        try git("add", "-A")
        try git("commit", "-q", "-m", "base")
        try git("branch", "topic")
        let remote = FileManager.default.temporaryDirectory.appendingPathComponent("lfgit-ui-remote-\(UUID().uuidString).git")
        try git("clone", "-q", "--bare", repository.path, remote.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: remote) }
        return remote
    }

    func testDashboardOffersOpenAndClone() throws {
        let app = launchOnDashboard()

        XCTAssertTrue(app.buttons["open-repository"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["clone-repository"].exists)
        attachScreenshot(app, named: "dashboard")
    }

    func testCloneSheetFindsTheBranchesAndWaitsForAFolder() throws {
        let remote = try makeRemote()
        let app = launchOnDashboard()
        app.buttons["clone-repository"].click()

        let field = app.textFields["clone-url"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click()
        field.typeText("file://\(remote.path)")

        XCTAssertTrue(app.popUpButtons["clone-branch"].waitForExistence(timeout: 15), "the branches are offered once the address is valid")
        XCTAssertTrue(app.textFields["clone-folder-name"].exists)
        XCTAssertFalse(app.buttons["clone-button"].isEnabled, "no folder is chosen yet, so Clone waits")
        attachScreenshot(app, named: "clone-sheet")

        app.buttons["clone-cancel"].click()
        XCTAssertTrue(app.buttons["open-repository"].waitForExistence(timeout: 5))
    }

    func testCloneSheetExplainsAnAddressGitCannotUse() throws {
        let app = launchOnDashboard()
        app.buttons["clone-repository"].click()

        let field = app.textFields["clone-url"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click()
        field.typeText("not a url")

        XCTAssertTrue(app.staticTexts["Use an https://, ssh:// or git@host:path address."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["clone-button"].isEnabled)
    }

    func testClosingTheRepositoryReturnsToTheDashboard() throws {
        try write("a.txt", "1\n")
        try git("add", "-A")
        try git("commit", "-q", "-m", "base")
        let app = launch(appearance: "light")
        let close = app.buttons["close-repository-button"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))

        close.click()

        XCTAssertTrue(app.buttons["open-repository"].waitForExistence(timeout: 10))
        XCTAssertFalse(close.exists)
    }
}
