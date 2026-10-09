import LFKit

/// Bisect, driven from the commit menu and the banner.
extension RepositoryModel {
    /// Marks a commit as bad or good. The search starts once both are known; while it runs, marks go to git.
    func markForBisect(_ mark: BisectMark, commit: GitCommit) async throws {
        if isBisecting {
            try await perform("Bisecting…") { client, _ in _ = try client.bisectMark(mark) }
            return
        }
        switch mark {
        case .bad: bisectBad = commit
        case .good: bisectGood = commit
        case .skip: return
        }
        guard let bad = bisectBad, let good = bisectGood else { return }
        try await perform("Starting bisect…") { client, _ in _ = try client.bisectStart(bad: bad.hash, good: good.hash) }
        bisectBad = nil
        bisectGood = nil
    }

    func answerBisect(_ mark: BisectMark) async throws {
        try await perform("Bisecting…") { client, _ in _ = try client.bisectMark(mark) }
    }

    func resetBisect() async throws {
        try await perform("Ending bisect…") { client, _ in try client.bisectReset() }
        bisectBad = nil
        bisectGood = nil
    }
}
