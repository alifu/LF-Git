import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Git helper")
struct GitTests {
    @Test("a plain directory is not a repository")
    func notARepository() {
        let box = Sandbox()

        #expect(throws: GitError.self) { try Git(directory: box.root).repositoryRoot() }
    }

    @Test("conflicted paths are listed relative to the repository root")
    func conflictedPaths() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt"), .text("sub/b.txt")])

        let paths = try fixture.git.conflictedPaths()

        #expect(paths.sorted() == ["a.txt", "sub/b.txt"])
    }

    @Test("a clean repository has no conflicted paths")
    func noConflicts() throws {
        let fixture = try GitFixture()
        fixture.sandbox.write("a.txt", "hello\n")
        try fixture.commitAll("init")

        #expect(try fixture.git.conflictedPaths().isEmpty)
    }

    @Test("marker size defaults to 7 and follows the conflict-marker-size attribute")
    func markerSize() throws {
        let fixture = try GitFixture()
        fixture.sandbox.write(".gitattributes", "*.long conflict-marker-size=9\n")
        let short = fixture.sandbox.write("a.txt", "x\n")
        let long = fixture.sandbox.write("b.long", "x\n")

        #expect(fixture.git.markerSize(forPath: short) == 7)
        #expect(fixture.git.markerSize(forPath: long) == 9)
    }

    @Test("a failing git command reports its arguments and stderr")
    func failureCarriesContext() throws {
        let fixture = try GitFixture()

        do {
            try fixture.git.run(["checkout", "no-such-branch"])
            Issue.record("expected a failure")
        } catch {
            #expect(error.description.contains("checkout"))
            #expect(error.description.contains("no-such-branch"))
        }
    }
}
