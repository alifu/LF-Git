import Foundation

public struct GitWorktree: Sendable, Equatable, Identifiable {
    public let path: String
    public let head: String
    /// nil when HEAD is detached.
    public let branch: String?
    public let isMain: Bool
    public let isLocked: Bool
    public let isPrunable: Bool

    public var id: String { path }
}

public enum SubmoduleState: Sendable, Equatable {
    case upToDate
    case notInitialized
    /// Checked out at a different commit than the superproject records.
    case modified
    case conflicted
}

public struct GitSubmodule: Sendable, Equatable, Identifiable {
    public let name: String
    public let path: String
    public let url: String
    public let hash: String
    public let state: SubmoduleState

    public var id: String { path }
}

extension GitClient {
    // MARK: Worktrees

    public func worktrees() throws -> [GitWorktree] {
        let text = String(decoding: try git.run(["worktree", "list", "--porcelain"]).stdout, as: UTF8.self)
        var result: [GitWorktree] = []
        for block in text.components(separatedBy: "\n\n") where !block.isEmpty {
            var path = "", head = "", branch: String?, locked = false, prunable = false
            for line in block.split(separator: "\n") {
                if line.hasPrefix("worktree ") { path = String(line.dropFirst("worktree ".count)) }
                else if line.hasPrefix("HEAD ") { head = String(line.dropFirst("HEAD ".count)) }
                else if line.hasPrefix("branch ") { branch = String(line.dropFirst("branch ".count)).replacingOccurrences(of: "refs/heads/", with: "") }
                else if line.hasPrefix("locked") { locked = true }
                else if line.hasPrefix("prunable") { prunable = true }
            }
            guard !path.isEmpty else { continue }
            result.append(GitWorktree(path: path, head: head, branch: branch, isMain: result.isEmpty, isLocked: locked, isPrunable: prunable))
        }
        return result
    }

    private func requireAbsolute(_ path: String) throws {
        guard path.hasPrefix("/") else { throw GitClientError.unsupported("'\(path)' is not an absolute path.") }
    }

    /// Checks out `branch` in a new directory; with `createBranch` the branch is created from HEAD.
    public func addWorktree(at path: String, branch: String, createBranch: Bool) throws {
        try requireAbsolute(path)
        try requireName(branch)
        try git.run(createBranch ? ["worktree", "add", "-b", branch, path] : ["worktree", "add", path, branch])
    }

    public func removeWorktree(at path: String, force: Bool = false) throws {
        try requireAbsolute(path)
        try git.run(["worktree", "remove"] + (force ? ["--force"] : []) + [path])
    }

    public func pruneWorktrees() throws {
        try git.run(["worktree", "prune"])
    }

    // MARK: Submodules

    public func submodules() throws -> [GitSubmodule] {
        let (names, urls) = try submoduleConfiguration()
        let status = try git.run(["submodule", "status"]).stdout
        return String(decoding: status, as: UTF8.self).split(separator: "\n").compactMap { line in
            guard let marker = line.first else { return nil }
            let parts = line.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let hash = parts[0]
            var path = parts[1]
            if let describe = path.range(of: " (", options: .backwards), path.hasSuffix(")") {
                path = String(path[..<describe.lowerBound])
            }
            let state: SubmoduleState = switch marker {
            case "-": .notInitialized
            case "+": .modified
            case "U": .conflicted
            default: .upToDate
            }
            return GitSubmodule(name: names[path] ?? path, path: path, url: urls[path] ?? "", hash: hash, state: state)
        }
    }

    /// path -> name and path -> URL, from `.gitmodules`.
    private func submoduleConfiguration() throws -> (names: [String: String], urls: [String: String]) {
        let result = try git.run(["config", "-z", "-f", ".gitmodules", "--get-regexp", #"^submodule\..*\.(path|url)$"#],
                                 allowedStatuses: [0, 1, 128])
        guard result.status == 0 else { return ([:], [:]) }
        var pathByName: [String: String] = [:]
        var urlByName: [String: String] = [:]
        for record in result.stdout.split(separator: 0) {
            let entry = String(decoding: record, as: UTF8.self)
            guard let newline = entry.firstIndex(of: "\n") else { continue }
            let key = String(entry[..<newline]), value = String(entry[entry.index(after: newline)...])
            let body = key.dropFirst("submodule.".count)
            if body.hasSuffix(".path") { pathByName[String(body.dropLast(".path".count))] = value }
            else if body.hasSuffix(".url") { urlByName[String(body.dropLast(".url".count))] = value }
        }
        var names: [String: String] = [:], urls: [String: String] = [:]
        for (name, path) in pathByName {
            names[path] = name
            urls[path] = urlByName[name]
        }
        return (names, urls)
    }

    public func addSubmodule(url: String, path: String, timeout: TimeInterval? = defaultRemoteTimeout,
                             cancellation: GitCancellation? = nil) throws {
        try requireName(url, what: "URL")
        try requireName(path, what: "path")
        try git.run(["submodule", "add", "--", url, path], timeout: timeout, cancellation: cancellation)
    }

    /// Initializes and checks out the commit the superproject records; empty `paths` means all.
    public func updateSubmodules(paths: [String] = [], recursive: Bool = true, timeout: TimeInterval? = defaultRemoteTimeout,
                                 cancellation: GitCancellation? = nil) throws {
        var arguments = ["submodule", "update", "--init"]
        if recursive { arguments.append("--recursive") }
        if !paths.isEmpty { arguments += ["--"] + paths }
        try git.run(arguments, timeout: timeout, cancellation: cancellation)
    }

    /// Removes the submodule from the work tree, the index, `.gitmodules` and `.git/modules`.
    public func removeSubmodule(path: String) throws {
        try requireName(path, what: "path")
        let name = try submoduleConfiguration().names[path] ?? path
        guard !name.contains("..") else { throw GitClientError.unsupported("Unsafe submodule name '\(name)'.") }
        try git.run(["submodule", "deinit", "-f", "--", path])
        try git.run(["rm", "-f", "--", path])
        let modules = try git.run(["rev-parse", "--git-path", "modules/\(name)"]).text
        let url = modules.hasPrefix("/") ? URL(fileURLWithPath: modules) : git.directory.appendingPathComponent(modules)
        try? FileManager.default.removeItem(at: url)
    }
}
