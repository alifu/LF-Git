import Foundation
@testable import LFGitCLI
import LFKit
import LFTestSupport
import Testing

private let projectPath = "App.xcodeproj/project.pbxproj"

/// Both sides add a file (git's line merge conflicts on that); optionally both change SWIFT_VERSION too.
private func scenario(conflictingSetting: Bool) -> (base: ClassicProject, ours: ClassicProject, theirs: ClassicProject, merged: ClassicProject) {
    let base = ClassicProject.withSources([1])
    var ours = base
    ours.addSource(2)
    var theirs = base
    theirs.addSource(3)
    if conflictingSetting {
        ours.debugSettings["SWIFT_VERSION"] = .value("5.9")
        theirs.debugSettings["SWIFT_VERSION"] = .value("6.0")
    }
    var merged = base
    merged.addSource(2)
    merged.addSource(3)
    return (base, ours, theirs, merged)
}

private func occurrences(of needle: String, in haystack: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}

@Suite("lfgit driver: project files")
struct ProjectDriverTests {
    private func runDriver(base: [UInt8], ours: [UInt8], theirs: [UInt8]) throws -> (code: Int32, merged: String, console: BufferConsole) {
        _ = try GitFixture() // isolates git configuration
        let box = Sandbox()
        let ancestor = box.write("O", bytes: base)
        let current = box.write("A", bytes: ours)
        let other = box.write("B", bytes: theirs)
        let console = BufferConsole()
        let code = try DriverCommand.parse([ancestor, current, other, "7", projectPath]).execute(console: console)
        return (code, box.readText(current), console)
    }

    @Test("independent changes to a project file merge cleanly")
    func clean() throws {
        let s = scenario(conflictingSetting: false)

        let result = try runDriver(base: s.base.bytes, ours: s.ours.bytes, theirs: s.theirs.bytes)

        #expect(result.code == 0)
        #expect(result.merged == s.merged.text)
    }

    @Test("a real disagreement leaves one small conflict and merges everything else")
    func smallConflict() throws {
        let s = scenario(conflictingSetting: true)

        let result = try runDriver(base: s.base.bytes, ours: s.ours.bytes, theirs: s.theirs.bytes)

        #expect(result.code == 1)
        #expect(occurrences(of: "<<<<<<< ", in: result.merged) == 1)
        #expect(result.merged.contains("<<<<<<< HEAD\n\t\t\t\tSWIFT_VERSION = 5.9;\n"))
        #expect(result.merged.contains("File2.swift in Sources */,\n\t\t\t\tC10000000000000000000003 /* File3.swift in Sources */,"))
    }

    @Test("a .pbxproj that is not in Xcode's format falls back to the line-based merge")
    func fallback() throws {
        let result = try runDriver(base: Array(text("a", "b", "c").utf8), ours: Array(text("A", "b", "c").utf8),
                                   theirs: Array(text("a", "b", "C").utf8))

        #expect(result.code == 0)
        #expect(result.merged == text("A", "b", "C"))
        #expect(result.console.errors.contains("line-based"))
    }
}

@Suite("lfgit remerge")
struct RemergeTests {
    private func conflictedRepository(conflictingSetting: Bool, extra: [ConflictSpec] = []) throws -> (GitFixture, ClassicProject) {
        let fixture = try GitFixture()
        let s = scenario(conflictingSetting: conflictingSetting)
        try fixture.makeConflicts([ConflictSpec(path: projectPath, base: s.base.bytes, ours: s.ours.bytes, theirs: s.theirs.bytes)] + extra)
        #expect(fixture.read(projectPath).contains("<<<<<<<"), "git's own merge should have conflicted")
        return (fixture, s.merged)
    }

    @Test("re-merges a conflicted project file from the index and stages it")
    func cleanAndStaged() throws {
        let (fixture, merged) = try conflictedRepository(conflictingSetting: false)
        let console = BufferConsole()

        let code = try RemergeCommand.parse(["-C", fixture.path, "--stage"]).execute(console: console)

        #expect(code == 0)
        #expect(fixture.read(projectPath) == merged.text)
        #expect(try fixture.conflictedPaths().isEmpty)
        #expect(console.output.contains("merged \(projectPath)"))
    }

    @Test("remaining conflicts are left as small blocks and the file is not staged")
    func remainingConflicts() throws {
        let (fixture, _) = try conflictedRepository(conflictingSetting: true)
        let console = BufferConsole()

        let code = try RemergeCommand.parse(["-C", fixture.path, "--stage", projectPath]).execute(console: console)

        #expect(code == 1)
        #expect(occurrences(of: "<<<<<<< ", in: fixture.read(projectPath)) == 1)
        #expect(try fixture.conflictedPaths() == [projectPath])
        #expect(console.output.contains("1 conflict"))
    }

