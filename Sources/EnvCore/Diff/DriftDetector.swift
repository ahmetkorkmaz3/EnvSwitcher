import Foundation

public enum DriftStatus: Equatable, Sendable {
    /// The file does not exist on disk.
    case missing
    /// The file matches the last content the app wrote.
    case clean
    /// The file changed after the app wrote it.
    case modified
    /// The file exists, but the app has no record of writing it.
    case unmanaged
}

public enum DriftDetector {
    public static func status(fileData: Data?, lastWrittenHash: String?) -> DriftStatus {
        guard let fileData else { return .missing }
        guard let lastWrittenHash else { return .unmanaged }
        return ContentHash.sha256(fileData) == lastWrittenHash ? .clean : .modified
    }
}
