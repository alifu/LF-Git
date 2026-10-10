import Foundation
import LFKit
import LFTestSupport
import Testing
@testable import LF_Git

@MainActor
@Suite("Log panel events")
struct ActivityLogTests {
    private func open(_ fixture: GitFixture) async throws -> RepositoryModel {
        let model = try RepositoryModel.open(at: fixture.directory)
        await model.refresh()
        return model
    }

    @Test("an action is logged when it starts and when it finishes")
    func startAndFinish() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let model = try await open(fixture)

        try await model.createBranch("topic")

        let texts = model.activity.filter { $0.kind == .action }.map(\.text)
        #expect(texts == ["Started: Creating topic", "Finished: Creating topic"])
        #expect(model.activity.first { $0.text == "Finished: Creating topic" }?.duration != nil)
    }

    @Test("a failing action is logged as a problem with git's reason")
    func failure() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let model = try await open(fixture)

        await #expect(throws: (any Error).self) { try await model.switchBranch("missing") }

        let problem = try #require(model.activity.last { $0.kind == .error })
        #expect(problem.text.hasPrefix("Failed: Switching to missing"))
        #expect(problem.isProblem)
        #expect(model.activity.contains { $0.kind == .git && !$0.succeeded })
    }

    @Test("a cancelled action is information, not an error")
    func cancelled() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let model = try await open(fixture)
        let running = Task {
            try await model.perform("Napping…", cancellable: true) { client, token in
                try client.git.run(["-c", "alias.nap=!sleep 30", "nap"], cancellation: token)
            }
        }
        try await Task.sleep(for: .milliseconds(500))
        model.cancelBusy()
        _ = try? await running.value

        #expect(model.activity.contains { $0.kind == .info && $0.text == "Cancelled: Napping" })
        #expect(!model.activity.contains { $0.kind == .error })
    }

    @Test("filters pick git lines, actions or problems, and the log can be cleared")
    func filtersAndClear() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let model = try await open(fixture)
        try await model.createBranch("topic")
        model.record(.error, "Failed: something", succeeded: false)

        #expect(model.activity.filter(LogFilter.git.includes).allSatisfy { $0.kind == .git })
        #expect(model.activity.filter(LogFilter.actions.includes).count == 2)
        #expect(model.activity.filter(LogFilter.problems.includes).map(\.text) == ["Failed: something"])
        #expect(LogEvent.transcript(model.activity).contains("Started: Creating topic"))

        model.clearActivity()
        #expect(model.activity.isEmpty)
    }

    @Test("the log keeps only the newest lines")
    func capacity() async throws {
        let fixture = try GitFixture()
        let model = try await open(fixture)
        for index in 0..<600 { model.record(.info, "line \(index)") }

        #expect(model.activity.count == 500)
        #expect(model.activity.last?.text == "line 599")
    }
}
