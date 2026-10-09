import ArgumentParser
import Foundation
@testable import LFGitCLI
import LFKit
import Testing

@Suite("lfgit status")
struct StatusTests {
    @Test("a clean repository reports no conflicts")
    func clean() throws {
        let fixture = try GitFixture()
        fixture.sandbox.write("a.txt", "hello\n")
        try fixture.commitAll("init")
        let console = BufferConsole()

        let code = try StatusCommand.parse(["-C", fixture.path]).execute(console: console)

        #expect(code == 0)
        #expect(console.output.contains("No conflicted files"))
    }

    @Test("conflicted text and binary files are listed with their type and conflict count")
    func listsFiles() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([
            .text("a.txt"),
            ConflictSpec(path: "logo.png", base: [0, 1, 2], ours: [0, 1, 3], theirs: [0, 1, 4]),
        ])
        let console = BufferConsole()

        let code = try StatusCommand.parse(["-C", fixture.path]).execute(console: console)

        #expect(code == 0)
        #expect(console.output.contains("2 conflicted files"))
        #expect(console.output.contains("a.txt"))
        #expect(console.output.contains("1 conflict"))
        #expect(console.output.contains("logo.png"))
        #expect(console.output.contains("binary"))
    }

    @Test("outside a repository the command fails")
    func notARepository() {
        let box = Sandbox()

        #expect(throws: GitError.self) {
            try StatusCommand.parse(["-C", box.root.path]).execute(console: BufferConsole())
        }
    }
}

@Suite("lfgit resolve")
struct ResolveCommandTests {
    @Test("--all-current keeps our side and --stage marks the file resolved")
    func currentAndStage() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")])
        let console = BufferConsole()

        let code = try ResolveCommand.parse(["-C", fixture.path, "--all-current", "--stage", "a.txt"]).execute(console: console)

