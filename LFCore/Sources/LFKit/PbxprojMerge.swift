import LFCore

/// The outcome of a semantic merge.
public struct LFMergeResult: Sendable, Equatable {
    public let bytes: [UInt8]
    /// Conflict blocks left in `bytes` (0 means the merge is complete).
    public let conflictCount: Int
    /// Objects changed on both sides that were combined field by field without conflict.
    public let mergedObjectCount: Int

    public var isClean: Bool { conflictCount == 0 }
}

/// Object-level three-way merge of Xcode `project.pbxproj` files (see `lf_pbx_merge`).
public enum PbxprojMerge {
    public struct Labels: Sendable, Equatable {
        public let current: String
        public let base: String
        public let incoming: String

        public init(current: String, base: String, incoming: String) {
            self.current = current
            self.base = base
            self.incoming = incoming
        }

        public static let standard = Labels(current: "HEAD", base: "base", incoming: "incoming")
    }

    /// Throws `LF_ERR_UNSUPPORTED` when an input is not a project file in Xcode's format;
    /// callers should then fall back to a line-based merge.
    public static func merge(
        base: [UInt8], ours: [UInt8], theirs: [UInt8], markerSize: Int = Int(LF_DEFAULT_MARKER_SIZE),
        includeBase: Bool = true, labels: Labels = .standard
    ) throws(LFError) -> LFMergeResult {
        var raw = lf_merge_result()
        let status = base.withUnsafeBufferPointer { b in
            ours.withUnsafeBufferPointer { o in
                theirs.withUnsafeBufferPointer { t in
                    labels.current.withCString { current in
                        labels.base.withCString { baseLabel in
                            labels.incoming.withCString { incoming in
                                var options = lf_merge_options(
                                    marker_size: UInt32(clamping: markerSize), include_base: includeBase ? 1 : 0,
                                    current_label: current, base_label: baseLabel, incoming_label: incoming
                                )
                                return lf_pbx_merge(
                                    b.baseAddress, b.count, o.baseAddress, o.count, t.baseAddress, t.count, &options, &raw
                                )
                            }
                        }
                    }
                }
            }
        }
        try LFError.check(status)
        defer { lf_merge_result_free(&raw) }
        let bytes = raw.data.map { Array(UnsafeBufferPointer(start: $0, count: raw.length)) } ?? []
        return LFMergeResult(
            bytes: bytes, conflictCount: Int(raw.conflict_count), mergedObjectCount: Int(raw.merged_object_count)
        )
    }
}
