import Foundation

/// How a file is merged: Xcode project files object by object, everything else line by line.
public enum MergeStrategy: Sendable, Equatable {
    case pbxproj
    case text

    public static func forPath(_ path: String) -> MergeStrategy {
        path.hasSuffix(".pbxproj") ? .pbxproj : .text
    }
}

/// A last check before a semantically merged project replaces anything: it must still be a property list.
public enum PropertyListCheck {
    public static func isValid(_ bytes: [UInt8]) -> Bool {
        (try? PropertyListSerialization.propertyList(from: Data(bytes), options: [], format: nil)) != nil
    }
}
