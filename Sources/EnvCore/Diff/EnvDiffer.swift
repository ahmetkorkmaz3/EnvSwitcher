import Foundation

public struct DotEnvChange: Equatable, Sendable {
    public var key: String
    public var oldValue: String
    public var newValue: String

    public init(key: String, oldValue: String, newValue: String) {
        self.key = key
        self.oldValue = oldValue
        self.newValue = newValue
    }
}

public struct EnvDiff: Equatable, Sendable {
    public var added: [DotEnvPair]
    public var changed: [DotEnvChange]
    public var removed: [String]

    public var isEmpty: Bool { added.isEmpty && changed.isEmpty && removed.isEmpty }
}

public enum EnvDiffer {
    public static func diff(old: [DotEnvPair], new: [DotEnvPair]) -> EnvDiff {
        let oldValues = Dictionary(old.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        let newKeys = Set(new.map(\.key))
        let added = new.filter { oldValues[$0.key] == nil }
        let changed = new.compactMap { pair -> DotEnvChange? in
            guard let oldValue = oldValues[pair.key], oldValue != pair.value else { return nil }
            return DotEnvChange(key: pair.key, oldValue: oldValue, newValue: pair.value)
        }
        let removed = old.map(\.key).filter { !newKeys.contains($0) }
        return EnvDiff(added: added, changed: changed, removed: removed)
    }
}
