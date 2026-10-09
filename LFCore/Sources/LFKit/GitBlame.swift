import Foundation

public struct GitBlameLine: Sendable, Equatable, Identifiable {
    public let number: Int
    public let hash: String
    public let author: String
    public let date: Date
    public let summary: String
    public let content: String

    public var id: Int { number }
    public var shortHash: String { String(hash.prefix(7)) }
    /// Not committed yet.
    public var isUncommitted: Bool { hash.allSatisfy { $0 == "0" } }
}

extension GitClient {
    /// Who last changed each line of a file, as of `revision` (the work tree when nil).
    public func blame(path: String, revision: String? = nil, ignoreWhitespace: Bool = false) throws -> [GitBlameLine] {
        if let revision { try requireName(revision, what: "revision") }
        var arguments = ["blame", "--porcelain"]
        if ignoreWhitespace { arguments.append("-w") }
        if let revision { arguments.append(revision) }
        arguments += ["--", path]
        return Self.parseBlame(try git.run(arguments).stdout)
    }

    static func parseBlame(_ output: Data) -> [GitBlameLine] {
        struct Meta { var author = "", summary = ""; var time: TimeInterval = 0 }
        var metas: [String: Meta] = [:]
        var lines: [GitBlameLine] = []
        var hash = "", number = 0
        for rawLine in output.split(separator: 0x0A, omittingEmptySubsequences: false) {
            let line = String(decoding: rawLine, as: UTF8.self)
            if line.hasPrefix("\t") {
                let meta = metas[hash] ?? Meta()
                lines.append(GitBlameLine(number: number, hash: hash, author: meta.author,
                                          date: Date(timeIntervalSince1970: meta.time), summary: meta.summary,
                                          content: String(line.dropFirst())))
                continue
            }
            let parts = line.split(separator: " ", maxSplits: 3).map(String.init)
            if parts.count >= 3, parts[0].count == 40, parts[0].allSatisfy(\.isHexDigit), let final = Int(parts[2]) {
                hash = parts[0]
                number = final
                if metas[hash] == nil { metas[hash] = Meta() }
            } else if line.hasPrefix("author ") {
                metas[hash]?.author = String(line.dropFirst("author ".count))
            } else if line.hasPrefix("author-time ") {
                metas[hash]?.time = TimeInterval(line.dropFirst("author-time ".count)) ?? 0
            } else if line.hasPrefix("summary ") {
                metas[hash]?.summary = String(line.dropFirst("summary ".count))
            }
        }
        return lines
    }
}
