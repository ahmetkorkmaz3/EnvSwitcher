import Foundation

public enum DotEnvSerializer {
    public static func serialize(_ pairs: [DotEnvPair], headerLines: [String] = []) -> String {
        let lines = headerLines.map { "# " + $0 } + pairs.map { "\($0.key)=\(encode($0.value))" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Wraps the value in double quotes when the parser would otherwise change it.
    static func encode(_ value: String) -> String {
        let special: Set<UnicodeScalar> = [" ", "\t", "#", "\"", "'", "\n", "\r", "\\"]
        guard value.unicodeScalars.contains(where: special.contains) else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
