import XCTest

/// Not a check of behaviour: walks through the features and keeps a screenshot of each (attachments named `shot-…`),
/// which `Scripts/docs/export-screenshots.sh` copies into `docs/images/` for the README.
final class ScreenshotTourUITests: GitUITestCase {
    private func item(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    private func commit(_ message: String, files: [String: String]) throws {
        for (path, text) in files { try write(path, text) }
        try git("add", "-A")
        try git("commit", "-q", "-m", message)
    }

    private func buildProject() throws {
        try commit("Add the greeter", files: [
            "Sources/Greeter.swift": "import Foundation\n\nstruct Greeter {\n    let name: String\n\n    func greet() -> String {\n        \"Hello, \\(name)\"\n    }\n}\n",
            "README.md": "# Demo\n\nA small project.\n",
        ])
        try commit("Add tests", files: ["Tests/GreeterTests.swift": "import XCTest\n\nfinal class GreeterTests: XCTestCase {}\n"])
        try git("tag", "v0.1")
        try git("checkout", "-q", "-b", "feature/shout")
        try commit("Shout the greeting", files: ["Sources/Shout.swift": "func shout(_ text: String) -> String { text.uppercased() }\n"])
        try git("checkout", "-q", "main")
        try git("branch", "feature/quiet")
        try git("branch", "release/1.0")
        // Work in progress: an edit in two places, a new file in a folder, a staged file.
        try write("Sources/Greeter.swift",
                  "import Foundation\n\nstruct Greeter {\n    let name: String\n    var punctuation = \"!\"\n\n    func greet() -> String {\n        \"Hello, \\(name)\\(punctuation)\"\n    }\n}\n")
        try write("Sources/Farewell.swift", "struct Farewell {\n    func say() -> String { \"Goodbye\" }\n}\n")
        try write("README.md", "# Demo\n\nA small project that greets people.\n")
        try git("add", "README.md")
    }

    func testTourOfTheFeatures() throws {
        try buildProject()
        let app = launch(appearance: "light")

        // Changes: staged and unstaged folders, a diff with selected lines.
        let row = item(app, "change-unstaged-Sources/Greeter.swift")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.click()
        let diff = item(app, "diff-view")
        XCTAssertTrue(diff.waitForExistence(timeout: 10))
        let rows = diff.tableRows
        if rows.count > 9 {
            rows.element(boundBy: 9).click() // the added "var punctuation" line
            XCUIElement.perform(withKeyModifiers: .shift) { rows.element(boundBy: 12).click() }
        }
        Thread.sleep(forTimeInterval: 0.5)
        shot(app, "changes")

        // Branches: local / remote groups, search.
        showSection("Branches", in: app)
        XCTAssertTrue(item(app, "branches-list").waitForExistence(timeout: 10))
        shot(app, "branches")

        // History with blame beside the diff.
        showSection("History", in: app)
        XCTAssertTrue(item(app, "commit-Add the greeter").waitForExistence(timeout: 10))
        item(app, "commit-Add the greeter").click()
        let file = item(app, "commit-file-Sources/Greeter.swift").firstMatch
        if file.waitForExistence(timeout: 10) { file.click() }
        Thread.sleep(forTimeInterval: 1.5)
        shot(app, "history")

        // The ribbon, minimized.
        item(app, "ribbon-toggle").click()
        Thread.sleep(forTimeInterval: 0.5)
        shot(app, "ribbon-minimized")
        item(app, "ribbon-toggle").click()

        // The branch menu with search.
        app.buttons["branch-menu"].firstMatch.click()
        Thread.sleep(forTimeInterval: 1)
        shot(app, "branch-menu")
        app.typeKey(.escape, modifierFlags: [])

        // Settings: accent color.
        app.typeKey(",", modifierFlags: .command)
        let theme = app.buttons["Theme"].exists ? app.buttons["Theme"] : app.radioButtons["Theme"]
        XCTAssertTrue(theme.waitForExistence(timeout: 10))
        theme.click()
        XCTAssertTrue(item(app, "settings-accent-blue").waitForExistence(timeout: 5))
        item(app, "settings-accent-blue").click()
        Thread.sleep(forTimeInterval: 0.8)
        shot(app, "settings-accent", window: "Settings")
        item(app, "settings-accent-green").click() // leave the default behind
    }

    func testTourOfAConflict() throws {
        try commit("Base", files: ["Sources/App.swift": "import Foundation\n\nlet greeting = \"hello\"\n"])
        try git("checkout", "-q", "-b", "feature")
        try commit("Feature", files: ["Sources/App.swift": "import Foundation\n\nlet greeting = \"hello from feature\"\nlet shout = true\n"])
        try git("checkout", "-q", "main")
        try commit("Main", files: ["Sources/App.swift": "import Foundation\n\nlet greeting = \"hello from main\"\nlet count = 1\n"])
        try git("merge", "feature", allowFailure: true)

        let app = launch(appearance: "light")
        XCTAssertTrue(app.buttons["accept-current-0"].waitForExistence(timeout: 15))
        shot(app, "conflict")
    }

    private func shot(_ app: XCUIApplication, _ name: String, window: String? = nil) {
        let target = window.flatMap { app.windows[$0].exists ? app.windows[$0] : nil } ?? app.windows.firstMatch
        let attachment = XCTAttachment(screenshot: target.screenshot())
        attachment.name = "shot-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
