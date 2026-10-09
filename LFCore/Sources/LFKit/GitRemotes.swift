import Foundation

public struct GitRemote: Sendable, Equatable, Identifiable {
    public let name: String
    public let fetchURL: String
    public let pushURL: String

    public var id: String { name }
}

extension GitClient {
    public func remotes() throws -> [GitRemote] {
        var fetch: [String: String] = [:]
        var push: [String: String] = [:]
        for line in String(decoding: try git.run(["remote", "-v"]).stdout, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[1].hasSuffix(" (fetch)") {
                fetch[parts[0]] = String(parts[1].dropLast(" (fetch)".count))
            } else if parts[1].hasSuffix(" (push)") {
                push[parts[0]] = String(parts[1].dropLast(" (push)".count))
            }
        }
        return fetch.keys.sorted().map { GitRemote(name: $0, fetchURL: fetch[$0] ?? "", pushURL: push[$0] ?? fetch[$0] ?? "") }
    }

    public func addRemote(_ name: String, url: String) throws {
        try requireName(name, what: "remote name")
        try requireName(url, what: "URL")
        try git.run(["remote", "add", name, url])
    }

    public func renameRemote(_ name: String, to newName: String) throws {
        try requireName(name, what: "remote name")
        try requireName(newName, what: "remote name")
        try git.run(["remote", "rename", name, newName])
    }

    public func setRemoteURL(_ name: String, url: String) throws {
        try requireName(name, what: "remote name")
        try requireName(url, what: "URL")
        try git.run(["remote", "set-url", name, url])
    }

    public func removeRemote(_ name: String) throws {
        try requireName(name, what: "remote name")
        try git.run(["remote", "remove", name])
    }

    /// Fetches one remote (all branches), removing tracking branches the remote no longer has.
    public func fetchRemote(_ name: String, timeout: TimeInterval? = defaultRemoteTimeout,
                            cancellation: GitCancellation? = nil) throws {
        try requireName(name, what: "remote name")
        try git.run(["fetch", "--prune", "-q", name], timeout: timeout, cancellation: cancellation)
    }

    public func pruneRemote(_ name: String, timeout: TimeInterval? = defaultRemoteTimeout,
                            cancellation: GitCancellation? = nil) throws {
        try requireName(name, what: "remote name")
        try git.run(["remote", "prune", name], timeout: timeout, cancellation: cancellation)
    }
}
