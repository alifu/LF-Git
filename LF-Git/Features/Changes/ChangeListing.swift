import Foundation
import LFKit

/// The staged and unstaged lists with their folder trees. Building the trees for tens of thousands of files takes
/// seconds, so this is made once per refresh off the main thread instead of by every redraw of the sidebar.
///
/// Cost: built in O(n·d + n log n) for n files of depth d; afterwards every lookup by path is O(1), and the lists are
/// stored, so `staged.isEmpty` is O(1) (unlike `GitStatus.staged`, which filters every entry on each call).
nonisolated struct ChangeListing: Sendable {
    let staged: [GitChange]
    let unstaged: [GitChange]
    let stagedTree: [PathNode<GitChange>]
    let unstagedTree: [PathNode<GitChange>]
    private let stagedByPath: [String: GitChange]
    private let unstagedByPath: [String: GitChange]

    static let empty = ChangeListing(status: GitStatus())

    init(status: GitStatus) {
        staged = status.staged
        unstaged = status.unstaged
        stagedTree = PathNode.build(staged, path: \.path)
        unstagedTree = PathNode.build(unstaged, path: \.path)
        stagedByPath = Self.index(staged)
        unstagedByPath = Self.index(unstaged)
    }

    /// The change at `path` on the staged or the unstaged side, in O(1).
    func change(path: String, staged: Bool) -> GitChange? {
        staged ? stagedByPath[path] : unstagedByPath[path]
    }

    /// `git status` lists a path once per side; should it ever repeat one, the first entry wins, as the old linear
    /// search did.
    private static func index(_ changes: [GitChange]) -> [String: GitChange] {
        Dictionary(changes.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