        #expect(code == 0)
        #expect(fixture.read("a.txt") == "a\nb-ours\nc\n")
        #expect(try fixture.conflictedPaths().isEmpty)
        #expect(console.output.contains("resolved 1 conflict"))
    }

    @Test("--all-incoming keeps their side; without --stage the file stays unmerged")
    func incomingWithoutStage() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")])

        let code = try ResolveCommand.parse(["-C", fixture.path, "--all-incoming", "a.txt"]).execute(console: BufferConsole())

        #expect(code == 0)
        #expect(fixture.read("a.txt") == "a\nb-theirs\nc\n")
        #expect(try fixture.conflictedPaths() == ["a.txt"])
    }

    @Test("--all-both keeps both sides, current first")
    func both() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")])

        _ = try ResolveCommand.parse(["-C", fixture.path, "--all-both", "a.txt"]).execute(console: BufferConsole())

        #expect(fixture.read("a.txt") == "a\nb-ours\nb-theirs\nc\n")
    }

    @Test("--all-base restores the common ancestor when the repository uses diff3")
    func base() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")], diff3: true)

        let code = try ResolveCommand.parse(["-C", fixture.path, "--all-base", "a.txt"]).execute(console: BufferConsole())

        #expect(code == 0)
        #expect(fixture.read("a.txt") == "a\nb\nc\n")
    }

    @Test("--all-base fails, and changes nothing, when there is no base section")
    func baseWithoutBase() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")])
        let before = fixture.read("a.txt")
        let console = BufferConsole()

        let code = try ResolveCommand.parse(["-C", fixture.path, "--all-base", "a.txt"]).execute(console: console)

        #expect(code == 1)
        #expect(fixture.read("a.txt") == before)
        #expect(console.errors.contains("a.txt"))
    }

    @Test("without file arguments every conflicted file is resolved")
    func allFiles() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt"), .text("sub/b.txt")])

        let code = try ResolveCommand.parse(["-C", fixture.path, "--all-incoming", "--stage"]).execute(console: BufferConsole())

        #expect(code == 0)
        #expect(try fixture.conflictedPaths().isEmpty)
        #expect(fixture.read("sub/b.txt") == "a\nb-theirs\nc\n")
    }

    @Test("binary files take a whole side with --all-current / --all-incoming")
    func binaryWholeFile() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([ConflictSpec(path: "logo.png", base: [0, 1, 2], ours: [0, 1, 3], theirs: [0, 1, 4])])

        let code = try ResolveCommand.parse(["-C", fixture.path, "--all-incoming", "--stage", "logo.png"]).execute(console: BufferConsole())

        #expect(code == 0)
        #expect(fixture.sandbox.read(fixture.sandbox.path("logo.png")) == [0, 1, 4])
        #expect(try fixture.conflictedPaths().isEmpty)
    }

    @Test("binary files cannot be merged with --all-both")
    func binaryBothRejected() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([ConflictSpec(path: "logo.png", base: [0, 1, 2], ours: [0, 1, 3], theirs: [0, 1, 4])])
        let console = BufferConsole()

        let code = try ResolveCommand.parse(["-C", fixture.path, "--all-both", "logo.png"]).execute(console: console)

        #expect(code == 1)
        #expect(console.errors.contains("binary"))
    }

    @Test("--dry-run reports what would happen and writes nothing")
    func dryRun() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")])
        let before = fixture.read("a.txt")
        let console = BufferConsole()

        let code = try ResolveCommand.parse(["-C", fixture.path, "--all-current", "--stage", "--dry-run", "a.txt"]).execute(console: console)

        #expect(code == 0)
        #expect(fixture.read("a.txt") == before)
        #expect(console.output.contains("would resolve 1 conflict"))
        #expect(try fixture.conflictedPaths() == ["a.txt"])
    }

    @Test("a file without conflict markers is skipped, not an error")
    func noMarkers() throws {
        let fixture = try GitFixture()
        fixture.sandbox.write("plain.txt", "hello\n")
        try fixture.commitAll("init")
        let console = BufferConsole()

        let code = try ResolveCommand.parse(["-C", fixture.path, "--all-current", "plain.txt"]).execute(console: console)

        #expect(code == 0)
        #expect(console.output.contains("no conflict markers"))
    }

    @Test("--stage does not stage a file that still has no markers because something else broke the merge")
    func noMarkersIsNotStaged() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")])
        fixture.sandbox.write("a.txt", "marker-free, but never actually resolved\n")
        let console = BufferConsole()

        let code = try ResolveCommand.parse(["-C", fixture.path, "--all-current", "--stage", "a.txt"]).execute(console: console)

        #expect(code == 0)
        #expect(try fixture.conflictedPaths() == ["a.txt"])
        #expect(console.output.contains("git add"))
    }

    @Test("a file outside the repository is reported without stopping the others")
    func outsideRepository() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")])
        let outside = Sandbox().write("elsewhere.txt", "x\n")
        let console = BufferConsole()

        let code = try ResolveCommand.parse(["-C", fixture.path, "--all-current", outside, "a.txt"]).execute(console: console)

        #expect(code == 1)
        #expect(console.errors.contains("outside"))
        #expect(fixture.read("a.txt") == "a\nb-ours\nc\n")
    }

    @Test("a missing file is reported and fails the command")
    func missingFile() throws {
        let fixture = try GitFixture()
        let console = BufferConsole()

        let code = try ResolveCommand.parse(["-C", fixture.path, "--all-current", "nope.txt"]).execute(console: console)

        #expect(code == 1)
        #expect(console.errors.contains("nope.txt"))
    }

    @Test("conflict-marker-size from .gitattributes is honoured")
    func customMarkerSize() throws {
        let fixture = try GitFixture()
        fixture.sandbox.write(".gitattributes", "*.txt conflict-marker-size=9\n")
        fixture.sandbox.write("a.txt", text("<<<<<<<<< HEAD", "ours", "=========", "theirs", ">>>>>>>>> feature"))

        let code = try ResolveCommand.parse(["-C", fixture.path, "--all-incoming", "a.txt"]).execute(console: BufferConsole())

        #expect(code == 0)
        #expect(fixture.read("a.txt") == "theirs\n")
    }

    @Test("exactly one strategy flag is required")
    func strategyValidation() {
        #expect(throws: (any Error).self) { try ResolveCommand.parse(["a.txt"]) }
        #expect(throws: (any Error).self) { try ResolveCommand.parse(["--all-current", "--all-incoming", "a.txt"]) }
    }
}
