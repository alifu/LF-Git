import Foundation

/// A small model of a classic (group-based) Xcode project that renders exactly the way Xcode writes
/// project.pbxproj: tabs, sections sorted by name, objects sorted by ID, single-line build files and
/// file references. Tests derive base/ours/theirs from it and the expected merge from a combined model.
public struct ClassicProject: Equatable {
    public struct File: Equatable {
        public var name: String
        public let refID: String
        public var fileType = "sourcecode.swift"
        public var displayName: String?

        public init(name: String, refID: String) {
            self.name = name
            self.refID = refID
        }
    }

    public struct Build: Equatable {
        public let buildID: String
        public let refID: String
        public let name: String

        public init(buildID: String, refID: String, name: String) {
            self.buildID = buildID
            self.refID = refID
            self.name = name
        }
    }

    public enum Setting: Equatable {
        case value(String)
        case list([String])
    }

    public enum Phase: String {
        case sources, frameworks, resources
    }

    public init() {}

    public var objectVersion = "56"
    public var files: [File] = []
    public var sources: [Build] = []
    public var resources: [Build] = []
    public var phases: [Phase] = [.sources, .frameworks, .resources]
    public var knownRegions = ["en", "Base"]
    public var debugSettings: [String: Setting] = ["SWIFT_VERSION": .value("5.0"), "ONLY_ACTIVE_ARCH": .value("YES")]
    public var releaseSettings: [String: Setting] = ["SWIFT_VERSION": .value("5.0")]

    // Fixed object IDs (24 hex digits, like Xcode's).
    public static let projectID = "A10000000000000000000001"
    public static let mainGroupID = "A10000000000000000000002"
    public static let productsGroupID = "A10000000000000000000003"
    public static let sourceGroupID = "A10000000000000000000004"
    public static let targetID = "A10000000000000000000005"
    public static let productID = "A10000000000000000000006"
    public static let sourcesPhaseID = "A10000000000000000000007"
    public static let frameworksPhaseID = "A10000000000000000000008"
    public static let resourcesPhaseID = "A10000000000000000000009"
    public static let projectConfigListID = "A1000000000000000000000A"
    public static let projectDebugID = "A1000000000000000000000B"
    public static let projectReleaseID = "A1000000000000000000000C"

    public static func refID(_ number: Int) -> String { String(format: "B1%022X", number) }
    public static func buildID(_ number: Int) -> String { String(format: "C1%022X", number) }

    /// Adds a Swift file to the group and to the Sources phase.
    public mutating func addSource(_ number: Int, name: String? = nil) {
        let file = File(name: name ?? "File\(number).swift", refID: Self.refID(number))
        files.append(file)
        sources.append(Build(buildID: Self.buildID(number), refID: file.refID, name: file.name))
    }

    /// Removes a file everywhere it is used.
    public mutating func removeFile(refID: String) {
        files.removeAll { $0.refID == refID }
        sources.removeAll { $0.refID == refID }
        resources.removeAll { $0.refID == refID }
    }

    public static func withSources(_ numbers: [Int]) -> ClassicProject {
        var project = ClassicProject()
        numbers.forEach { project.addSource($0) }
        return project
    }

    // MARK: - Rendering

    private struct Entry {
        let section: String
        let id: String
        let text: String
    }

