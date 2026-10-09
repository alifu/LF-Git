import Foundation
@testable import LFGitCLI
import LFKit
import LFTestSupport
import Testing

@Suite("lfgit driver")
struct DriverTests {
    private func merge(base: String, ours: String, theirs: String, markerSize: Int = 7) throws -> (code: Int32, merged: String) {
        _ = try GitFixture() // isolates git configuration
        let box = Sandbox()
        let ancestor = box.write("O.txt", base)
        let current = box.write("A.txt", ours)
        let other = box.write("B.txt", theirs)
        let code = try DriverCommand.parse([ancestor, current, other, String(markerSize), "file.txt"]).execute(console: BufferConsole())
        return (code, box.readText(current))
    }

    @Test("non-overlapping changes merge cleanly into the current file")
    func cleanMerge() throws {
        let result = try merge(
            base: text("a", "b", "c", "d", "e", "f", "g"),
            ours: text("A", "b", "c", "d", "e", "f", "g"),
            theirs: text("a", "b", "c", "d", "e", "f", "G")
        )

        #expect(result.code == 0)
        #expect(result.merged == text("A", "b", "c", "d", "e", "f", "G"))
    }

    @Test("overlapping changes exit 1 and leave diff3 markers with a base section")
    func conflict() throws {
        let result = try merge(base: text("a", "b", "c"), ours: text("a", "b-ours", "c"), theirs: text("a", "b-theirs", "c"))

        #expect(result.code == 1)
        #expect(result.merged.contains("<<<<<<< HEAD"))
        #expect(result.merged.contains("||||||| "))
        #expect(result.merged.contains(">>>>>>> incoming"))
    }

    @Test("the marker size passed by git is used")
    func markerSize() throws {
        let result = try merge(
            base: text("a", "b", "c"), ours: text("a", "b-ours", "c"), theirs: text("a", "b-theirs", "c"), markerSize: 9
        )

        #expect(result.merged.contains("<<<<<<<<< HEAD"))
    }

    @Test("a missing input file is an error, not a conflict")
    func missingInput() throws {
        let box = Sandbox()
        let current = box.write("A.txt", "x\n")

        let code = try DriverCommand.parse([box.path("nope"), current, current, "7", "f"]).execute(console: BufferConsole())

        #expect(code == 2)
    }
}

@Suite("lfgit install")
struct InstallTests {
    private func config(_ fixture: GitFixture, _ key: String) throws -> String? {
        let result = try fixture.git.run(["config", "--local", "--get", key], allowedStatuses: [0, 1])
        return result.status == 0 ? String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    @Test("registers the merge tool and the merge driver in the repository config")
    func installs() throws {
        let fixture = try GitFixture()

        let code = try InstallCommand.parse(["-C", fixture.path]).execute(console: BufferConsole())

        #expect(code == 0)
        #expect(try config(fixture, "merge.tool") == "lfgit")
        #expect(try config(fixture, "mergetool.lfgit.cmd") == #"lfgit mergetool "$BASE" "$LOCAL" "$REMOTE" "$MERGED""#)
        #expect(try config(fixture, "mergetool.lfgit.trustexitcode") == "true")
        #expect(try config(fixture, "merge.lfgit.driver") == "lfgit driver %O %A %B %L %P")
    }

    @Test("an existing merge.tool is kept, with a hint on how to use lfgit anyway")
    func keepsOtherMergeTool() throws {
        let fixture = try GitFixture()
        try fixture.git.run(["config", "--local", "merge.tool", "kaleidoscope"])
        let console = BufferConsole()

        let code = try InstallCommand.parse(["-C", fixture.path]).execute(console: console)

        #expect(code == 0)
        #expect(try config(fixture, "merge.tool") == "kaleidoscope")
        #expect(try config(fixture, "merge.lfgit.driver") != nil)
        #expect(console.output.contains("--tool=lfgit"))
    }

    @Test("a .gitattributes that cannot be read as UTF-8 is never rewritten")
    func attributesNotWipedWhenUnreadable() throws {
        let fixture = try GitFixture()
        let original: [UInt8] = Array("# caf".utf8) + [0xE9] + Array("\n*.png binary\n".utf8)
        fixture.sandbox.write(".gitattributes", bytes: original)

        #expect(throws: (any Error).self) {
            try InstallCommand.parse(["-C", fixture.path, "--attributes", "*.pbxproj"]).execute(console: BufferConsole())
        }
        #expect(fixture.sandbox.read(fixture.sandbox.path(".gitattributes")) == original)
    }

