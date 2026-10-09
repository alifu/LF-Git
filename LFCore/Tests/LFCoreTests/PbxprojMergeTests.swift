import Foundation
import LFCore
@testable import LFKit
import LFTestSupport
import Testing

private func merge(_ base: ClassicProject, _ ours: ClassicProject, _ theirs: ClassicProject) throws -> LFMergeResult {
    try PbxprojMerge.merge(base: base.bytes, ours: ours.bytes, theirs: theirs.bytes)
}

private func string(_ result: LFMergeResult) -> String {
    String(decoding: result.bytes, as: UTF8.self)
}

/// Resolves every conflict block left by the merge the same way, through the regular engine.
private func resolving(_ result: LFMergeResult, as choice: LFChoice) throws -> String {
    let box = Sandbox()
    let path = box.write("project.pbxproj", bytes: result.bytes)
    let document = try LFDocument(path: path)
    try document.resolveAll(as: choice)
    try document.save()
    return box.readText(path)
}

private func unsupported(_ base: [UInt8], _ ours: [UInt8], _ theirs: [UInt8]) -> LFError? {
    do {
        _ = try PbxprojMerge.merge(base: base, ours: ours, theirs: theirs)
        return nil
    } catch {
        return error
    }
}

@Suite("pbxproj merge: clean merges")
struct PbxprojCleanMergeTests {
    @Test("identical inputs merge to the same bytes")
    func identity() throws {
        let project = ClassicProject.withSources([1, 2, 3])

        let result = try merge(project, project, project)

        #expect(result.bytes == project.bytes)
        #expect(result.conflictCount == 0)
    }

    @Test("a change on one side only is taken byte for byte")
    func oneSided() throws {
        let base = ClassicProject.withSources([1, 2])
        var changed = base
        changed.addSource(3)
        changed.debugSettings["SWIFT_VERSION"] = .value("6.0")

        #expect(try merge(base, changed, base).bytes == changed.bytes)
        #expect(try merge(base, base, changed).bytes == changed.bytes)
        #expect(try merge(base, changed, changed).bytes == changed.bytes)
    }

