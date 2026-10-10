import Testing
@testable import LF_Git

@MainActor
@Suite("Preview sample repository")
struct PreviewDataTests {
    @Test("the sample repository has data for every section a preview shows")
    func hasData() async throws {
        let repository = try #require(await PreviewData.repository())

        #expect(!repository.files.isEmpty, "a merge stopped on a conflict")
        #expect(repository.operation != nil)
        #expect(!repository.stashes.isEmpty)
        #expect(!repository.tags.isEmpty)
        #expect(!repository.remotes.isEmpty)
        #expect(repository.branches.count >= 2)
        #expect(!repository.reflog.isEmpty)
        #expect(!repository.history.commits.isEmpty)
    }
}
