import Foundation
import LFCore
import Testing
@testable import LFKit

/// Builds random well-formed conflicted files together with the expected result of every choice.
private struct GeneratedFile {
    var bytes: [UInt8] = []
    var current: [UInt8] = []
    var incoming: [UInt8] = []
    var bothCurrentFirst: [UInt8] = []
    var bothIncomingFirst: [UInt8] = []
    var base: [UInt8] = []
    var conflictCount = 0

    mutating func plain(_ line: [UInt8]) {
        bytes += line
        current += line
        incoming += line
        bothCurrentFirst += line
        bothIncomingFirst += line
        base += line
    }

    mutating func conflict(marker: [UInt8], cur: [UInt8], baseSide: [UInt8]?, inc: [UInt8]) {
        bytes += marker
        current += cur
        incoming += inc
        bothCurrentFirst += cur + inc
        bothIncomingFirst += inc + cur
        base += baseSide ?? []
        conflictCount += 1
    }
}

private struct FileBuilder {
    var rng: SplitMix64
    let diff3: Bool
    let crlf: Bool
    let mixed: Bool

    private static let outsideLookalikes = ["=======", "|||||||", ">>>>>>> x", "<<<<<<<< eight", "  <<<<<<< indented", "<<<<<<<glued"]
    private static let sideLookalikes = ["<<<<<<<< eight", "  <<<<<<< indented", ">>>>>>>> eight", "<<<<<<<glued"]
    private static let incomingExtras = ["=======", "|||||||"]

    mutating func eol() -> String {
        if mixed { return Bool.random(using: &rng) ? "\r\n" : "\n" }
        return crlf ? "\r\n" : "\n"
    }

    mutating func line(_ content: String) -> [UInt8] {
        Array((content + eol()).utf8)
    }

    mutating func side(lookalikes: [String]) -> [UInt8] {
        let count = Int.random(in: 0...4, using: &rng)
        var out: [UInt8] = []
        for index in 0..<count {
            let useLookalike = !lookalikes.isEmpty && Int.random(in: 0..<4, using: &rng) == 0
            let content = useLookalike ? lookalikes.randomElement(using: &rng)! : "side line \(index) \(UInt32.random(in: 0..<1000, using: &rng))"
            out += line(content)
        }
        return out
    }

    mutating func build() -> GeneratedFile {
        var file = GeneratedFile()
        let segments = Int.random(in: 1...12, using: &rng)
        for segment in 0..<segments {
            let plainLines = Int.random(in: 0...5, using: &rng)
            for index in 0..<plainLines {
                let lookalike = Int.random(in: 0..<5, using: &rng) == 0
                let content = lookalike ? Self.outsideLookalikes.randomElement(using: &rng)! : "plain \(segment).\(index)"
                file.plain(line(content))
            }
            if Bool.random(using: &rng) || segment == segments - 1 {
                appendConflict(to: &file)
            }
        }
        file.plain(line("tail"))
        return file
    }

    private mutating func appendConflict(to file: inout GeneratedFile) {
        let open = line("<<<<<<< HEAD")
        let cur = side(lookalikes: Self.sideLookalikes)
        let baseSide = diff3 ? side(lookalikes: Self.sideLookalikes) : nil
        let inc = side(lookalikes: Self.sideLookalikes + Self.incomingExtras)
        var marker = open + cur
        if let baseSide {
            marker += line("||||||| merged common ancestors") + baseSide
        }
        marker += line("=======") + inc + line(">>>>>>> feature")
        file.conflict(marker: marker, cur: cur, baseSide: baseSide, inc: inc)
    }
}

@Suite("Property: random conflicted files")
struct PropertyTests {
    private static let iterations = 400

    private func check(
        _ expected: [UInt8], choice: LFChoice, path: String, sandbox: Sandbox, label: String, seed: Int
    ) throws {
        let doc = try LFDocument(path: path)
        try doc.resolveAll(as: choice)
        let out = sandbox.path("out-\(seed).txt")
        try doc.save(to: out)
        #expect(sandbox.read(out) == expected, "seed \(seed): \(label)")
    }

    @Test("every uniform choice matches the construction of the file")
    func uniformChoices() throws {
        let box = Sandbox()
        for seed in 0..<Self.iterations {
            var builder = FileBuilder(
                rng: SplitMix64(seed: UInt64(seed)),
                diff3: seed % 2 == 0,
                crlf: seed % 3 == 0,
                mixed: seed % 5 == 0
            )
            let file = builder.build()
            let path = box.write("in-\(seed).txt", bytes: file.bytes)
            let doc = try LFDocument(path: path)
            #expect(doc.info.conflictCount == file.conflictCount, "seed \(seed): conflict count")

            try check(file.current, choice: .current, path: path, sandbox: box, label: "current", seed: seed)
            try check(file.incoming, choice: .incoming, path: path, sandbox: box, label: "incoming", seed: seed)
            try check(file.bothCurrentFirst, choice: .bothCurrentFirst, path: path, sandbox: box, label: "both", seed: seed)
            try check(file.bothIncomingFirst, choice: .bothIncomingFirst, path: path, sandbox: box, label: "both-incoming", seed: seed)
            if seed % 2 == 0 {
                try check(file.base, choice: .base, path: path, sandbox: box, label: "base", seed: seed)
            }
        }
    }

    @Test("resolving nothing and force-saving reproduces the input byte for byte")
    func forceSaveIsIdentity() throws {
        let box = Sandbox()
        for seed in 0..<Self.iterations {
            var builder = FileBuilder(
                rng: SplitMix64(seed: UInt64(seed) &+ 10_000), diff3: seed % 2 == 0, crlf: false, mixed: seed % 3 == 0
            )
            let file = builder.build()
            let path = box.write("in-\(seed).txt", bytes: file.bytes)
            let doc = try LFDocument(path: path)
            let out = box.path("out-\(seed).txt")

            try doc.save(to: out, force: true)

            #expect(box.read(out) == file.bytes, "seed \(seed)")
        }
    }

    @Test("arbitrary bytes never crash the scanner")
    func randomBytesDoNotCrash() throws {
        let box = Sandbox()
        var rng = SplitMix64(seed: 42)
        let alphabet: [UInt8] = Array("<|=>\r\n x".utf8) + [0x00, 0xFF, 0xEF, 0xBB, 0xBF]
        for iteration in 0..<Self.iterations {
            let length = Int.random(in: 0...400, using: &rng)
            let bytes = (0..<length).map { _ in alphabet.randomElement(using: &rng)! }
            let path = box.write("fuzz-\(iteration).bin", bytes: bytes)

            if let doc = try? LFDocument(path: path) {
                _ = try? doc.resolveAll(as: .current)
                try? doc.save(to: box.path("fuzz-out-\(iteration).bin"), force: true)
            }
        }
    }
}