    @Test("a file whose markers are gone is not overwritten unless --force")
    func protectsManualResolution() throws {
        let (fixture, merged) = try conflictedRepository(conflictingSetting: false)
        let manual = scenario(conflictingSetting: false).ours.text
        fixture.sandbox.write(projectPath, manual)
        let console = BufferConsole()

        let refused = try RemergeCommand.parse(["-C", fixture.path, projectPath]).execute(console: console)

        #expect(refused == 1)
        #expect(console.errors.contains("--force"))
        #expect(fixture.read(projectPath) == manual)

        let forced = try RemergeCommand.parse(["-C", fixture.path, "--force", projectPath]).execute(console: BufferConsole())
        #expect(forced == 0)
        #expect(fixture.read(projectPath) == merged.text)
    }

    @Test("the replaced working file is kept as .orig, so partial hand resolutions are never lost")
    func keepsBackup() throws {
        let (fixture, merged) = try conflictedRepository(conflictingSetting: false)
        let before = fixture.read(projectPath)
        let console = BufferConsole()

        let code = try RemergeCommand.parse(["-C", fixture.path]).execute(console: console)

        #expect(code == 0)
        #expect(fixture.read(projectPath) == merged.text)
        #expect(fixture.read(projectPath + ".orig") == before)
        #expect(console.output.contains(".orig"))
    }

    @Test("--no-backup skips the .orig copy")
    func noBackup() throws {
        let (fixture, _) = try conflictedRepository(conflictingSetting: false)

        _ = try RemergeCommand.parse(["-C", fixture.path, "--no-backup"]).execute(console: BufferConsole())

        #expect(!FileManager.default.fileExists(atPath: fixture.sandbox.path(projectPath + ".orig")))
    }

    @Test("--dry-run reports and writes nothing")
    func dryRun() throws {
        let (fixture, _) = try conflictedRepository(conflictingSetting: false)
        let before = fixture.read(projectPath)
        let console = BufferConsole()

        let code = try RemergeCommand.parse(["-C", fixture.path, "--dry-run"]).execute(console: console)

        #expect(code == 0)
        #expect(fixture.read(projectPath) == before)
        #expect(console.output.contains("would merge"))
    }

    @Test("without arguments only conflicted project files are re-merged")
    func onlyProjectFiles() throws {
        let (fixture, merged) = try conflictedRepository(conflictingSetting: false, extra: [.text("notes.txt")])

        let code = try RemergeCommand.parse(["-C", fixture.path, "--stage"]).execute(console: BufferConsole())

        #expect(code == 0)
        #expect(fixture.read(projectPath) == merged.text)
        #expect(try fixture.conflictedPaths() == ["notes.txt"])
    }

    @Test("other file types are refused with a hint")
    func otherFiles() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")])
        let console = BufferConsole()

        let code = try RemergeCommand.parse(["-C", fixture.path, "a.txt"]).execute(console: console)

        #expect(code == 1)
        #expect(console.errors.contains("lfgit resolve"))
    }

    @Test("a project file that is not unmerged in the index is reported")
    func notUnmerged() throws {
        let fixture = try GitFixture()
        fixture.sandbox.write(projectPath, scenario(conflictingSetting: false).base.text)
        try fixture.commitAll("init")
        let console = BufferConsole()

        let code = try RemergeCommand.parse(["-C", fixture.path, "--force", projectPath]).execute(console: console)

        #expect(code == 1)
        #expect(console.errors.contains("index"))
    }

    @Test("a file deleted on one side but kept by a modify/delete conflict gets a warning")
    func modifyDeleteWarning() throws {
        let fixture = try GitFixture()
        let base = ClassicProject.withSources([1, 2])
        var ours = base
        ours.addSource(3)
        var theirs = base
        theirs.removeFile(refID: ClassicProject.refID(1))
        theirs.addSource(4)
        var deleted = ConflictSpec(path: "App/File1.swift", base: "let a = 1\n", ours: "let a = 2\n", theirs: "")
        deleted.theirsDeletes = true
        try fixture.makeConflicts([ConflictSpec(path: projectPath, base: base.bytes, ours: ours.bytes, theirs: theirs.bytes), deleted])
        let console = BufferConsole()

        let code = try RemergeCommand.parse(["-C", fixture.path, projectPath]).execute(console: console)

        #expect(code == 0)
        #expect(console.errors.contains("File1.swift"))
        #expect(console.errors.contains("add it back"))
    }

    @Test("status marks project files and suggests remerge")
    func statusHint() throws {
        let (fixture, _) = try conflictedRepository(conflictingSetting: false)
        let console = BufferConsole()

        _ = try StatusCommand.parse(["-C", fixture.path]).execute(console: console)

        #expect(console.output.contains("pbxproj"))
        #expect(console.output.contains("lfgit remerge"))
    }
}
