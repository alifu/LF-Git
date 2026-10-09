import Foundation

/// A user-facing failure with a ready-to-print message.
struct CLIError: Error, LocalizedError, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { message }
    var errorDescription: String? { message }
}
