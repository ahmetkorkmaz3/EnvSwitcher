import Foundation

public struct EntryEditor: Sendable {
    public enum EditError: Error, Equatable {
        case unknownTarget
        case unknownKey(String)
        case duplicateKey(String)
        case invalidKey(String)
    }

    public enum CopyMode: Sendable {
        case overwrite
        case skipExisting
    }

    /// What a paste does to each key of the pasted text.
    public struct PastePlan: Equatable, Sendable {
        /// Keys that the environment does not have.
        public var added: [String] = []
        /// Keys that the environment has with an empty value.
        public var filled: [String] = []
        /// Keys that the environment has with a different, non-empty value.
        public var conflicts: [String] = []
        /// Keys that the environment has with the same value.
        public var unchanged: [String] = []

        public init() {}
    }

    let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    public func readValue(key: String, in project: Project, targetId: UUID, environmentId: UUID) throws -> String {
        guard let target = project.targets.first(where: { $0.id == targetId }) else { throw EditError.unknownTarget }
        guard let entry = target.entries(for: environmentId).first(where: { $0.key == key }) else {
            throw EditError.unknownKey(key)
        }
        guard entry.isSecret else { return entry.value ?? "" }
        return try secrets.read(account: account(project, targetId, environmentId, key)) ?? ""
    }

    public func addEntry(key: String, in project: Project, targetId: UUID, environmentId: UUID) throws -> Project {
        guard DotEnvParser.isValidKey(key) else { throw EditError.invalidKey(key) }
        return try mutate(project, targetId, environmentId) { entries in
            guard !entries.contains(where: { $0.key == key }) else { throw EditError.duplicateKey(key) }
            entries.append(EnvEntry(key: key, value: ""))
        }
    }

    public func removeEntry(key: String, in project: Project, targetId: UUID, environmentId: UUID) throws -> Project {
        try mutate(project, targetId, environmentId) { entries in
            let i = try index(of: key, in: entries)
            if entries[i].isSecret { try secrets.delete(account: account(project, targetId, environmentId, key)) }
            entries.remove(at: i)
        }
    }

    public func setValue(_ value: String, key: String, in project: Project, targetId: UUID, environmentId: UUID) throws -> Project {
        try mutate(project, targetId, environmentId) { entries in
            let i = try index(of: key, in: entries)
            if entries[i].isSecret {
                try secrets.write(value, account: account(project, targetId, environmentId, key))
            } else {
                entries[i].value = value
            }
        }
    }

    /// Sets the value. When the environment does not have the key, adds it at the end first.
    /// `isSecret` applies only to a new key. An existing key keeps its secret flag.
    public func upsertValue(_ value: String, key: String, isSecret: Bool, in project: Project, targetId: UUID, environmentId: UUID) throws -> Project {
        guard DotEnvParser.isValidKey(key) else { throw EditError.invalidKey(key) }
        return try mutate(project, targetId, environmentId) { entries in
            let secretAccount = account(project, targetId, environmentId, key)
            if let i = entries.firstIndex(where: { $0.key == key }) {
                if entries[i].isSecret {
                    try secrets.write(value, account: secretAccount)
                } else {
                    entries[i].value = value
                }
            } else if isSecret {
                try secrets.write(value, account: secretAccount)
                entries.append(EnvEntry(key: key, value: nil, isSecret: true))
            } else {
                entries.append(EnvEntry(key: key, value: value))
            }
        }
    }

    public func setSecret(_ isSecret: Bool, key: String, in project: Project, targetId: UUID, environmentId: UUID) throws -> Project {
        try mutate(project, targetId, environmentId) { entries in
            let i = try index(of: key, in: entries)
            guard entries[i].isSecret != isSecret else { return }
            let secretAccount = account(project, targetId, environmentId, key)
            if isSecret {
                try secrets.write(entries[i].value ?? "", account: secretAccount)
                entries[i].value = nil
            } else {
                entries[i].value = try secrets.read(account: secretAccount) ?? ""
                try secrets.delete(account: secretAccount)
            }
            entries[i].isSecret = isSecret
        }
    }

    public func renameKey(_ oldKey: String, to newKey: String, in project: Project, targetId: UUID, environmentId: UUID) throws -> Project {
        guard DotEnvParser.isValidKey(newKey) else { throw EditError.invalidKey(newKey) }
        guard oldKey != newKey else { return project }
        return try mutate(project, targetId, environmentId) { entries in
            let i = try index(of: oldKey, in: entries)
            guard !entries.contains(where: { $0.key == newKey }) else { throw EditError.duplicateKey(newKey) }
            if entries[i].isSecret {
                let oldAccount = account(project, targetId, environmentId, oldKey)
                try secrets.write(try secrets.read(account: oldAccount) ?? "", account: account(project, targetId, environmentId, newKey))
                try secrets.delete(account: oldAccount)
            }
            entries[i].key = newKey
        }
    }