    public var text: String {
        let grouped = Dictionary(grouping: entries(), by: \.section)
        var out = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = \(objectVersion);\n\tobjects = {\n"
        for section in grouped.keys.sorted() {
            out += "\n/* Begin \(section) section */\n"
            for entry in grouped[section, default: []].sorted(by: { $0.id < $1.id }) {
                out += entry.text
            }
            out += "/* End \(section) section */\n"
        }
        out += "\t};\n\trootObject = \(Self.projectID) /* Project object */;\n}\n"
        return out
    }

    public var bytes: [UInt8] { Array(text.utf8) }

    public static func quoted(_ value: String) -> String {
        let bare = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.$/")
        if !value.isEmpty, value.unicodeScalars.allSatisfy(bare.contains) {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func object(_ id: String, comment: String?, _ lines: [String]) -> String {
        let label = comment.map { " /* \($0) */" } ?? ""
        return "\t\t\(id)\(label) = {\n" + lines.map { "\t\t\t\($0)\n" }.joined() + "\t\t};\n"
    }

    private func list(_ items: [String], indent: Int) -> String {
        let inner = String(repeating: "\t", count: indent + 1)
        return "(\n" + items.map { "\(inner)\($0),\n" }.joined() + String(repeating: "\t", count: indent) + ")"
    }

    private func settings(_ values: [String: Setting]) -> String {
        var out = "{\n"
        for key in values.keys.sorted() {
            switch values[key]! {
            case .value(let value):
                out += "\t\t\t\t\(Self.quoted(key)) = \(Self.quoted(value));\n"
            case .list(let items):
                out += "\t\t\t\t\(Self.quoted(key)) = \(list(items.map(Self.quoted), indent: 4));\n"
            }
        }
        return out + "\t\t\t}"
    }

    private func phaseObject(_ id: String, isa: String, comment: String, builds: [Build], suffix: String) -> String {
        object(id, comment: comment, [
            "isa = \(isa);",
            "buildActionMask = 2147483647;",
            "files = \(list(builds.map { "\($0.buildID) /* \($0.name) in \(suffix) */" }, indent: 3));",
            "runOnlyForDeploymentPostprocessing = 0;",
        ])
    }

    private func entries() -> [Entry] {
        var result: [Entry] = []
        for build in sources {
            result.append(Entry(section: "PBXBuildFile", id: build.buildID, text:
                "\t\t\(build.buildID) /* \(build.name) in Sources */ = {isa = PBXBuildFile; fileRef = \(build.refID) /* \(build.name) */; };\n"))
        }
        for build in resources {
            result.append(Entry(section: "PBXBuildFile", id: build.buildID, text:
                "\t\t\(build.buildID) /* \(build.name) in Resources */ = {isa = PBXBuildFile; fileRef = \(build.refID) /* \(build.name) */; };\n"))
        }
        result.append(Entry(section: "PBXFileReference", id: Self.productID, text:
            "\t\t\(Self.productID) /* App.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };\n"))
        var written = Set<String>()
        for file in files where written.insert(file.refID).inserted { // a file listed twice is still one object
            let name = file.displayName.map { "name = \(Self.quoted($0)); " } ?? ""
            result.append(Entry(section: "PBXFileReference", id: file.refID, text:
                "\t\t\(file.refID) /* \(file.name) */ = {isa = PBXFileReference; lastKnownFileType = \(file.fileType); \(name)path = \(Self.quoted(file.name)); sourceTree = \"<group>\"; };\n"))
        }
        result.append(Entry(section: "PBXFrameworksBuildPhase", id: Self.frameworksPhaseID, text:
            phaseObject(Self.frameworksPhaseID, isa: "PBXFrameworksBuildPhase", comment: "Frameworks", builds: [], suffix: "Frameworks")))
        result.append(Entry(section: "PBXResourcesBuildPhase", id: Self.resourcesPhaseID, text:
            phaseObject(Self.resourcesPhaseID, isa: "PBXResourcesBuildPhase", comment: "Resources", builds: resources, suffix: "Resources")))
        result.append(Entry(section: "PBXSourcesBuildPhase", id: Self.sourcesPhaseID, text:
            phaseObject(Self.sourcesPhaseID, isa: "PBXSourcesBuildPhase", comment: "Sources", builds: sources, suffix: "Sources")))
        result.append(contentsOf: groupEntries())
        result.append(Entry(section: "PBXNativeTarget", id: Self.targetID, text: targetObject()))
        result.append(Entry(section: "PBXProject", id: Self.projectID, text: projectObject()))
        result.append(contentsOf: configurationEntries())
        return result
    }

    private func groupEntries() -> [Entry] {
        [
            Entry(section: "PBXGroup", id: Self.mainGroupID, text: object(Self.mainGroupID, comment: nil, [
                "isa = PBXGroup;",
                "children = \(list(["\(Self.sourceGroupID) /* App */", "\(Self.productsGroupID) /* Products */"], indent: 3));",
                "sourceTree = \"<group>\";",
            ])),
            Entry(section: "PBXGroup", id: Self.productsGroupID, text: object(Self.productsGroupID, comment: "Products", [
                "isa = PBXGroup;",
                "children = \(list(["\(Self.productID) /* App.app */"], indent: 3));",
                "name = Products;",
                "sourceTree = \"<group>\";",
            ])),
            Entry(section: "PBXGroup", id: Self.sourceGroupID, text: object(Self.sourceGroupID, comment: "App", [
                "isa = PBXGroup;",
                "children = \(list(files.map { "\($0.refID) /* \($0.name) */" }, indent: 3));",
                "path = App;",
                "sourceTree = \"<group>\";",
            ])),
        ]
    }

    private func targetObject() -> String {
        let phaseRefs = phases.map { phase -> String in
            switch phase {
            case .sources: "\(Self.sourcesPhaseID) /* Sources */"
            case .frameworks: "\(Self.frameworksPhaseID) /* Frameworks */"
            case .resources: "\(Self.resourcesPhaseID) /* Resources */"
            }
        }
        return object(Self.targetID, comment: "App", [
            "isa = PBXNativeTarget;",
            "buildConfigurationList = \(Self.projectConfigListID) /* Build configuration list for PBXProject \"App\" */;",
            "buildPhases = \(list(phaseRefs, indent: 3));",
            "buildRules = \(list([], indent: 3));",
            "dependencies = \(list([], indent: 3));",
            "name = App;",
            "productName = App;",
            "productReference = \(Self.productID) /* App.app */;",
            "productType = \"com.apple.product-type.application\";",
        ])
    }

    private func projectObject() -> String {
        object(Self.projectID, comment: "Project object", [
            "isa = PBXProject;",
            "attributes = {\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastUpgradeCheck = 1500;\n\t\t\t};",
            "buildConfigurationList = \(Self.projectConfigListID) /* Build configuration list for PBXProject \"App\" */;",
            "developmentRegion = en;",
            "hasScannedForEncodings = 0;",
            "knownRegions = \(list(knownRegions, indent: 3));",
            "mainGroup = \(Self.mainGroupID);",
            "productRefGroup = \(Self.productsGroupID) /* Products */;",
            "projectDirPath = \"\";",
            "projectRoot = \"\";",
            "targets = \(list(["\(Self.targetID) /* App */"], indent: 3));",
        ])
    }

    private func configurationEntries() -> [Entry] {
        [
            Entry(section: "XCBuildConfiguration", id: Self.projectDebugID, text: object(Self.projectDebugID, comment: "Debug", [
                "isa = XCBuildConfiguration;", "buildSettings = \(settings(debugSettings));", "name = Debug;",
            ])),
            Entry(section: "XCBuildConfiguration", id: Self.projectReleaseID, text: object(Self.projectReleaseID, comment: "Release", [
                "isa = XCBuildConfiguration;", "buildSettings = \(settings(releaseSettings));", "name = Release;",
            ])),
            Entry(section: "XCConfigurationList", id: Self.projectConfigListID, text: object(
                Self.projectConfigListID, comment: "Build configuration list for PBXProject \"App\"", [
                    "isa = XCConfigurationList;",
                    "buildConfigurations = \(list(["\(Self.projectDebugID) /* Debug */", "\(Self.projectReleaseID) /* Release */"], indent: 3));",
                    "defaultConfigurationIsVisible = 0;",
                    "defaultConfigurationName = Release;",
                ]
            )),
        ]
    }
}