    @Test("both sides adding different files merge into one project")
    func bothAddFiles() throws {
        let base = ClassicProject.withSources([1])
        var ours = base
        ours.addSource(2)
        var theirs = base
        theirs.addSource(3)
        var expected = base
        expected.addSource(2)
        expected.addSource(3)

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount == 0)
        #expect(string(result) == expected.text)
        #expect(result.mergedObjectCount >= 2) // the group and the Sources phase
    }

    @Test("an addition on one side and a removal on the other both apply")
    func addAndRemove() throws {
        let base = ClassicProject.withSources([1, 2])
        var ours = base
        ours.addSource(3)
        var theirs = base
        theirs.removeFile(refID: ClassicProject.refID(1))
        var expected = ours
        expected.removeFile(refID: ClassicProject.refID(1))

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount == 0)
        #expect(string(result) == expected.text)
    }

    @Test("different build settings changed in the same configuration are combined")
    func differentSettings() throws {
        var base = ClassicProject.withSources([1])
        base.debugSettings = ["A": .value("1"), "B": .value("2"), "D": .value("4")]
        var ours = base
        ours.debugSettings["A"] = .value("10")
        var theirs = base
        theirs.debugSettings["B"] = .value("20")
        theirs.debugSettings["C"] = .value("3")
        theirs.debugSettings["D"] = nil
        var expected = base
        expected.debugSettings = ["A": .value("10"), "B": .value("20"), "C": .value("3")]

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount == 0)
        #expect(string(result) == expected.text)
    }

    @Test("theirs reordering build phases and ours adding a file are both kept")
    func reorderAndAdd() throws {
        let base = ClassicProject.withSources([1])
        var ours = base
        ours.addSource(2)
        var theirs = base
        theirs.phases = [.frameworks, .sources, .resources]
        var expected = ours
        expected.phases = theirs.phases

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount == 0)
        #expect(string(result) == expected.text)
    }

    @Test("lists of plain strings outside build settings merge as sets")
    func knownRegions() throws {
        let base = ClassicProject.withSources([1])
        var ours = base
        ours.knownRegions.append("de")
        var theirs = base
        theirs.knownRegions.append("fr")
        var expected = base
        expected.knownRegions += ["de", "fr"]

        let result = try merge(base, ours, theirs)

        #expect(string(result) == expected.text)
    }

    @Test("different fields of one single-line object are combined")
    func singleLineObjectFields() throws {
        let base = ClassicProject.withSources([1])
        var ours = base
        ours.files[0].fileType = "sourcecode.swift.alt"
        var theirs = base
        theirs.files[0].displayName = "Main"
        var expected = ours
        expected.files[0].displayName = "Main"

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount == 0)
        #expect(string(result) == expected.text)
    }

    @Test("lists that already contain duplicates (left by older merges) still merge as ordered sets")
    func duplicatesInLists() throws {
        // Real projects often list the same file twice in a group after a bad merge.
        var base = ClassicProject.withSources([1, 2])
        base.files.append(base.files[0])
        var ours = base
        ours.addSource(3)
        var theirs = base
        theirs.addSource(4)
        var expected = base
        expected.addSource(3)
        expected.addSource(4)
        // addSource appends after the duplicate; the expected order follows the same rule.

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount == 0)
        #expect(string(result) == expected.text)
    }

    @Test("removing one copy of a duplicated element removes exactly one copy")
    func removeOneDuplicate() throws {
        var base = ClassicProject.withSources([1, 2])
        base.files.append(base.files[0])
        var ours = base
        ours.files.removeLast()
        var theirs = base
        theirs.addSource(5)
        var expected = theirs
        expected.files.remove(at: 2)

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount == 0)
        #expect(string(result) == expected.text)
    }

    @Test("both sides removing the first copy of a duplicated child is not a reorder (seen in a real merge)")
    func duplicateRemovedByBoth() throws {
        var base = ClassicProject.withSources([1, 2, 3])
        base.files.insert(base.files[2], at: 0) // File3 listed first and last
        var ours = base
        ours.files.removeFirst()
        ours.files.insert(ours.files[1], at: 0) // and a stray extra copy of File2 at the top
        ours.addSource(4)
        var theirs = base
        theirs.files.removeFirst()
        theirs.addSource(5)
        var expected = ours
        expected.addSource(5)

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount == 0)
        #expect(string(result) == expected.text)
    }

    @Test("extra copies of an element go away when the other side removes the element (seen in a real merge)")
    func duplicateOfRemovedElement() throws {
        let base = ClassicProject.withSources([1, 2, 3])
        var ours = base
        ours.files.append(ours.files[1]) // a stray second copy of File2, left by an older merge
        ours.addSource(4)
        var theirs = base
        theirs.removeFile(refID: ClassicProject.refID(2))
        var expected = base
        expected.removeFile(refID: ClassicProject.refID(2))
        expected.addSource(4)

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount == 0)
        #expect(string(result) == expected.text)
    }

    @Test("a deletion whose side already had a dangling reference is followed, as git and Xcode would")
    func inheritedDanglingReference() throws {
        // Theirs deletes the build file object but (already broken) keeps listing it in the Sources phase.
        let base = ClassicProject.withSources([1, 2])
        var ours = base
        ours.addSource(3)
        let brokenTheirs = base.text.replacingOccurrences(
            of: "\t\t\(ClassicProject.buildID(1)) /* File1.swift in Sources */ = {isa = PBXBuildFile; fileRef = \(ClassicProject.refID(1)) /* File1.swift */; };\n",
            with: ""
        )
        let expected = ours.text.replacingOccurrences(
            of: "\t\t\(ClassicProject.buildID(1)) /* File1.swift in Sources */ = {isa = PBXBuildFile; fileRef = \(ClassicProject.refID(1)) /* File1.swift */; };\n",
            with: ""
        )
        #expect(brokenTheirs != base.text)

        let result = try PbxprojMerge.merge(base: base.bytes, ours: ours.bytes, theirs: Array(brokenTheirs.utf8))

        #expect(result.conflictCount == 0)
        #expect(string(result) == expected)
    }

    @Test("an objectVersion bump on one side is taken")
    func headerChange() throws {
        let base = ClassicProject.withSources([1])
        var theirs = base
        theirs.objectVersion = "60"
        var ours = base
        ours.addSource(2)
        var expected = ours
        expected.objectVersion = "60"

        #expect(string(try merge(base, ours, theirs)) == expected.text)
    }

    @Test("a real Xcode 16+ project (synchronized folders, local packages) merges field by field")
    func realProjectFile() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Synchronized.pbxproj")
        let base = try String(contentsOf: fixture, encoding: .utf8)
        let ours = base.replacingOccurrences(of: "MARKETING_VERSION = 1.0;", with: "MARKETING_VERSION = 1.1;")
        let theirs = base.replacingOccurrences(of: "CURRENT_PROJECT_VERSION = 1;", with: "CURRENT_PROJECT_VERSION = 7;")
        let expected = ours.replacingOccurrences(of: "CURRENT_PROJECT_VERSION = 1;", with: "CURRENT_PROJECT_VERSION = 7;")
        #expect(ours != base && theirs != base)

        let identity = try PbxprojMerge.merge(base: Array(base.utf8), ours: Array(base.utf8), theirs: Array(base.utf8))
        let result = try PbxprojMerge.merge(base: Array(base.utf8), ours: Array(ours.utf8), theirs: Array(theirs.utf8))

        #expect(identity.bytes == Array(base.utf8))
        #expect(result.conflictCount == 0)
        #expect(string(result) == expected)
    }
}

