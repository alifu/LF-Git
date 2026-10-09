import Foundation
@testable import LFGitCLI
import LFKit
import LFTestSupport

/// A console that records output and replays scripted input.
final class BufferConsole: Console {
    var palette: TerminalPalette?
    private(set) var output = ""
    private(set) var errors = ""
    private(set) var prompts: [String] = []
    private var inputs: [String]

    init(inputs: [String] = [], palette: TerminalPalette? = nil) {
        self.inputs = inputs
        self.palette = palette
    }

    func write(_ text: String) { output += text }
    func writeError(_ text: String) { errors += text }

    func readLine(prompt: String) -> String? {
        prompts.append(prompt)
        return inputs.isEmpty ? nil : inputs.removeFirst()
    }
}
