import XCTest

/// Drives the real app against a real conflicted repository.
final class ConflictResolutionUITests: XCTestCase {
    private var repository: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        repository = FileManager.default.temporaryDirectory.appendingPathComponent("lfgit-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main")
        try git("config", "user.name", "UI Test")
        try git("config", "user.email", "ui@example.com")
        try write("Sources/App.swift", "import Foundation\n\nlet greeting = \"hello\"\nlet count = 1\n")
        try git("add", "-A")
        try git("commit", "-q", "-m", "base")
        try git("checkout", "-q", "-b", "feature")
        try write("Sources/App.swift", "import Foundation\n\nlet greeting = \"hello from feature\"\nlet count = 1\n")
        try git("commit", "-q", "-am", "theirs")
        try git("checkout", "-q", "main")
        try write("Sources/App.swift", "import Foundation\n\nlet greeting = \"hello from main\"\nlet count = 1\n")
        try git("commit", "-q", "-am", "ours")
        try git("merge", "feature", allowFailure: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repository)
    }

    func testResolveAndSaveAConflict() throws {
        let app = launch(appearance: "light")

        let file = app.descendants(matching: .any)["file-Sources/App.swift"]
        XCTAssertTrue(file.waitForExistence(timeout: 10), "the conflicted file is listed")
        let accept = app.buttons["accept-current-0"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10), "the conflict shows its actions")
        attachScreenshot(app, named: "editor-light")

        accept.click()
        XCTAssertTrue(app.staticTexts["All 1 resolved"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "accepted-before-save")
        app.buttons["save"].click()

        let saved = try String(contentsOf: repository.appendingPathComponent("Sources/App.swift"), encoding: .utf8)
        XCTAssertEqual(saved, "import Foundation\n\nlet greeting = \"hello from main\"\nlet count = 1\n")
        XCTAssertTrue(waitUntil { (try? self.git("diff", "--name-only", "--diff-filter=U").isEmpty) == true }, "saving staged the file")
        attachScreenshot(app, named: "resolved-light")
    }

    func testEditAConflictToKeepCodeFromBothSides() throws {
        let app = launch(appearance: "light")
        let edit = app.buttons["edit-0"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10), "every open conflict offers Edit")
        edit.click()

        let box = app.textViews["edit-text"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        attachScreenshot(app, named: "edit-conflict")
        app.buttons["edit-start-both"].click()
        box.click()
        app.typeKey("a", modifierFlags: .command)
        box.typeText("let greeting = \"hello from both\"\n")
        app.buttons["edit-apply"].click()

        XCTAssertTrue(app.staticTexts["All 1 resolved"].waitForExistence(timeout: 5))
        app.buttons["save"].click()
        XCTAssertTrue(waitUntil { (try? self.git("diff", "--name-only", "--diff-filter=U").isEmpty) == true })
        let saved = try String(contentsOf: repository.appendingPathComponent("Sources/App.swift"), encoding: .utf8)
        XCTAssertEqual(saved, "import Foundation\n\nlet greeting = \"hello from both\"\nlet count = 1\n")
    }

    func testKeyboardShortcutsAndUndo() throws {
        let app = launch(appearance: "light")
        XCTAssertTrue(app.buttons["accept-current-0"].waitForExistence(timeout: 10))

        app.typeKey("2", modifierFlags: .command) // Accept Incoming
        XCTAssertTrue(app.staticTexts["All 1 resolved"].waitForExistence(timeout: 5))
        app.typeKey("z", modifierFlags: .command) // Undo Resolution
        XCTAssertTrue(app.staticTexts["1 of 1 unresolved"].waitForExistence(timeout: 5))
        app.typeKey("z", modifierFlags: [.command, .shift]) // Redo
        XCTAssertTrue(app.staticTexts["All 1 resolved"].waitForExistence(timeout: 5))
        app.typeKey("s", modifierFlags: .command)

        let saved = try String(contentsOf: repository.appendingPathComponent("Sources/App.swift"), encoding: .utf8)
        XCTAssertEqual(saved, "import Foundation\n\nlet greeting = \"hello from feature\"\nlet count = 1\n")
    }

    func testTwoMillionLineFile() throws {
        // A real merge: 2,000,000 lines where both branches change the same 1,000 lines differently.
        try FileManager.default.removeItem(at: repository)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main")
        try git("config", "user.name", "UI Test")
        try git("config", "user.email", "ui@example.com")
        let lines = 2_000_000, every = 2_000
        func version(_ tag: String?) -> String {
            var text = ""
            text.reserveCapacity(lines * 24)
            for index in 0..<lines {
                if let tag, index % every == every / 2 {
                    text += "let value\(index) = \"\(tag)\"\n"
                } else {
                    text += "let value\(index) = \(index)\n"
                }
            }
            return text
        }
        try write("Big.swift", version(nil))
        try git("add", "-A")
        try git("commit", "-q", "-m", "base")
        try git("checkout", "-q", "-b", "feature")
        try write("Big.swift", version("theirs"))
        try git("commit", "-q", "-am", "theirs")
        try git("checkout", "-q", "main")
        try write("Big.swift", version("ours"))
        try git("commit", "-q", "-am", "ours")
        try git("merge", "feature", allowFailure: true)

        let app = XCUIApplication()
        app.launchArguments = ["--repo", repository.path, "--file", "Big.swift"]
        let start = Date()
        app.launch()
        // The status uses the user's number format (e.g. "1.000" or "1,000"), like the app does.
        let status = { (left: Int, total: Int) in "\(left.formatted()) of \(total.formatted()) unresolved" }
        XCTAssertTrue(app.staticTexts[status(1000, 1000)].waitForExistence(timeout: 30), "the file opens with its conflicts")
        let opened = Date().timeIntervalSince(start)

        // XCTest only snapshots the first 1,000 table rows, so drive the editor with the keyboard here.
        for _ in 0..<5 { app.typeKey(.downArrow, modifierFlags: [.command, .option]) } // jump through the file
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts[status(999, 1000)].waitForExistence(timeout: 5))
        app.typeKey("2", modifierFlags: [.command, .shift]) // Accept All Incoming
        XCTAssertTrue(app.staticTexts["All \(1000.formatted()) resolved"].waitForExistence(timeout: 10))
        attachScreenshot(app, named: "two-million-lines")
        let note = XCTAttachment(string: String(format: "launch to first conflict: %.2f s", opened))
        note.name = "timing"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertLessThan(opened, 15, "opening a 2M-line file stays interactive")
    }

    func testSwitchingFilesKeepsUnsavedWorkAndPartialSavesContinue() throws {
        try rebuildRepository(files: [
            "Sources/App.swift": ("a\nb\nc\n", "a\nb-ours\nc\n", "a\nb-theirs\nc\n"),
            "Sources/Other.swift": ("1\n2\n3\n4\n5\n6\n7\n8\n", "1\n2-ours\n3\n4\n5\n6\n7-ours\n8\n", "1\n2-theirs\n3\n4\n5\n6\n7-theirs\n8\n"),
        ])
        let app = XCUIApplication()
        app.launchArguments = ["--repo", repository.path, "--file", "Sources/Other.swift"]
        app.launch()
        XCTAssertTrue(app.buttons["accept-current-0"].waitForExistence(timeout: 10))

        app.buttons["accept-current-0"].click()
        XCTAssertTrue(app.staticTexts["1 of 2 unresolved"].waitForExistence(timeout: 5))

        // Away and back: the unsaved resolution is still there.
        app.descendants(matching: .any)["file-Sources/App.swift"].click()
        XCTAssertTrue(app.staticTexts["1 of 1 unresolved"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["file-Sources/Other.swift"].click()
        XCTAssertTrue(app.staticTexts["1 of 2 unresolved"].waitForExistence(timeout: 5))

        // Save part of the work, then keep resolving in the same view.
        app.buttons["save"].click()
        XCTAssertTrue(app.buttons["accept-incoming-1"].waitForExistence(timeout: 5))
        app.buttons["accept-incoming-1"].click()
        XCTAssertTrue(app.staticTexts["All 2 resolved"].waitForExistence(timeout: 5))
        app.buttons["save"].click()

        XCTAssertTrue(waitUntil {
            (try? String(contentsOf: self.repository.appendingPathComponent("Sources/Other.swift"), encoding: .utf8))
                == "1\n2-ours\n3\n4\n5\n6\n7-theirs\n8\n"
        })
        XCTAssertTrue(waitUntil { (try? self.git("diff", "--name-only", "--diff-filter=U")) == "Sources/App.swift" })
    }

    func testLinkOpensRepositoryInRunningApp() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-LFNoRestore"]
        app.launch() // the dashboard: nothing is reopened
        XCTAssertTrue(app.buttons["open-repository"].waitForExistence(timeout: 10))

        var link = URLComponents()
        link.scheme = "lfgit"
        link.host = "open"
        link.queryItems = [URLQueryItem(name: "repo", value: repository.path), URLQueryItem(name: "file", value: "Sources/App.swift")]
        app.open(try XCTUnwrap(link.url)) // what `lfgit open` sends; it must reach the running app

        XCTAssertTrue(app.buttons["accept-current-0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["file-Sources/App.swift"].exists)
    }

    func testDarkModeScreenshot() throws {
        let app = launch(appearance: "dark")
        XCTAssertTrue(app.buttons["accept-current-0"].waitForExistence(timeout: 10))
        attachScreenshot(app, named: "editor-dark")
    }

    // MARK: - Helpers

    /// Replaces the repository with one where every file conflicts: path -> (base, ours, theirs).
    private func rebuildRepository(files: [String: (String, String, String)]) throws {
        try FileManager.default.removeItem(at: repository)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main")
        try git("config", "user.name", "UI Test")
        try git("config", "user.email", "ui@example.com")
        for (path, versions) in files { try write(path, versions.0) }
        try git("add", "-A")
        try git("commit", "-q", "-m", "base")
        try git("checkout", "-q", "-b", "feature")
        for (path, versions) in files { try write(path, versions.2) }
        try git("commit", "-q", "-am", "theirs")
        try git("checkout", "-q", "main")
        for (path, versions) in files { try write(path, versions.1) }
        try git("commit", "-q", "-am", "ours")
        try git("merge", "feature", allowFailure: true)
    }

    private func launch(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--repo", repository.path, "-appearance", appearance]
        app.launch()
        return app
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
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
        process.standardOutput = output
        let errors = Pipe()
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
