import Foundation

/// Command-line arguments the app understands (`lfgit open` passes them).
nonisolated struct LaunchOptions: Equatable, Sendable {
    /// Repository to open at launch.
    var repository: URL?
    /// File to select, relative to the repository.
    var file: String?

    static func parse(_ arguments: [String]) -> LaunchOptions {
        var options = LaunchOptions()
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            let next = arguments.index(after: index)
            let value = next < arguments.endIndex ? arguments[next] : nil
            switch argument {
            case "--repo" where value != nil:
                options.repository = URL(fileURLWithPath: value!)
                index = next
            case "--file" where value != nil:
                options.file = value
                index = next
            default:
                break
            }
            index = arguments.index(after: index)
        }
        return options
    }

    /// `lfgit://open?repo=<path>&file=<path>`, which `lfgit open` sends (it also reaches a running app).
    static func parse(url: URL) -> LaunchOptions? {
        guard url.scheme == "lfgit",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let repository = items.first(where: { $0.name == "repo" })?.value, !repository.isEmpty else {
            return nil
        }
        return LaunchOptions(
            repository: URL(fileURLWithPath: repository),
            file: items.first { $0.name == "file" }?.value
        )
    }
}
