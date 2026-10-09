import Darwin
import Foundation
import LFKit

// lf-bench — measures open+scan, resolve and save on a synthetic conflicted file.
//
//   lf-bench [--lines N] [--conflicts M] [--keep] [--file PATH]
//
// Gate (plan, Phase 1): 10,000,000 lines opened, indexed and scanned in under 1 second.

let gateLines = 10_000_000
let gateSeconds = 1.0
let chunkBytes = 8 << 20

struct Options {
    var lines = gateLines
    var conflicts = 10_000
    var keep = false
    var file: String?
}

func parseOptions() -> Options {
    var options = Options()
    var arguments = CommandLine.arguments.dropFirst()
    while let argument = arguments.popFirst() {
        switch argument {
        case "--lines": options.lines = arguments.popFirst().flatMap(Int.init) ?? options.lines
        case "--conflicts": options.conflicts = arguments.popFirst().flatMap(Int.init) ?? options.conflicts
        case "--file": options.file = arguments.popFirst()
        case "--keep": options.keep = true
        default:
            FileHandle.standardError.write(Data("usage: lf-bench [--lines N] [--conflicts M] [--keep] [--file PATH]\n".utf8))
            exit(2)
        }
    }
    return options
}

func appendNumber(_ value: Int, to buffer: inout [UInt8]) {
    var digits: [UInt8] = []
    var rest = value
    repeat {
        digits.append(UInt8(48 + rest % 10))
        rest /= 10
    } while rest > 0
    buffer.append(contentsOf: digits.reversed())
}

func appendLine(_ prefix: StaticString, _ number: Int, to buffer: inout [UInt8]) {
    prefix.withUTF8Buffer { buffer.append(contentsOf: $0) }
    appendNumber(number, to: &buffer)
    buffer.append(10)
}

func appendText(_ text: StaticString, to buffer: inout [UInt8]) {
    text.withUTF8Buffer { buffer.append(contentsOf: $0) }
    buffer.append(10)
}

func generate(path: String, lines: Int, conflicts: Int) throws {
    guard FileManager.default.createFile(atPath: path, contents: nil),
          let handle = FileHandle(forWritingAtPath: path) else {
        throw CocoaError(.fileWriteUnknown)
    }
    defer { try? handle.close() }
    let interval = max(1, lines / (conflicts + 1))
    var emitted = 0
    var buffer: [UInt8] = []
    buffer.reserveCapacity(chunkBytes + 4096)
    for index in 0..<lines {
        if conflicts > 0, index > 0, index % interval == 0, emitted < conflicts {
            appendLine("<<<<<<< HEAD line ", index, to: &buffer)
            appendLine("    let ours = compute(", index, to: &buffer)
            appendText("=======", to: &buffer)
            appendLine("    let theirs = compute(", index, to: &buffer)
            appendLine(">>>>>>> feature ", index, to: &buffer)
            emitted += 1
        }
        appendLine("    let value = compute(", index, to: &buffer)
        if buffer.count >= chunkBytes {
            try handle.write(contentsOf: buffer)
            buffer.removeAll(keepingCapacity: true)
        }
    }
    try handle.write(contentsOf: buffer)
}

func seconds<T>(_ body: () throws -> T) rethrows -> (T, Double) {
    let start = DispatchTime.now().uptimeNanoseconds
    let value = try body()
    return (value, Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9)
}

func peakResidentMegabytes() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_maxrss) / 1_048_576
}

func report(_ label: String, _ time: Double, _ extra: String = "") {
    print(String(format: "  %-22@ %8.3f s  %@", label as NSString, time, extra as NSString))
}

let options = parseOptions()
let path = options.file ?? NSTemporaryDirectory() + "lf-bench-\(getpid()).txt"
let generated = options.file == nil

do {
    if generated {
        let (_, time) = try seconds { try generate(path: path, lines: options.lines, conflicts: options.conflicts) }
        let size = (try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        print("generated \(options.lines) lines, \(options.conflicts) conflicts, \(size / 1_048_576) MB")
        report("generate", time)
    }
    func cleanUp() {
        if generated && !options.keep { try? FileManager.default.removeItem(atPath: path) }
    }

    // Evict nothing: run twice and report both, since the first run may include cold-cache reads.
    var openTimes: [Double] = []
    var document: LFDocument?
    for run in 1...2 {
        document = nil  // release the previous mapping so peak memory reflects one open document
        let (opened, time) = try seconds { try LFDocument(path: path) }
        openTimes.append(time)
        let info = opened.info
        report("open + scan (run \(run))", time, "\(info.lineCount) lines, \(info.conflictCount) conflicts")
        document = opened
    }
    guard let document else { cleanUp(); exit(1) }

    let (_, resolveTime) = try seconds { try document.resolveAll(as: .bothCurrentFirst) }
    report("resolve all", resolveTime)
    let output = path + ".resolved"
    let (_, saveTime) = try seconds { try document.save(to: output) }
    report("save", saveTime)
    try? FileManager.default.removeItem(atPath: output)

    print(String(format: "  peak resident memory   %8.0f MB", peakResidentMegabytes()))
    let warm = openTimes.min() ?? .infinity
    cleanUp()
    if options.lines >= gateLines {
        let passed = warm < gateSeconds
        print("gate: open+scan of \(options.lines) lines under \(gateSeconds) s (best run \(String(format: "%.3f", warm)) s): \(passed ? "PASS" : "FAIL")")
        exit(passed ? 0 : 1)
    }
} catch {
    if generated && !options.keep { try? FileManager.default.removeItem(atPath: path) }
    FileHandle.standardError.write(Data("lf-bench: \(error)\n".utf8))
    exit(1)
}