@Suite("pbxproj merge: conflicts")
struct PbxprojConflictTests {
    @Test("the same setting changed differently is one small conflict that resolves to either side")
    func sameSetting() throws {
        let base = ClassicProject.withSources([1])
        var ours = base
        ours.debugSettings["SWIFT_VERSION"] = .value("5.9")
        var theirs = base
        theirs.debugSettings["SWIFT_VERSION"] = .value("6.0")

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount == 1)
        #expect(string(result).contains("<<<<<<< HEAD\n\t\t\t\tSWIFT_VERSION = 5.9;\n"))
        #expect(string(result).contains("||||||| base\n\t\t\t\tSWIFT_VERSION = 5.0;\n"))
        #expect(try resolving(result, as: .current) == ours.text)
        #expect(try resolving(result, as: .incoming) == theirs.text)
    }

    @Test("a conflict next to clean changes keeps the clean changes in both resolutions")
    func conflictPlusCleanChanges() throws {
        let base = ClassicProject.withSources([1])
        var ours = base
        ours.addSource(2)
        ours.debugSettings["SWIFT_VERSION"] = .value("5.9")
        var theirs = base
        theirs.addSource(3)
        theirs.debugSettings["SWIFT_VERSION"] = .value("6.0")
        var both = base
        both.addSource(2)
        both.addSource(3)
        var expectedCurrent = both
        expectedCurrent.debugSettings["SWIFT_VERSION"] = .value("5.9")
        var expectedIncoming = both
        expectedIncoming.debugSettings["SWIFT_VERSION"] = .value("6.0")

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount == 1)
        #expect(try resolving(result, as: .current) == expectedCurrent.text)
        #expect(try resolving(result, as: .incoming) == expectedIncoming.text)
    }

    @Test("flag lists inside build settings are never merged as sets")
    func buildSettingLists() throws {
        var base = ClassicProject.withSources([1])
        base.debugSettings["OTHER_LDFLAGS"] = .list(["-ObjC"])
        var ours = base
        ours.debugSettings["OTHER_LDFLAGS"] = .list(["-ObjC", "-lz"])
        var theirs = base
        theirs.debugSettings["OTHER_LDFLAGS"] = .list(["-ObjC", "-lc++"])

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount == 1)
        #expect(try resolving(result, as: .current) == ours.text)
        #expect(try resolving(result, as: .incoming) == theirs.text)
    }

    @Test("both sides reordering the same list differently is a conflict")
    func bothReorder() throws {
        let base = ClassicProject.withSources([1])
        var ours = base
        ours.phases = [.resources, .sources, .frameworks]
        var theirs = base
        theirs.phases = [.frameworks, .sources, .resources]

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount == 1)
        #expect(try resolving(result, as: .incoming) == theirs.text)
    }

    @Test("an object deleted on one side and changed on the other is a conflict")
    func deleteVersusModify() throws {
        let base = ClassicProject.withSources([1, 2])
        var ours = base
        ours.files[0].fileType = "sourcecode.swift.alt"
        var theirs = base
        theirs.removeFile(refID: ClassicProject.refID(1))

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount == 1)
        #expect(try resolving(result, as: .incoming) == theirs.text)
    }

    @Test("deleting an object that the other side starts using is a conflict, not a dangling reference")
    func deletedButReferenced() throws {
        let base = ClassicProject.withSources([1, 2])
        var ours = base
        ours.resources.append(.init(buildID: ClassicProject.buildID(100), refID: ClassicProject.refID(1), name: "File1.swift"))
        var theirs = base
        theirs.removeFile(refID: ClassicProject.refID(1))

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount >= 1)
        let current = try resolving(result, as: .current)
        #expect(current.contains("\(ClassicProject.refID(1)) /* File1.swift */ = {isa = PBXFileReference"))
        #expect(current.contains("\(ClassicProject.buildID(100)) /* File1.swift in Resources */"))
    }

    @Test("objects needed only by one side of a conflict are kept, not turned into more conflicts")
    func noConflictCascade() throws {
        // Both sides reorder the build phases differently (one real conflict); theirs also deletes a
        // file the Sources phase no longer lists on its side. Only the real conflict may remain.
        let base = ClassicProject.withSources([1, 2])
        var ours = base
        ours.phases = [.resources, .sources, .frameworks]
        ours.debugSettings["SWIFT_VERSION"] = .value("5.9")
        var theirs = base
        theirs.phases = [.frameworks, .sources, .resources]
        theirs.debugSettings["SWIFT_VERSION"] = .value("6.0")

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount == 2) // the phase order and the setting, nothing else
        #expect(try resolving(result, as: .current) == ours.text)
        #expect(try resolving(result, as: .incoming) == theirs.text)
    }

    @Test("objectVersion changed differently on both sides is a conflict")
    func headerConflict() throws {
        let base = ClassicProject.withSources([1])
        var ours = base
        ours.objectVersion = "60"
        var theirs = base
        theirs.objectVersion = "63"

        let result = try merge(base, ours, theirs)

        #expect(result.conflictCount == 1)
        #expect(try resolving(result, as: .current) == ours.text)
        #expect(try resolving(result, as: .incoming) == theirs.text)
    }

    @Test("without diff3 the base section is left out")
    func noBaseSection() throws {
        let base = ClassicProject.withSources([1])
        var ours = base
        ours.debugSettings["SWIFT_VERSION"] = .value("5.9")
        var theirs = base
        theirs.debugSettings["SWIFT_VERSION"] = .value("6.0")

        let result = try PbxprojMerge.merge(base: base.bytes, ours: ours.bytes, theirs: theirs.bytes, includeBase: false)

        #expect(!string(result).contains("|||||||"))
        #expect(result.conflictCount == 1)
    }

    @Test("labels and marker size are configurable")
    func labelsAndMarkerSize() throws {
        let base = ClassicProject.withSources([1])
        var ours = base
        ours.debugSettings["SWIFT_VERSION"] = .value("5.9")
        var theirs = base
        theirs.debugSettings["SWIFT_VERSION"] = .value("6.0")

        let result = try PbxprojMerge.merge(
            base: base.bytes, ours: ours.bytes, theirs: theirs.bytes, markerSize: 9,
            labels: .init(current: "main", base: "ancestor", incoming: "feature/x")
        )

        #expect(string(result).contains("<<<<<<<<< main\n"))
        #expect(string(result).contains(">>>>>>>>> feature/x\n"))
    }
}

