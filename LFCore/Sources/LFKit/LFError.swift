import LFCore

/// A failing `lf_status` from the C engine, with its human-readable message.
public struct LFError: Error, Equatable, Sendable, CustomStringConvertible {
    public let status: lf_status
    public let message: String

    public init(status: lf_status) {
        self.status = status
        self.message = String(cString: lf_status_string(status))
    }

    public var description: String { message }

    /// Throws when `status` is anything other than `LF_OK`.
    public static func check(_ status: lf_status) throws(LFError) {
        guard status == LF_OK else {
            throw LFError(status: status)
        }
    }
}
