import LFCore

/// Build information about the linked LF-Git engine.
public enum LFKitInfo {
    /// Engine version, "MAJOR.MINOR.PATCH", read from the C library.
    public static let version = String(cString: lf_version_string())
}