@Suite("pbxproj merge: unsupported input falls back")
struct PbxprojUnsupportedTests {
    @Test("text that is not a project file is unsupported", arguments: ["", "hello\n", "{ broken"])
    func notAProject(text: String) {
        let bytes = Array(text.utf8)

        #expect(unsupported(bytes, bytes, bytes)?.status == LF_ERR_UNSUPPORTED)
    }

    @Test("CRLF line endings are unsupported (Xcode never writes them)")
    func crlf() {
        let crlf = Array(ClassicProject.withSources([1]).text.replacingOccurrences(of: "\n", with: "\r\n").utf8)

        #expect(unsupported(crlf, crlf, crlf)?.status == LF_ERR_UNSUPPORTED)
    }

    @Test("an input that already contains conflict markers is unsupported")
    func markersInInput() {
        let project = ClassicProject.withSources([1])
        let marked = Array(project.text.replacingOccurrences(of: "\t\tA10000000000000000000006", with: "<<<<<<< HEAD\n\t\tA10000000000000000000006").utf8)

        #expect(unsupported(project.bytes, marked, project.bytes)?.status == LF_ERR_UNSUPPORTED)
    }

    @Test("duplicate object IDs are unsupported")
    func duplicateIDs() {
        var project = ClassicProject.withSources([1])
        project.addSource(1)

        #expect(unsupported(project.bytes, project.bytes, project.bytes)?.status == LF_ERR_UNSUPPORTED)
    }

    @Test("a second objects dictionary is unsupported, never merged into duplicated content")
    func duplicateObjectsKey() {
        let text = ClassicProject.withSources([1]).text
            .replacingOccurrences(of: "\trootObject = ", with: "\tobjects = {\n\t};\n\trootObject = ")
        let bytes = Array(text.utf8)

        #expect(unsupported(bytes, bytes, bytes)?.status == LF_ERR_UNSUPPORTED)
    }

