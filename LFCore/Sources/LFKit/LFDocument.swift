import LFCore

/// A text file with conflict markers, opened for resolution.
///
/// Not thread-safe: use one document from one thread (or actor) at a time.
public final class LFDocument {
    private let handle: OpaquePointer

    public init(path: String, markerSize: Int = Int(LF_DEFAULT_MARKER_SIZE)) throws(LFError) {
        var options = lf_open_options(marker_size: UInt32(clamping: markerSize))
        var opened: OpaquePointer?
        let status = path.withCString { lf_doc_open($0, &options, &opened) }
        try LFError.check(status)
        guard let opened else {
            throw LFError(status: LF_ERR_IO, detail: "engine returned no document for '\(path)'")
        }
        handle = opened
    }

    deinit {
        lf_doc_close(handle)
    }

    public var info: LFDocumentInfo {
        var raw = lf_doc_info()
        // lf_doc_get_info only fails for null arguments, which cannot happen here.
        _ = lf_doc_get_info(handle, &raw)
        return LFDocumentInfo(raw)
    }

    public var conflictCount: Int { info.conflictCount }

    public func conflict(at index: Int) throws(LFError) -> LFConflict {
        guard index >= 0 else {
            throw LFError(status: LF_ERR_INVALID_ARGUMENT, detail: "conflict index \(index) is negative")
        }
        var raw = lf_conflict_info()
        try LFError.check(lf_doc_get_conflict(handle, UInt64(index), &raw))
        return LFConflict(raw)
    }

    public func resolve(_ index: Int, as choice: LFChoice) throws(LFError) {
        guard index >= 0 else {
            throw LFError(status: LF_ERR_INVALID_ARGUMENT, detail: "conflict index \(index) is negative")
        }
        try LFError.check(lf_doc_set_choice(handle, UInt64(index), choice.raw))
    }

    public func resolveAll(as choice: LFChoice) throws(LFError) {
        try LFError.check(lf_doc_set_choice_all(handle, choice.raw))
    }

    public func setCustom(_ index: Int, bytes: [UInt8]) throws(LFError) {
        guard index >= 0 else {
            throw LFError(status: LF_ERR_INVALID_ARGUMENT, detail: "conflict index \(index) is negative")
        }
        let status = bytes.withUnsafeBufferPointer { buffer in
            lf_doc_set_custom(handle, UInt64(index), buffer.baseAddress, buffer.count)
        }
        try LFError.check(status)
    }

    /// Byte offset where a 1-based line starts; `lineCount + 1` is the end of the text.
    public func lineOffset(_ line: Int) throws(LFError) -> Int {
        guard line >= 0 else {
            throw LFError(status: LF_ERR_INVALID_ARGUMENT, detail: "line \(line) is negative")
        }
        var offset: UInt64 = 0
        try LFError.check(lf_doc_line_offset(handle, UInt64(line), &offset))
        return Int(offset)
    }

    /// Copies a byte range of the document's UTF-8 text. Out-of-range requests are clamped.
    public func bytes(in range: LFRange) -> [UInt8] {
        var length: UInt64 = 0
        guard let base = lf_doc_data(handle, &length), range.length > 0 else { return [] }
        let start = min(max(range.offset, 0), Int(length))
        let end = min(start + range.length, Int(length))
        return Array(UnsafeBufferPointer(start: base + start, count: end - start))
    }

    /// Writes the resolved file atomically. `path` defaults to the source file.
    public func save(to path: String? = nil, force: Bool = false) throws(LFError) {
        let flags: UInt32 = force ? LF_SAVE_FORCE : 0
        let status: lf_status
        if let path {
            status = path.withCString { lf_doc_save(handle, $0, flags) }
        } else {
            status = lf_doc_save(handle, nil, flags)
        }
        try LFError.check(status)
    }
}
