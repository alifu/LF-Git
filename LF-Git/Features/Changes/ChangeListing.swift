import Foundation
import LFKit

/// The staged and unstaged lists with their folder trees. Building the trees for tens of thousands of files takes
/// seconds, so this is made once per refresh off the main thread instead of by every redraw of the sidebar.
nonisolated struct ChangeListing: Sendable {
    let staged: [GitChange]
    let unstaged: [GitChange]
    let stagedTree: [PathNode<GitChange>]
    let unstagedTree: [PathNode<GitChange>]

    static let empty = ChangeListing(status: GitStatus())

    init(status: GitStatus) {
        staged = status.staged
        unstaged = status.unstaged
        stagedTree = PathNode.build(staged, path: \.path)
        unstagedTree = PathNode.build(unstaged, path: \.path)
    }
}
