import Foundation

public struct ScannedFile: Equatable, Sendable {
    public var relativePath: String
    public var keyCount: Int
    public var isSelectedByDefault: Bool

    public init(relativePath: String, keyCount: Int, isSelectedByDefault: Bool) {
        self.relativePath = relativePath
        self.keyCount = keyCount
        self.isSelectedByDefault = isSelectedByDefault
    }
}

public enum ProjectScanner {
    public static let skippedDirectoryNames: Set<String> = [
        "node_modules", "vendor", ".git", "dist", "build", ".next", ".turbo", ".claude",
    ]
    static let templateSuffixes = [".example", ".sample", ".template"]

    public static func scan(root: URL) -> [ScannedFile] {
        let fm = FileManager.default
        let rootURL = root.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = rootURL.path
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: keys) else { return [] }

        var results: [ScannedFile] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = url.lastPathComponent
            if values?.isDirectory == true {
                // A folder with its own .git entry is another repo or a git worktree copy.
                let isOtherRepo = fm.fileExists(atPath: url.appendingPathComponent(".git").path)
                if skippedDirectoryNames.contains(name) || isOtherRepo {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true, name == ".env" || name.hasPrefix(".env.") else { continue }
            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(rootPath + "/") else { continue }
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            results.append(ScannedFile(
                relativePath: String(path.dropFirst(rootPath.count + 1)),
                keyCount: DotEnvParser.parse(text).pairs.count,
                isSelectedByDefault: !templateSuffixes.contains { name.hasSuffix($0) }
            ))
        }
        return results.sorted { $0.relativePath < $1.relativePath }
    }
}
