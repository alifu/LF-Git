import Foundation

public struct GitTag: Sendable, Equatable, Identifiable {
    public let name: String
    /// The commit the tag points at.
    public let commit: String
    public let isAnnotated: Bool
    /// First line of an annotated tag's message.
    public let message: String?
    public let date: Date

    public var id: String { name }
}

public struct GitReflogEntry: Sendable, Equatable, Identifiable {
    public let hash: String
    /// `HEAD@{3}`
    public let selector: String
    public let message: String
    public let date: Date

    public var id: String { selector }
    public var shortHash: String { String(hash.prefix(7)) }
}

extension GitClient {
    // MARK: Tags

    public func tags() throws -> [GitTag] {
        let format = ["%(refname:short)", "%(objecttype)", "%(objectname)", "%(*objectname)", "%(contents:subject)",
                      "%(creatordate:unix)"].joined(separator: "%1f")
        let result = try git.run(["for-each-ref", "--sort=-creatordate", "--format=\(format)", "refs/tags"])
        return String(decoding: result.stdout, as: UTF8.self).split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 6 else { return nil }
            let annotated = fields[1] == "tag"
            return GitTag(name: fields[0], commit: annotated ? fields[3] : fields[2], isAnnotated: annotated,
                          message: annotated ? fields[4] : nil, date: Date(timeIntervalSince1970: TimeInterval(fields[5]) ?? 0))
        }
    }

    /// A lightweight tag, or an annotated one when `message` is given.
    public func createTag(_ name: String, at revision: String? = nil, message: String? = nil) throws {
        try requireName(name, what: "tag name")
        if let revision { try requireName(revision, what: "revision") }
        var arguments = ["tag"]
        if let message, !message.isEmpty { arguments += ["-a", "-m", message] }
        arguments.append(name)
        if let revision { arguments.append(revision) }
        try git.run(arguments)
    }

    public func deleteTag(_ name: String) throws {
        try requireName(name, what: "tag name")
        try git.run(["tag", "-d", name])
    }

    public func pushTag(_ name: String, to remote: String, timeout: TimeInterval? = defaultRemoteTimeout,
                        cancellation: GitCancellation? = nil) throws {
        try requireName(name, what: "tag name")
        try requireName(remote, what: "remote name")
        try git.run(["push", "-q", remote, "refs/tags/\(name)"], timeout: timeout, cancellation: cancellation)
    }

    public func deleteRemoteTag(_ name: String, on remote: String, timeout: TimeInterval? = defaultRemoteTimeout,
                                cancellation: GitCancellation? = nil) throws {
        try requireName(name, what: "tag name")
        try requireName(remote, what: "remote name")
        try git.run(["push", "-q", remote, "--delete", "refs/tags/\(name)"], timeout: timeout, cancellation: cancellation)
    }

    // MARK: Reflog

    /// Where HEAD has been, newest first.
    public func reflog(maxCount: Int? = nil) throws -> [GitReflogEntry] {
        var arguments = ["log", "-g", "-z", "--format=%H%x1f%gd%x1f%at%x1f%gs"]
        if let maxCount { arguments.append("--max-count=\(maxCount)") }
        arguments.append("HEAD")
        let result = try git.run(arguments, allowedStatuses: [0, 128])
        guard result.status == 0 else { return [] } // no commits yet
        return result.stdout.split(separator: 0, omittingEmptySubsequences: true).compactMap { record in
            let fields = String(decoding: record, as: UTF8.self).components(separatedBy: "\u{1F}")
            guard fields.count >= 4 else { return nil }
            return GitReflogEntry(hash: fields[0], selector: fields[1], message: fields[3...].joined(separator: "\u{1F}"),
                                  date: Date(timeIntervalSince1970: TimeInterval(fields[2]) ?? 0))
        }
    }
}
