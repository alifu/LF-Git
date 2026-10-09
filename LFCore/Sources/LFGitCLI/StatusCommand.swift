import ArgumentParser
import Foundation
import LFKit

func plural(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
}

func finish(_ code: Int32) throws {
    if code != 0 {
        throw ExitCode(code)
    }
}

public struct StatusCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "List conflicted files with their type and number of conflicts."
    )

    @OptionGroup public var global: GlobalOptions

    public init() {}

    private enum Kind {
        case text(conflicts: Int)
        case binary
        case unreadable(String)
    }

    public func run() throws {
        try finish(execute(console: StandardConsole()))
    }

    public func execute(console: Console) throws -> Int32 {
        let git = global.git
        let root = try git.repositoryRoot()
        let paths = try Git(directory: root).conflictedPaths()
        guard !paths.isEmpty else {
            console.line("No conflicted files.")
            return 0
        }
        console.line(plural(paths.count, "conflicted file"))
        let rows = paths.map { (path: $0, kind: describe(root.appendingPathComponent($0).path, git: git)) }
        let width = rows.map(\.path.count).max() ?? 0
        for row in rows {
            console.line(format(row.path, kind: row.kind, width: width, palette: console.palette,
                                size: fileSize(root.appendingPathComponent(row.path).path)))
        }
        return 0
    }

    private func describe(_ absolutePath: String, git: Git) -> Kind {
        do {
            if try LFFileProbe(path: absolutePath).kind == .binary {
                return .binary
            }
            let document = try LFDocument(path: absolutePath, markerSize: git.markerSize(forPath: absolutePath))
            return .text(conflicts: document.info.conflictCount)
        } catch {
            return .unreadable("\(error)")
        }
    }

    private func fileSize(_ path: String) -> String {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? nil
        return bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "-"
    }

    private func format(_ path: String, kind: Kind, width: Int, palette: TerminalPalette?, size: String) -> String {
        let padded = path.padding(toLength: width, withPad: " ", startingAt: 0)
        func tint(_ text: String, _ color: TerminalPalette.RGB?) -> String {
            guard let palette, let color else { return text }
            return palette.paint(text, color)
        }
        switch kind {
        case .text(let conflicts):
            let note = conflicts == 0 ? "no markers" : plural(conflicts, "conflict")
            return "  U  \(padded)  text    \(tint(note, conflicts == 0 ? palette?.muted : palette?.danger))  \(size)"
        case .binary:
            return "  U  \(padded)  \(tint("binary", palette?.muted))  \(size)"
        case .unreadable(let reason):
            return "  U  \(padded)  \(tint("unreadable: \(reason)", palette?.danger))"
        }
    }
}
