import Foundation
import LFKit
import LFTestSupport
import Testing
@testable import LF_Git

@MainActor
@Suite("Reopening and closing the repository")
struct AppModelRestoreTests {
    /// Defaults that die with the test, so the user's own are never read or written.
    private func isolatedDefaults() -> UserDefaults {
        let name = "lfgit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A repository outside the temporary folder is not possible in a test, so the app's "scratch" filter is
    /// satisfied by seeding the defaults the way a real run would have left them.
    private func seeded(last path: String?, recents: [String] = [], reopen: Bool? = nil) -> UserDefaults {
        let defaults = isolatedDefaults()
        if let path { defaults.set(path, forKey: "lastOpenedRepository") }
        defaults.set(recents, forKey: "recentRepositories")
        if let reopen { defaults.set(reopen, forKey: AppModel.reopenLastKey) }
        return defaults
    }

    @Test("the last repository comes back at launch")
    func restores() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let app = AppModel(defaults: seeded(last: fixture.path))

        app.restoreLastRepository(arguments: [])

        #expect(app.repository?.root.standardizedFileURL.path == fixture.directory.resolvingSymlinksInPath().path)
    }

    @Test("the setting and the launch argument both keep the dashboard")
    func notWhenTurnedOff() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")

        let off = AppModel(defaults: seeded(last: fixture.path, reopen: false))
        off.restoreLastRepository(arguments: [])
        let flagged = AppModel(defaults: seeded(last: fixture.path))
        flagged.restoreLastRepository(arguments: [AppModel.noRestoreArgument])

        #expect(off.repository == nil)
        #expect(flagged.repository == nil)
    }

    @Test("a repository that is gone is dropped with a note instead of an error")
    func missing() {
        let path = "/nonexistent/lfgit/gone-repo"
        let app = AppModel(defaults: seeded(last: path, recents: [path, "/other"]))

        app.restoreLastRepository(arguments: [])

        #expect(app.repository == nil)
        #expect(app.errorMessage == nil)
        #expect(app.restoreNote?.contains("gone-repo") == true)
        #expect(app.recentRepositories == ["/other"])
        #expect(app.lastOpenedRepository == nil)
    }

    @Test("closing returns to the dashboard and forgets the last repository")
    func closes() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let defaults = seeded(last: fixture.path)
        let app = AppModel(defaults: defaults)
        app.restoreLastRepository(arguments: [])
        #expect(app.repository != nil)

        let closed = app.close()

        #expect(closed)
        #expect(app.repository == nil)
        #expect(app.lastOpenedRepository == nil)
        #expect(defaults.string(forKey: "lastOpenedRepository") == nil)
    }

    @Test("a repository can be removed from the recents")
    func removeFromRecents() {
        let app = AppModel(defaults: seeded(last: "/a", recents: ["/a", "/b"]))

        app.removeFromRecents("/a")

        #expect(app.recentRepositories == ["/b"])
        #expect(app.lastOpenedRepository == nil)
    }

    @Test("clearing the recents also forgets the last repository, so nothing reopens at launch")
    func clearRecents() {
        let defaults = seeded(last: "/a", recents: ["/a", "/b"])
        let app = AppModel(defaults: defaults)

        app.clearRecentRepositories()

        #expect(app.recentRepositories.isEmpty)
        #expect(app.lastOpenedRepository == nil)
        #expect(defaults.string(forKey: "lastOpenedRepository") == nil)
    }

    @Test("a closed repository ignores a refresh that was still running")
    func shutDownDropsLateRefresh() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let model = try RepositoryModel.open(at: fixture.directory)

        let refresh = Task { await model.refresh() }
        await Task.yield() // the refresh is now waiting for git
        model.shutDown()
        await refresh.value

        #expect(model.status.branch == nil)
    }
}
