import Foundation

public struct FileTreeNode: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var targetId: UUID?
    /// nil for a file node.
    public var children: [FileTreeNode]?

    public init(id: String, name: String, targetId: UUID?, children: [FileTreeNode]?) {
        self.id = id
        self.name = name
        self.targetId = targetId
        self.children = children
    }
}

public enum FileTree {
    private final class Folder {
        var folders: [String: Folder] = [:]
        var files: [(name: String, id: UUID)] = []
    }

    public static func build(_ targets: [EnvTarget]) -> [FileTreeNode] {
        let root = Folder()
        for target in targets {
            var parts = target.relativePath.split(separator: "/").map(String.init)
            guard let fileName = parts.popLast() else { continue }
            var folder = root
            for part in parts {
                let next = folder.folders[part] ?? Folder()
                folder.folders[part] = next
                folder = next
            }
            folder.files.append((fileName, target.id))
        }
        return nodes(of: root, prefix: "")
    }

    private static func nodes(of folder: Folder, prefix: String) -> [FileTreeNode] {
        var result: [FileTreeNode] = []
        for name in folder.folders.keys.sorted() {
            let child = folder.folders[name]!
            let path = prefix + name
            if child.folders.isEmpty, child.files.count == 1 {
                let file = child.files[0]
                result.append(FileTreeNode(id: path + "/" + file.name, name: name + "/" + file.name, targetId: file.id, children: nil))
            } else {
                result.append(FileTreeNode(id: path, name: name, targetId: nil, children: nodes(of: child, prefix: path + "/")))
            }
        }
        for file in folder.files.sorted(by: { $0.name < $1.name }) {
            result.append(FileTreeNode(id: prefix + file.name, name: file.name, targetId: file.id, children: nil))
        }
        return result
    }
}
