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
