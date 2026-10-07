import Foundation

public enum SecretSuggester {
    /// `NEXT_PUBLIC_` values go to the browser, so they are never suggested as secrets.
    public static func isLikelySecret(_ key: String) -> Bool {
        let upper = key.uppercased()
        if upper.hasPrefix("NEXT_PUBLIC_") { return false }
        if upper.hasSuffix("_KEY") { return true }
        return ["SECRET", "PASSWORD", "TOKEN", "PRIVATE"].contains { upper.contains($0) }
    }
}
