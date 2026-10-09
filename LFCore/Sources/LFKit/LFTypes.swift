import LFCore

public enum LFFileKind: Sendable, Equatable {
    case text
    case binary
}

public enum LFEncoding: Sendable, Equatable {
    case utf8
    case utf8Bom
    case utf16LittleEndian
    case utf16BigEndian

    init(_ raw: lf_encoding) {
        switch raw {
        case LF_ENCODING_UTF8_BOM: self = .utf8Bom
        case LF_ENCODING_UTF16LE: self = .utf16LittleEndian
        case LF_ENCODING_UTF16BE: self = .utf16BigEndian
        default: self = .utf8
        }
    }
}

public enum LFLineEnding: Sendable, Equatable {
    case none
    case lf
    case crlf
    case mixed

    init(_ raw: lf_eol) {
        switch raw {
        case LF_EOL_LF: self = .lf
        case LF_EOL_CRLF: self = .crlf
        case LF_EOL_MIXED: self = .mixed
        default: self = .none
        }
    }
}

/// How a conflict is resolved.
public enum LFChoice: Sendable, Equatable, CaseIterable {
    case unresolved
    case current
    case incoming
    case bothCurrentFirst
    case bothIncomingFirst
    case base
    case custom

    init(_ raw: lf_choice) {
        switch raw {
        case LF_CHOICE_CURRENT: self = .current
        case LF_CHOICE_INCOMING: self = .incoming
        case LF_CHOICE_BOTH_CURRENT_FIRST: self = .bothCurrentFirst
        case LF_CHOICE_BOTH_INCOMING_FIRST: self = .bothIncomingFirst
        case LF_CHOICE_BASE: self = .base
        case LF_CHOICE_CUSTOM: self = .custom
        default: self = .unresolved
        }
    }

    var raw: lf_choice {
        switch self {
        case .unresolved: LF_CHOICE_UNRESOLVED
        case .current: LF_CHOICE_CURRENT
        case .incoming: LF_CHOICE_INCOMING
        case .bothCurrentFirst: LF_CHOICE_BOTH_CURRENT_FIRST
        case .bothIncomingFirst: LF_CHOICE_BOTH_INCOMING_FIRST
        case .base: LF_CHOICE_BASE
        case .custom: LF_CHOICE_CUSTOM
        }
    }
}

/// A byte range inside a document's text.
public struct LFRange: Sendable, Equatable {
    public let offset: Int
    public let length: Int

    init(_ raw: lf_range) {
        offset = Int(raw.offset)
        length = Int(raw.length)
    }
}

public struct LFConflict: Sendable, Equatable {
    public let openLine: Int
    public let baseLine: Int
    public let separatorLine: Int
    public let closeLine: Int
    public let region: LFRange
    public let current: LFRange
    public let base: LFRange
    public let incoming: LFRange
    public let currentLabel: LFRange
    public let incomingLabel: LFRange
    public let choice: LFChoice
    public let hasBase: Bool

    /// Lines in the current side (excluding marker lines).
    public var currentLineCount: Int {
        (hasBase ? baseLine : separatorLine) - openLine - 1
    }

    public var baseLineCount: Int {
        hasBase ? separatorLine - baseLine - 1 : 0
    }

    public var incomingLineCount: Int {
        closeLine - separatorLine - 1
    }

    init(_ raw: lf_conflict_info) {
        openLine = Int(raw.open_line)
        baseLine = Int(raw.base_line)
        separatorLine = Int(raw.separator_line)
        closeLine = Int(raw.close_line)
        region = LFRange(raw.region)
        current = LFRange(raw.current)
        base = LFRange(raw.base)
        incoming = LFRange(raw.incoming)
        currentLabel = LFRange(raw.current_label)
        incomingLabel = LFRange(raw.incoming_label)
        choice = LFChoice(raw.choice)
        hasBase = raw.has_base != 0
    }
}

public struct LFDocumentInfo: Sendable, Equatable {
    public let size: Int
    public let lineCount: Int
    public let conflictCount: Int
    public let unresolvedCount: Int
    public let encoding: LFEncoding
    public let eol: LFLineEnding

    init(_ raw: lf_doc_info) {
        size = Int(raw.size)
        lineCount = Int(raw.line_count)
        conflictCount = Int(raw.conflict_count)
        unresolvedCount = Int(raw.unresolved_count)
        encoding = LFEncoding(raw.encoding)
        eol = LFLineEnding(raw.eol)
    }
}

/// Cheap classification of a file: reads only its first 8000 bytes.
public struct LFFileProbe: Sendable, Equatable {
    public let kind: LFFileKind
    public let encoding: LFEncoding

    public init(path: String) throws(LFError) {
        var info = lf_text_info()
        let status = path.withCString { lf_probe_file($0, &info) }
        try LFError.check(status)
        kind = info.kind == LF_KIND_BINARY ? .binary : .text
        encoding = LFEncoding(info.encoding)
    }
}
