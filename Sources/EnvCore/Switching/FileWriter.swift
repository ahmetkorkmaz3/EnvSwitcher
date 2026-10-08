import Foundation

public protocol FileWriter: Sendable {
    /// Returns nil when the file does not exist.
    func read(_ url: URL) throws -> Data?
    /// Writes to a temporary file in the same folder, then renames it over the target.
    func write(_ data: Data, to url: URL) throws
    /// Removing a file that does not exist is not an error.
    func remove(_ url: URL) throws
    func directoryExists(_ url: URL) -> Bool
}

public struct LocalFileWriter: FileWriter {
    public init() {}

    public func read(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// Writes through a symlink to the real file and keeps the old file permissions (for example 600).
    public func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let destination = url.resolvingSymlinksInPath()
        let permissions = try? fm.attributesOfItem(atPath: destination.path)[.posixPermissions]
        try data.write(to: destination, options: .atomic)
        if let permissions {
            try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: destination.path)
        }
    }

    public func remove(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
