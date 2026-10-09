import Foundation

/// Opens the user's editor ($VISUAL, then $EDITOR, then vi) on a temporary file.
public enum ExternalEditor {
    /// Returns the edited bytes, or nil if the editor failed or could not be started.
    public static func edit(_ initial: [UInt8]) -> [UInt8]? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lfgit-edit-\(UUID().uuidString).txt")
        guard FileManager.default.createFile(atPath: file.path, contents: Data(initial)) else {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: file) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The editor setting may contain arguments ("code --wait"), so let the shell split it.
        process.arguments = ["-c", "${VISUAL:-${EDITOR:-vi}} \"$1\"", "lfgit-editor", file.path]
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, let edited = FileManager.default.contents(atPath: file.path) else {
            return nil
        }
        return Array(edited)
    }
}
