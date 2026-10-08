/// Names for new keys and environments that do not clash with existing ones.
public enum UniqueName {
    /// "NEW_KEY_1", "NEW_KEY_2" and so on. The key goes into .env files, so it is the same in every language.
    public static func newKey(existing: Set<String>) -> String {
        var n = 1
        while existing.contains("NEW_KEY_\(n)") { n += 1 }
        return "NEW_KEY_\(n)"
    }

    /// `base`, then "base 2", "base 3" and so on. The caller gives a localized base.
    public static func numbered(base: String, existing: Set<String>) -> String {
        var name = base
        var n = 2
        while existing.contains(name) {
            name = "\(base) \(n)"
            n += 1
        }
        return name
    }
}