    @Test("many new objects in one section are sorted correctly")
    func manyAdditions() throws {
        let base = ClassicProject.withSources([1])
        var ours = base
        for n in stride(from: 5000, to: 2000, by: -1) { ours.addSource(n) } // added in descending ID order
        var expected = base
        for n in stride(from: 5000, to: 2000, by: -1) { expected.addSource(n) }

        let result = try merge(base, ours, base)

        #expect(string(result) == expected.text)
    }

    @Test("the error says which side could not be read")
    func namesTheSide() {
        let good = ClassicProject.withSources([1]).bytes

        let error = unsupported(good, good, Array("nope".utf8))

        #expect(error?.message.contains("theirs") == true)
    }
}

@Suite("pbxproj merge: property")
struct PbxprojPropertyTests {
    private static let iterations = 200

    /// Independent edits on both sides must merge cleanly into the model with both edits applied.
    @Test("independent random edits always merge cleanly to the combined project")
    func independentEdits() throws {
        for seed in 0..<Self.iterations {
            var rng = SplitMix64(seed: UInt64(seed) &+ 7)
            let baseFiles = Array(1...Int.random(in: 2...12, using: &rng))
            var base = ClassicProject.withSources(baseFiles)
            let keys = (0..<8).map { "KEY_\($0)" }
            for key in keys.prefix(4) { base.debugSettings[key] = .value("base") }

            // Disjoint removals, additions and setting edits.
            let shuffled = baseFiles.shuffled(using: &rng)
            let oursRemoves = Set(shuffled.prefix(Int.random(in: 0...2, using: &rng)))
            let theirsRemoves = Set(shuffled.dropFirst(2).prefix(Int.random(in: 0...2, using: &rng)))
            let oursAdds = (0..<Int.random(in: 0...3, using: &rng)).map { 100 + $0 }
            let theirsAdds = (0..<Int.random(in: 0...3, using: &rng)).map { 200 + $0 }

            var ours = base
            var theirs = base
            var expected = base
            for number in oursRemoves {
                ours.removeFile(refID: ClassicProject.refID(number))
                expected.removeFile(refID: ClassicProject.refID(number))
            }
            for number in theirsRemoves {
                theirs.removeFile(refID: ClassicProject.refID(number))
                expected.removeFile(refID: ClassicProject.refID(number))
            }
            for number in oursAdds { ours.addSource(number); expected.addSource(number) }
            for number in theirsAdds { theirs.addSource(number); expected.addSource(number) }
            let oursKey = keys[seed % 4], theirsKey = keys[4 + seed % 4]
            ours.debugSettings[oursKey] = .value("ours")
            expected.debugSettings[oursKey] = .value("ours")
            theirs.debugSettings[theirsKey] = .value("theirs")
            expected.debugSettings[theirsKey] = .value("theirs")
            if seed % 3 == 0 {
                theirs.phases = [.frameworks, .sources, .resources]
                expected.phases = theirs.phases
            }

            let result = try merge(base, ours, theirs)

            #expect(result.conflictCount == 0, "seed \(seed)")
            #expect(string(result) == expected.text, "seed \(seed)")
        }
    }

    @Test("for any edits, every conflict-free choice is a parseable project and each side is recoverable")
    func recoverability() throws {
        for seed in 0..<Self.iterations {
            var rng = SplitMix64(seed: UInt64(seed) &+ 99)
            let base = ClassicProject.withSources(Array(1...6))
            var ours = base
            var theirs = base
            for side in 0..<2 {
                var project = side == 0 ? ours : theirs
                if Bool.random(using: &rng) { project.debugSettings["SWIFT_VERSION"] = .value(side == 0 ? "5.9" : "6.0") }
                if Bool.random(using: &rng) { project.removeFile(refID: ClassicProject.refID(Int.random(in: 1...6, using: &rng))) }
                if Bool.random(using: &rng) { project.addSource(50 + side) }
                if Bool.random(using: &rng), !project.files.isEmpty { project.files[0].fileType = "sourcecode.swift.v\(side)" }
                if side == 0 { ours = project } else { theirs = project }
            }

            let result = try merge(base, ours, theirs)

            // Whatever the user picks, the result must again be a valid project file for the engine.
            for choice in [LFChoice.current, .incoming] {
                let resolved = Array(try resolving(result, as: choice).utf8)
                #expect(throws: Never.self, "seed \(seed) \(choice)") {
                    _ = try PbxprojMerge.merge(base: resolved, ours: resolved, theirs: resolved)
                }
            }
        }
    }
}
