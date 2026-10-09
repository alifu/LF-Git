import Foundation

/// A temporary directory that is removed when the value goes out of scope.
final class Sandbox: @unchecked Sendable {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lfgit-test-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            preconditionFailure("cannot create sandbox: \(error)")
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func path(_ name: String) -> String {
        root.appendingPathComponent(name).path
    }

    @discardableResult
    func write(_ name: String, bytes: [UInt8]) -> String {
        let target = path(name)
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: target).deletingLastPathComponent(), withIntermediateDirectories: true
        )
        guard FileManager.default.createFile(atPath: target, contents: Data(bytes)) else {
            preconditionFailure("cannot write \(target)")
        }
        return target
    }

    @discardableResult
    func write(_ name: String, _ text: String) -> String {
        write(name, bytes: Array(text.utf8))
    }

    func read(_ path: String) -> [UInt8] {
        guard let data = FileManager.default.contents(atPath: path) else {
            preconditionFailure("cannot read \(path)")
        }
        return Array(data)
    }

    func readText(_ path: String) -> String {
        String(decoding: read(path), as: UTF8.self)
    }
}

/// Joins `lines`, ending each with `eol`.
func text(_ lines: String..., eol: String = "\n") -> String {
    lines.map { $0 + eol }.joined()
}

/// UTF-16 bytes of `string`, with a byte-order mark.
func utf16Bytes(_ string: String, bigEndian: Bool = false) -> [UInt8] {
    var bytes: [UInt8] = bigEndian ? [0xFE, 0xFF] : [0xFF, 0xFE]
    for unit in string.utf16 {
        let high = UInt8(unit >> 8), low = UInt8(unit & 0xFF)
        bytes.append(contentsOf: bigEndian ? [high, low] : [low, high])
    }
    return bytes
}

/// Deterministic generator so property tests are reproducible.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
