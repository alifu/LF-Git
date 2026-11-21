import Foundation
import LFKit
import LFTestSupport
import Testing
@testable import LF_Git

@MainActor
@Suite("Push with hooks")
struct HookPushModelTests {
    /// A repo with an origin, one unpushed commit and a `pre-push` hook that prints and then fails.
    private func repositoryWithFailingHook() async throws -> (GitFixture, RepositoryModel) {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "one")
        _ = try fixture.addOrigin()
        try fixture.commit("a.txt", "2\n", message: "two")
        let hook = fixture.directory.appendingPathComponent(".git/hooks/pre-push")
        try "#!/bin/sh\necho 'guardrail: secrets found'\nexit 1\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        let model = try RepositoryModel.open(at: fixture.directory)
        await model.refresh()
        return (fixture, model)
    }

    @Test("a rejecting pre-push hook shows its output and fails the run")
    func rejectingHook() async throws {
        let (fixture, model) = try await repositoryWithFailingHook()
        defer { withExtendedLifetime(fixture) {} }
        #expect(model.hasPrePushHook)

        await #expect(throws: (any Error).self) { try await model.push() }

        let run = try #require(model.hooks.latest)
        #expect(run.text.contains("guardrail: secrets found"))
        guard case .failed = run.state else { Issue.record("expected a failed run, got \(run.state)"); return }
        #expect(model.showsHooksPanel)
        #expect(model.status.ahead == 1)
    }

    @Test("with hooks off the push goes out, no run is recorded and the log says so")
    func hooksOff() async throws {
        let (fixture, model) = try await repositoryWithFailingHook()
        defer { withExtendedLifetime(fixture) {} }
        model.runsPushHooks = false
        defer { model.runsPushHooks = true }

        try await model.push()

        #expect(model.hooks.runs.isEmpty)
        #expect(model.status.ahead == 0)
        #expect(model.activity.contains { $0.text.contains("hooks disabled") })
    }

    @Test("without a pre-push hook nothing is recorded")
    func noHook() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "one")
        _ = try fixture.addOrigin()
        try fixture.commit("a.txt", "2\n", message: "two")
        let model = try RepositoryModel.open(at: fixture.directory)
        await model.refresh()

        try await model.push()

        #expect(!model.hasPrePushHook)
        #expect(model.hooks.runs.isEmpty)
        #expect(!model.showsHooksPanel)
    }
}
