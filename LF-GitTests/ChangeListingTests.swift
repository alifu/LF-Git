import Foundation
import LFKit
import Testing
@testable import LF_Git

@Suite("Change listing")
struct ChangeListingTests {
    private static func listing(_ entries: [GitChange]) -> ChangeListing {
        var status = GitStatus()
        status.entries = entries
        return ChangeListing(status: status)
    }

    private static let partlyStaged = GitChange(path: "src/app.swift", kind: .ordinary, index: .modified, worktree: .modified)
    private static let onlyStaged = GitChange(path: "src/new.swift", kind: .ordinary, index: .added, worktree: .unmodified)
    private static let untracked = GitChange(path: "notes.txt", kind: .untracked, index: .untracked, worktree: .untracked)

    @Test("finds a file on the side it was asked for")
    func findsBySide() {
        let listing = Self.listing([Self.partlyStaged, Self.onlyStaged, Self.untracked])

        #expect(listing.change(path: "src/new.swift", staged: true) == Self.onlyStaged)
        #expect(listing.change(path: "src/app.swift", staged: true) == Self.partlyStaged)
        #expect(listing.change(path: "src/app.swift", staged: false) == Self.partlyStaged)
        #expect(listing.change(path: "notes.txt", staged: false) == Self.untracked)
    }

    @Test("returns nothing for a file that is not on that side")
    func missingSide() {
        let listing = Self.listing([Self.onlyStaged, Self.untracked])

        #expect(listing.change(path: "src/new.swift", staged: false) == nil)
        #expect(listing.change(path: "notes.txt", staged: true) == nil)
        #expect(listing.change(path: "absent.swift", staged: false) == nil)
    }

    @Test("an empty listing has nothing staged and nothing to find")
    func empty() {
        #expect(ChangeListing.empty.staged.isEmpty)
        #expect(ChangeListing.empty.change(path: "a", staged: true) == nil)
    }
}
