import LFCore

/// A failing `lf_status` from the C engine, with the engine's explanation when it has one.
public struct LFError: Error, Equatable, Sendable, CustomStringConvertible {
    public let status: lf_status
    public let message: String

    public init(status: lf_status, detail: String? = nil) {
        self.status = status
        if let detail, !detail.isEmpty {
            message = detail
        } else {
            message = String(cString: lf_status_string(status))
        }
    }

    public var description: String { message }

    /// Throws when `status` is anything other than `LF_OK`, capturing `lf_last_error()` on this thread.
    public static func check(_ status: lf_status) throws(LFError) {
        guard status == LF_OK else {
            throw LFError(status: status, detail: String(cString: lf_last_error()))
        }
    }
}