    @Test("--executable is shell-quoted into both commands")
    func executablePath() throws {
        let fixture = try GitFixture()

        _ = try InstallCommand.parse(["-C", fixture.path, "--executable", "/opt/my tools/lfgit"]).execute(console: BufferConsole())

        #expect(try config(fixture, "merge.lfgit.driver") == "'/opt/my tools/lfgit' driver %O %A %B %L %P")
    }

    @Test("--dry-run prints the commands and changes nothing")
    func dryRun() throws {
        let fixture = try GitFixture()
        let console = BufferConsole()

        _ = try InstallCommand.parse(["-C", fixture.path, "--dry-run", "--global"]).execute(console: console)

        #expect(console.output.contains("git config --global merge.tool lfgit"))
        #expect(try config(fixture, "merge.tool") == nil)
    }

    @Test("--attributes writes merge=lfgit rules once")
    func attributes() throws {
        let fixture = try GitFixture()
        let arguments = ["-C", fixture.path, "--attributes", "*.pbxproj"]

        _ = try InstallCommand.parse(arguments).execute(console: BufferConsole())
        _ = try InstallCommand.parse(arguments).execute(console: BufferConsole())

        let attributes = fixture.read(".gitattributes")
        #expect(attributes.components(separatedBy: "*.pbxproj merge=lfgit").count == 2)
    }

    @Test("--uninstall removes what install added, but not another tool's setting")
    func uninstall() throws {
        let fixture = try GitFixture()
        _ = try InstallCommand.parse(["-C", fixture.path]).execute(console: BufferConsole())

        let code = try InstallCommand.parse(["-C", fixture.path, "--uninstall"]).execute(console: BufferConsole())

        #expect(code == 0)
        #expect(try config(fixture, "merge.tool") == nil)
        #expect(try config(fixture, "merge.lfgit.driver") == nil)

        try fixture.git.run(["config", "--local", "merge.tool", "kaleidoscope"])
        _ = try InstallCommand.parse(["-C", fixture.path, "--uninstall"]).execute(console: BufferConsole())
        #expect(try config(fixture, "merge.tool") == "kaleidoscope")
    }

    @Test("--global with --uninstall and no repository still works on a plain directory")
    func globalDoesNotNeedRepository() throws {
        let box = Sandbox()
        let console = BufferConsole()

        let code = try InstallCommand.parse(["-C", box.root.path, "--global", "--dry-run"]).execute(console: console)

        #expect(code == 0)
    }

    @Test("local install outside a repository fails")
    func localNeedsRepository() {
        let box = Sandbox()

        #expect(throws: GitError.self) {
            try InstallCommand.parse(["-C", box.root.path]).execute(console: BufferConsole())
        }
    }
}

@Suite("Terminal palette")
struct PaletteTests {
    private struct Theme: Decodable {
        struct Token: Decodable { let light: String; let dark: String }
        let palette: [String: String]
        let tokens: [String: Token]
    }

    private func loadTheme() throws -> Theme {
        // .../LFCore/Tests/LFGitCLITests/File.swift -> repo root
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Design/theme.json"))
        return try JSONDecoder().decode(Theme.self, from: data)
    }

    @Test("every terminal colour equals the theme.json token it is derived from")
    func matchesTheme() throws {
        let theme = try loadTheme()

        for entry in TerminalPalette.entries {
            let token = try #require(theme.tokens[entry.token], "unknown token \(entry.token)")
            #expect(theme.palette[token.light]?.uppercased() == entry.light.uppercased(), "\(entry.role) light")
            #expect(theme.palette[token.dark]?.uppercased() == entry.dark.uppercased(), "\(entry.role) dark")
        }
    }

    @Test("NO_COLOR and non-terminals disable colour")
    func detectsDisabled() {
        #expect(TerminalPalette.detect(environment: ["NO_COLOR": "1"], isTerminal: true) == nil)
        #expect(TerminalPalette.detect(environment: [:], isTerminal: false) == nil)
        #expect(TerminalPalette.detect(environment: ["TERM": "dumb"], isTerminal: true) == nil)
    }

    @Test("a light terminal background selects the light palette, anything else the dark one")
    func detectsBackground() {
        #expect(TerminalPalette.detect(environment: ["COLORFGBG": "0;15"], isTerminal: true) == .light)
        #expect(TerminalPalette.detect(environment: ["COLORFGBG": "15;0"], isTerminal: true) == .dark)
        #expect(TerminalPalette.detect(environment: [:], isTerminal: true) == .dark)
    }

    @Test("painting wraps text in a 24-bit colour escape and resets")
    func paints() {
        let painted = TerminalPalette.dark.paint("hi", TerminalPalette.dark.current)

        #expect(painted.hasPrefix("\u{1B}[38;2;"))
        #expect(painted.hasSuffix("hi\u{1B}[0m"))
    }
}
