import Foundation

public struct SwitchExecutor: Sendable {
    let files: any FileWriter
    let recoveryDirectory: URL
    private let now: @Sendable () -> Date

    public init(files: any FileWriter = LocalFileWriter(), recoveryDirectory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.files = files
        self.recoveryDirectory = recoveryDirectory
        self.now = now
    }

    /// Step 5: writes every file or none. Returns the SHA-256 hash of each written file by target id.
    /// A write whose target has an entry in `expectedContents` goes ahead only when the file on disk
    /// still has those bytes (nil = missing). Otherwise nothing is written.
    public func execute(_ writes: [PreparedWrite], expectedContents: [UUID: Data?] = [:]) throws -> [UUID: String] {
        let originals = try writes.map { try files.read($0.url) }
        let changed = zip(writes, originals).filter { write, original in
            guard let expected = expectedContents[write.targetId] else { return false }
            return expected != original
        }
        guard changed.isEmpty else { throw SwitchError.fileChanged(paths: changed.map { $0.0.relativePath }) }
        for (index, write) in writes.enumerated() {
            do {
                try files.write(write.data, to: write.url)
            } catch {
                try rollback(Array(zip(writes[..<index], originals[..<index])))
                throw SwitchError.writeFailed(path: write.relativePath, reason: String(describing: error))
            }
        }
        return Dictionary(uniqueKeysWithValues: writes.map { ($0.targetId, ContentHash.sha256($0.data)) })
    }

    /// Puts back the old content. A file with no old content is removed.
    /// When this also fails, the old content goes to the recovery folder.
    private func rollback(_ written: [(PreparedWrite, Data?)]) throws {
        var failed: [(PreparedWrite, Data?)] = []
        for (write, original) in written {
            do {
                if let original {
                    try files.write(original, to: write.url)
                } else {
                    try files.remove(write.url)
                }
            } catch {
                failed.append((write, original))
            }
        }
        guard !failed.isEmpty else { return }

        let folder = recoveryDirectory.appendingPathComponent(Timestamp.string(now()), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            let pathsWithContent = failed.filter { _, original in original != nil }.map { $0.0.relativePath }
            throw SwitchError.recoveryFailed(paths: pathsWithContent)
        }

        var recoveryFailures: [String] = []
        for (write, original) in failed {
            guard let original else { continue }
            let name = write.relativePath.replacingOccurrences(of: "/", with: "__")
            do {
                try original.write(to: folder.appendingPathComponent(name))
            } catch {
                recoveryFailures.append(write.relativePath)
            }
        }

        if !recoveryFailures.isEmpty {
            throw SwitchError.recoveryFailed(paths: recoveryFailures)
        }
        throw SwitchError.rollbackFailed(paths: failed.map { $0.0.relativePath }, recoveryFolder: folder)
    }
}
