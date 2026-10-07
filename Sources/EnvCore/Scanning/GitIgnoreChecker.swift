import Foundation

public enum GitIgnoreChecker {
    /// Returns true when git ignores the file, false when it does not, and nil when
    /// the folder is not a git repo or git cannot run.
    public static func isIgnored(relativePath: String, root: URL) -> Bool? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path, "check-ignore", "-q", "--", relativePath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        switch process.terminationStatus {
        case 0: return true
        case 1: return false
        default: return nil
        }
    }
}
