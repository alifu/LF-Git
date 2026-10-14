import XCTest

/// A real git repository in a temporary folder, the app launched on it, and the helpers to drive both.
class GitUITestCase: XCTestCase {
    var repository: URL!

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

    // MARK: - Helpers

    /// `accent` is passed as a launch argument, which beats whatever an earlier run or the user stored.
    func launch(appearance: String, accent: String = "green") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--repo", repository.path, "-appearance", appearance, "-accentColor", accent]
        app.launch()
        return app
    }

    func showSection(_ title: String, in app: XCUIApplication) {
        let picker = app.descendants(matching: .any)["section-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let button = picker.radioButtons[title].firstMatch.exists ? picker.radioButtons[title].firstMatch : picker.buttons[title].firstMatch
        button.click()
    }

    func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func waitUntil(timeout: TimeInterval = 8, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    func write(_ path: String, _ text: String) throws {
        let url = repository.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The UI test runner is sandboxed, and /usr/bin/git is an xcrun shim that refuses to run there.
    static let gitExecutable: String = {
        let candidates = [
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/git"
    }()

    @discardableResult
    func git(_ arguments: String..., allowFailure: Bool = false) throws -> String {
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
