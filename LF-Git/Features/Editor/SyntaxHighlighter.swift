import Foundation

nonisolated enum SyntaxLanguage: Sendable, Equatable {
    case swift, objc, json, yaml, pbxproj, markdown, plain

    static func forPath(_ path: String) -> SyntaxLanguage {
        let name = (path as NSString).lastPathComponent
        switch (name as NSString).pathExtension.lowercased() {
        case "swift": return .swift
        case "m", "mm", "h", "c", "cc", "cpp", "hpp": return .objc
        case "json", "resolved", "xcstrings": return .json
        case "yml", "yaml": return .yaml
        case "pbxproj": return .pbxproj
        case "md", "markdown": return .markdown
        default: return name == "Podfile.lock" ? .yaml : .plain
        }
    }
}

nonisolated struct SyntaxToken: Equatable, Sendable {
    enum Kind: Sendable, Equatable {
        case keyword, string, number, comment, type, identifier
    }

    /// UTF-16 offsets, ready for NSAttributedString.
    let range: Range<Int>
    let kind: Kind
}

/// A small single-line tokenizer: enough to colour code in the conflict editor, cheap enough to
/// run on every visible row. It does not track state across lines.
nonisolated enum SyntaxHighlighter {
    /// Lines are only scanned up to here; the rest stays plain.
    static let maxScannedLength = 2000

    private static let swiftKeywords: Set<String> = [
        "actor", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue", "default",
        "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "final", "for",
        "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let", "nil", "nonisolated",
        "open", "operator", "override", "private", "protocol", "public", "repeat", "rethrows", "return", "self",
        "Self", "some", "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try",
        "typealias", "var", "where", "while", "any", "lazy", "weak", "mutating", "convenience", "required",
    ]
    private static let objcKeywords: Set<String> = [
        "if", "else", "for", "while", "do", "return", "switch", "case", "default", "break", "continue", "static",
        "const", "void", "int", "char", "float", "double", "long", "unsigned", "struct", "enum", "typedef", "sizeof",
        "id", "self", "super", "nil", "NULL", "YES", "NO", "true", "false", "#import", "#include", "#define",
    ]
    private static let dataKeywords: Set<String> = ["true", "false", "null", "yes", "no"]
    private static let pbxprojKeywords: Set<String> = ["isa"]

    static func tokens(in line: String, language: SyntaxLanguage) -> [SyntaxToken] {
        guard language != .plain else { return [] }
        let units = Array(line.utf16.prefix(maxScannedLength))
        if language == .markdown {
            return units.first == 0x23 /* # */ ? [SyntaxToken(range: 0..<units.count, kind: .keyword)] : []
        }
        var scanner = Scanner(units: units, language: language)
        return scanner.run()
    }

    private struct Scanner {
        let units: [UInt16]
        let language: SyntaxLanguage
        var tokens: [SyntaxToken] = []
        var i = 0

        mutating func run() -> [SyntaxToken] {
            while i < units.count {
                let c = units[i]
                if startsLineComment() {
                    tokens.append(SyntaxToken(range: i..<units.count, kind: .comment))
                    break
                } else if c == 0x2F /* / */, peek(1) == 0x2A /* * */, language != .yaml, language != .json {
                    blockComment()
                } else if c == 0x22 /* " */ {
                    quoted()
                } else if isWord(c) {
                    word()
                } else {
                    i += 1
                }
            }
            return tokens
        }

        func peek(_ offset: Int) -> UInt16? {
            i + offset < units.count ? units[i + offset] : nil
        }

        func startsLineComment() -> Bool {
            switch language {
            case .yaml: return units[i] == 0x23 /* # */
            case .json: return false
            default: return units[i] == 0x2F && peek(1) == 0x2F
            }
        }

        mutating func blockComment() {
            let start = i
            i += 2
            while i < units.count, !(units[i] == 0x2A && peek(1) == 0x2F) { i += 1 }
            i = min(i + 2, units.count)
            tokens.append(SyntaxToken(range: start..<i, kind: .comment))
        }

        mutating func quoted() {
            let start = i
            i += 1
            while i < units.count, units[i] != 0x22 { i += units[i] == 0x5C /* \ */ ? 2 : 1 }
            i = min(i + 1, units.count)
            tokens.append(SyntaxToken(range: start..<i, kind: .string))
        }

        func isWord(_ c: UInt16) -> Bool {
            (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F
                || (c == 0x23 && language == .objc) // #import
        }

        mutating func word() {
            let start = i
            while i < units.count, isWord(units[i]) { i += 1 }
            let text = String(decoding: units[start..<i], as: UTF16.self)
            if let kind = classify(text) {
                tokens.append(SyntaxToken(range: start..<i, kind: kind))
            }
        }

        func classify(_ word: String) -> SyntaxToken.Kind? {
            if language == .pbxproj, word.count == 24, word.allSatisfy({ $0.isHexDigit && !$0.isLowercase }) {
                return .identifier
            }
            if word.first?.isNumber == true {
                return word.allSatisfy { $0.isNumber || $0 == "." || $0 == "x" || $0.isHexDigit } ? .number : nil
            }
            switch language {
            case .swift: return SyntaxHighlighter.swiftKeywords.contains(word) ? .keyword : (word.first!.isUppercase ? .type : nil)
            case .objc: return SyntaxHighlighter.objcKeywords.contains(word) ? .keyword : (word.first!.isUppercase ? .type : nil)
            case .json, .yaml: return SyntaxHighlighter.dataKeywords.contains(word) ? .keyword : nil
            case .pbxproj: return SyntaxHighlighter.pbxprojKeywords.contains(word) ? .keyword : nil
            case .markdown, .plain: return nil
            }
        }
    }
}
