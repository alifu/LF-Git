import Foundation
import Testing
@testable import LF_Git

@Suite("Launch options")
struct LaunchOptionsTests {
    @Test("--repo and --file are read; unrelated arguments are ignored")
    func parsesArguments() {
        let options = LaunchOptions.parse(["/app", "-NSDocumentRevisionsDebugMode", "YES", "--repo", "/tmp/r", "--file", "a/b.swift"])

        #expect(options.repository == URL(fileURLWithPath: "/tmp/r"))
        #expect(options.file == "a/b.swift")
    }

    @Test("no arguments means no repository")
    func empty() {
        #expect(LaunchOptions.parse(["/app"]) == LaunchOptions())
    }

    @Test("lfgit:// URLs carry the repository and file, percent-encoded")
    func parsesURL() throws {
        let url = try #require(URL(string: "lfgit://open?repo=/tmp/my%20repo&file=App/My%20File.swift"))

        let options = try #require(LaunchOptions.parse(url: url))

        #expect(options.repository == URL(fileURLWithPath: "/tmp/my repo"))
        #expect(options.file == "App/My File.swift")
    }

    @Test("other URLs are ignored")
    func otherURLs() throws {
        #expect(LaunchOptions.parse(url: try #require(URL(string: "https://example.com/?repo=/x"))) == nil)
        #expect(LaunchOptions.parse(url: try #require(URL(string: "lfgit://open"))) == nil)
    }

    @Test("a flag without a value is ignored")
    func missingValue() {
        #expect(LaunchOptions.parse(["/app", "--repo"]).repository == nil)
    }
}

@Suite("Line classifier")
struct LineClassifierTests {
    // Lines: 1 a | 2 <<< | 3 ours | 4 ||| | 5 base | 6 === | 7 theirs | 8 >>> | 9 b | 10 <<< | 11 === | 12 >>>
    private let classifier = LineClassifier(spans: [
        ConflictSpan(index: 0, openLine: 2, baseLine: 4, separatorLine: 6, closeLine: 8),
        ConflictSpan(index: 1, openLine: 10, baseLine: 0, separatorLine: 11, closeLine: 12),
    ])

    @Test("every line of a diff3 conflict gets its role", arguments: [
        (1, LineRole.plain), (2, .header(conflict: 0)), (3, .current(conflict: 0)), (4, .baseHeader(conflict: 0)),
        (5, .base(conflict: 0)), (6, .separator(conflict: 0)), (7, .incoming(conflict: 0)), (8, .footer(conflict: 0)),
        (9, .plain), (10, .header(conflict: 1)), (11, .separator(conflict: 1)), (12, .footer(conflict: 1)), (13, .plain),
    ])
    func roles(line: Int, expected: LineRole) {
        #expect(classifier.role(ofLine: line) == expected)
    }

    @Test("the conflict containing a line is found by binary search")
    func conflictAtLine() {
        #expect(classifier.conflict(containingLine: 5) == 0)
        #expect(classifier.conflict(containingLine: 9) == nil)
        #expect(classifier.conflict(containingLine: 12) == 1)
    }

    @Test("a file without conflicts is all plain")
    func noConflicts() {
        #expect(LineClassifier(spans: []).role(ofLine: 3) == .plain)
    }
}

@Suite("Syntax highlighter")
struct SyntaxHighlighterTests {
    private func kinds(_ line: String, _ language: SyntaxLanguage) -> [String: SyntaxToken.Kind] {
        let utf16 = Array(line.utf16)
        var result: [String: SyntaxToken.Kind] = [:]
        for token in SyntaxHighlighter.tokens(in: line, language: language) {
            result[String(decoding: utf16[token.range], as: UTF16.self)] = token.kind
        }
        return result
    }

    @Test("languages are picked by file extension")
    func languageForPath() {
        #expect(SyntaxLanguage.forPath("a/B.swift") == .swift)
        #expect(SyntaxLanguage.forPath("X.xcodeproj/project.pbxproj") == .pbxproj)
        #expect(SyntaxLanguage.forPath("c.m") == .objc)
        #expect(SyntaxLanguage.forPath("Package.resolved") == .json)
        #expect(SyntaxLanguage.forPath("ci.yml") == .yaml)
        #expect(SyntaxLanguage.forPath("notes") == .plain)
    }

    @Test("Swift keywords, types, strings, numbers and comments")
    func swift() {
        let tokens = kinds(#"let view: UIView = make("hi", 42) // done"#, .swift)

        #expect(tokens["let"] == .keyword)
        #expect(tokens["UIView"] == .type)
        #expect(tokens[#""hi""#] == .string)
        #expect(tokens["42"] == .number)
        #expect(tokens["// done"] == .comment)
        #expect(tokens["make"] == nil)
    }

    @Test("escaped quotes stay inside the string")
    func escapes() {
        #expect(kinds(#"x = "a\"b" + 1"#, .swift)[#""a\"b""#] == .string)
    }

    @Test("project files highlight object IDs and comments")
    func pbxproj() {
        let tokens = kinds("\t\t82C428D03078FCD200C5A3AD /* LFKit */ = {isa = PBXBuildFile; };", .pbxproj)

        #expect(tokens["82C428D03078FCD200C5A3AD"] == .identifier)
        #expect(tokens["/* LFKit */"] == .comment)
        #expect(tokens["isa"] == .keyword)
    }

    @Test("plain text has no tokens and very long lines are not scanned past the limit")
    func plainAndLimits() {
        #expect(SyntaxHighlighter.tokens(in: "let x = 1", language: .plain).isEmpty)
        let long = String(repeating: "a ", count: 10_000) + "\"tail\""
        #expect(SyntaxHighlighter.tokens(in: long, language: .swift).allSatisfy { $0.range.upperBound <= SyntaxHighlighter.maxScannedLength })
    }
}
