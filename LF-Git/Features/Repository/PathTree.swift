import Foundation

/// Slash-separated paths (files, or branch names such as `feature/login`) grouped into folders for an expandable list.
nonisolated struct PathNode<Item>: Identifiable {
    /// The folder's path, or the item's own path for a leaf.
    let id: String
    /// What the row shows: one path component, or several joined when a folder holds only another folder.
    let name: String
    /// Set for a leaf.
    let item: Item?
    /// Set for a folder.
    let children: [PathNode]?

    var isFolder: Bool { children != nil }

    /// Every item at or below this node, in list order.
    var items: [Item] {
        if let item { return [item] }
        return (children ?? []).flatMap(\.items)
    }

    private struct Entry {
        let path: String
        let parts: ArraySlice<String>
        let item: Item
    }

    /// Builds the tree. Folders come first, each level sorted by name; a folder with a single folder inside is shown
    /// as one row (`a/b/c`) so deep, narrow paths do not need a click per level.
    static func build(_ items: [Item], path: (Item) -> String) -> [PathNode] {
        let entries = items.map { item -> Entry in
            let full = path(item)
            return Entry(path: full, parts: full.split(separator: "/").map(String.init)[...], item: item)
        }
        return level(entries, prefix: "")
    }

    private static func level(_ entries: [Entry], prefix: String) -> [PathNode] {
        var leaves: [PathNode] = []
        var folders: [String: [Entry]] = [:]
        for entry in entries {
            guard let first = entry.parts.first else { continue }
            if entry.parts.count == 1 {
                leaves.append(PathNode(id: entry.path, name: first, item: entry.item, children: nil))
            } else {
                folders[first, default: []].append(Entry(path: entry.path, parts: entry.parts.dropFirst(), item: entry.item))
            }
        }
        let names = folders.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var folderNodes: [PathNode] = []
        for name in names {
            let id = prefix + name + "/"
            let children = level(folders[name] ?? [], prefix: id)
            if children.count == 1, let only = children.first, only.isFolder {
                folderNodes.append(PathNode(id: only.id, name: name + "/" + only.name, item: nil, children: only.children))
            } else {
                folderNodes.append(PathNode(id: id, name: name, item: nil, children: children))
            }
        }
        return folderNodes + leaves.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
