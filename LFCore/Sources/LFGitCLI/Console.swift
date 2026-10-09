import Darwin
import Foundation

/// Terminal input/output seam, so commands can be tested without a terminal.
public protocol Console: AnyObject {
    /// Colours to use, or nil for plain text.
    var palette: TerminalPalette? { get }
    func write(_ text: String)
    func writeError(_ text: String)
    /// Shows `prompt` (without a newline) and reads one line; nil at end of input.
    func readLine(prompt: String) -> String?
}

extension Console {
    func line(_ text: String = "") {
        write(text + "\n")
    }

    func errorLine(_ text: String) {
        writeError(text + "\n")
    }
}

public final class StandardConsole: Console {
    public let palette: TerminalPalette?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        palette = TerminalPalette.detect(environment: environment, isTerminal: isatty(STDOUT_FILENO) != 0)
    }

    public func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    public func writeError(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }

    public func readLine(prompt: String) -> String? {
        write(prompt)
        return Swift.readLine()
    }
}
