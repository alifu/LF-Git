import Foundation
import LFKit
import Testing
@testable import LF_Git

@MainActor
@Suite("Hook runs")
struct HookRunTests {
    @Test("output chunks are collected and the run passes")
    func collectsOutput() {
        let store = HookRunStore()
        let id = store.begin(title: "Push")

        store.append("lint… ", to: id)
        store.append("ok\n", to: id)
        store.finish(id, error: nil)

        #expect(store.latest?.text == "lint… ok\n")
        #expect(store.latest?.state == .passed)
        #expect(store.latest?.duration != nil)
    }

    @Test("a failed command marks the run failed")
    func failure() {
        let store = HookRunStore()
        let id = store.begin(title: "Push")

        store.finish(id, error: GitError.cancelled)

        #expect(store.latest?.state == .failed("cancelled"))
    }

    @Test("colour codes and carriage returns are cleaned")
    func cleaning() {
        #expect(HookRun.stripControlSequences("\u{1B}[31mfail\u{1B}[0m\r50%\r100%\r\n") == "fail\n50%\n100%\n")
    }

    @Test("a CRLF or a colour code split across chunks is cleaned like a whole one")
    func splitAcrossChunks() {
        let run = HookRun(id: 1, title: "Push")
            .appending("one\r")
            .appending("\ntwo \u{1B}[3")
            .appending("1mred\u{1B}[0m\n")

        #expect(run.text == "one\ntwo red\n")
    }

    @Test("a held-back carriage return is written when the run ends")
    func heldBackFlushedOnFinish() {
        let run = HookRun(id: 1, title: "Push").appending("50%\r").finished(.passed)

        #expect(run.text == "50%\n")
    }

    @Test("output past the limit is cut and flagged")
    func truncation() {
        let run = HookRun(id: 1, title: "Push")
            .appending(String(repeating: "x", count: HookRun.characterLimit))
            .appending("more")

        #expect(run.text.count == HookRun.characterLimit)
        #expect(run.isTruncated)
    }

    @Test("only the newest runs are kept, and clearing keeps a running one")
    func capacity() {
        let store = HookRunStore()
        for _ in 0..<(HookRunStore.capacity + 5) { store.finish(store.begin(title: "Push"), error: nil) }
        let running = store.begin(title: "Commit")

        #expect(store.runs.count == HookRunStore.capacity)
        store.clear()
        #expect(store.runs.map(\.id) == [running])
    }

    @Test("commit hooks default to running and skipping them is kept per repository")
    func commitPreferences() throws {
        let defaults = try #require(UserDefaults(suiteName: "HookRunTests-\(UUID().uuidString)"))
        let preferences = HookPreferences(defaults: defaults)
        let first = URL(fileURLWithPath: "/tmp/repo-one")
        #expect(!preferences.skipsCommitHooks(in: first))

        preferences.setSkipsCommitHooks(true, in: first)

        #expect(preferences.skipsCommitHooks(in: first))
        #expect(!preferences.skipsCommitHooks(in: URL(fileURLWithPath: "/tmp/repo-two")))
    }

    @Test("push hooks default to on and the choice is kept per repository")
    func preferences() throws {
        let defaults = try #require(UserDefaults(suiteName: "HookRunTests-\(UUID().uuidString)"))
        let preferences = HookPreferences(defaults: defaults)
        let first = URL(fileURLWithPath: "/tmp/repo-one")
        let second = URL(fileURLWithPath: "/tmp/repo-two")
        #expect(preferences.runsPushHooks(in: first))

        preferences.setRunsPushHooks(false, in: first)

        #expect(!preferences.runsPushHooks(in: first))
        #expect(preferences.runsPushHooks(in: second))
        preferences.setRunsPushHooks(true, in: first)
        #expect(preferences.runsPushHooks(in: first))
    }
}
