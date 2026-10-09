import LFCore

/// Build information about the linked LF-Git engine.
public enum LFKitInfo {
    /// Engine version, "MAJOR.MINOR.PATCH", read from the C library.
    public static let version = String(cString: lf_version_string())
}

/// Engine constants, read from the C library.
public enum LFDefaults {
    /// Length of conflict marker runs when no `conflict-marker-size` attribute is set.
    public static let markerSize = UInt32(LF_DEFAULT_MARKER_SIZE)
}