    public func copyEntries(from source: UUID, to destination: UUID, targetId: UUID, mode: CopyMode, in project: Project) throws -> Project {
        guard let target = project.targets.first(where: { $0.id == targetId }) else { throw EditError.unknownTarget }
        let sourceEntries = target.entries(for: source)
        return try mutate(project, targetId, destination) { entries in
            for entry in sourceEntries {
                let existing = entries.firstIndex { $0.key == entry.key }
                if existing != nil, mode == .skipExisting { continue }

                let value = try entry.isSecret
                    ? (secrets.read(account: account(project, targetId, source, entry.key)) ?? "")
                    : (entry.value ?? "")
                let destinationAccount = account(project, targetId, destination, entry.key)
                if let existing, entries[existing].isSecret, !entry.isSecret {
                    try secrets.delete(account: destinationAccount)
                }
                if entry.isSecret { try secrets.write(value, account: destinationAccount) }

                let copied = EnvEntry(key: entry.key, value: entry.isSecret ? nil : value, isSecret: entry.isSecret)
                if let existing {
                    entries[existing] = copied
                } else {
                    entries.append(copied)
                }
            }
        }
    }

    public func planPaste(_ pairs: [DotEnvPair], in project: Project, targetId: UUID, environmentId: UUID) throws -> PastePlan {
        guard let target = project.targets.first(where: { $0.id == targetId }) else { throw EditError.unknownTarget }
        let existingKeys = Set(target.entries(for: environmentId).map(\.key))
        var plan = PastePlan()
        for pair in pairs {
            guard existingKeys.contains(pair.key) else {
                plan.added.append(pair.key)
                continue
            }
            let current = try readValue(key: pair.key, in: project, targetId: targetId, environmentId: environmentId)
            if current == pair.value {
                plan.unchanged.append(pair.key)
            } else if current.isEmpty {
                plan.filled.append(pair.key)
            } else {
                plan.conflicts.append(pair.key)
            }
        }
        return plan
    }

    /// Writes the pasted pairs to the environment. An empty existing value is always filled.
    /// `.skipExisting` keeps the existing non-empty values. A new key that looks like a secret goes to the SecretStore.
    public func pasteEntries(_ pairs: [DotEnvPair], mode: CopyMode, in project: Project, targetId: UUID, environmentId: UUID) throws -> Project {
        if let invalid = pairs.first(where: { !DotEnvParser.isValidKey($0.key) }) { throw EditError.invalidKey(invalid.key) }
        let plan = try planPaste(pairs, in: project, targetId: targetId, environmentId: environmentId)
        let skipped = Set(plan.unchanged + (mode == .skipExisting ? plan.conflicts : []))
        var updated = project
        for pair in pairs where !skipped.contains(pair.key) {
            updated = try upsertValue(
                pair.value,
                key: pair.key,
                isSecret: SecretSuggester.isLikelySecret(pair.key),
                in: updated,
                targetId: targetId,
                environmentId: environmentId
            )
        }
        return updated
    }

    /// Where `fillMissing` takes the value of a key from.
    public enum FillSource: Equatable, Sendable {
        /// The first environment, in project order, that has the key.
        case firstAvailable
        case environment(UUID)
    }

    public struct FillResult: Sendable {
        public var project: Project
        /// Keys that were added to one or more environments.
        public var filled: [String]
        /// Missing keys that the source environment does not have.
        public var skipped: [String]
    }

    /// Adds each missing key to every environment that does not have it. Existing values do not change.
    /// A key that is secret in any environment is secret in the new environments too.
    public func fillMissing(_ rows: [ComparisonRow], from source: FillSource, in project: Project, targetId: UUID) throws -> FillResult {
        var result = FillResult(project: project, filled: [], skipped: [])
        for row in rows where row.status == .missing {
            let value: String? = switch source {
            case .firstAvailable: project.environments.lazy.compactMap { row.values[$0.id] }.first
            case .environment(let id): row.values[id]
            }
            guard let value else {
                result.skipped.append(row.key)
                continue
            }
            for environment in project.environments where row.values[environment.id] == nil {
                result.project = try upsertValue(
                    value, key: row.key, isSecret: row.isSecret, in: result.project, targetId: targetId, environmentId: environment.id)
            }
            result.filled.append(row.key)
        }
        return result
    }

    private func account(_ project: Project, _ targetId: UUID, _ environmentId: UUID, _ key: String) -> String {
        SecretAccount.make(projectId: project.id, targetId: targetId, environmentId: environmentId, key: key)
    }

    private func index(of key: String, in entries: [EnvEntry]) throws -> Int {
        guard let i = entries.firstIndex(where: { $0.key == key }) else { throw EditError.unknownKey(key) }
        return i
    }

    private func mutate(
        _ project: Project,
        _ targetId: UUID,
        _ environmentId: UUID,
        _ change: (inout [EnvEntry]) throws -> Void
    ) throws -> Project {
        guard let targetIndex = project.targetIndex(id: targetId) else { throw EditError.unknownTarget }
        var updated = project
        var entries = updated.targets[targetIndex].entries(for: environmentId)
        try change(&entries)
        updated.targets[targetIndex].setEntries(entries, for: environmentId)
        return updated
    }
}
