import Foundation

/// One key of a target and its value in every environment.
public struct ComparisonRow: Equatable, Identifiable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Every environment has the key with the same value.
        case same
        /// Every environment has the key, but the values are not all the same.
        case different
        /// One or more environments do not have the key.
        case missing
    }

    public var id: String { key }
    public var key: String
    /// Keyed by environment id. An environment without the key has no entry.
    public var values: [UUID: String]
    /// True when the key is secret in any environment.
    public var isSecret: Bool
    public var status: Status

    public init(key: String, values: [UUID: String], isSecret: Bool, status: Status) {
        self.key = key
        self.values = values
        self.isSecret = isSecret
        self.status = status
    }
}

public struct EnvComparer: Sendable {
    let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    /// Returns every key of the target in environment order, then entry order.
    /// Secret values come from the SecretStore. A secret with no stored value shows as empty.
    public func compare(project: Project, targetId: UUID) throws -> [ComparisonRow] {
        guard let target = project.targets.first(where: { $0.id == targetId }) else {
            throw EntryEditor.EditError.unknownTarget
        }
        var order: [String] = []
        var valuesByKey: [String: [UUID: String]] = [:]
        var secretKeys = Set<String>()

        for environment in project.environments {
            for entry in target.entries(for: environment.id) {
                if valuesByKey[entry.key] == nil {
                    order.append(entry.key)
                    valuesByKey[entry.key] = [:]
                }
                if entry.isSecret {
                    secretKeys.insert(entry.key)
                    let account = SecretAccount.make(projectId: project.id, targetId: target.id, environmentId: environment.id, key: entry.key)
                    valuesByKey[entry.key]?[environment.id] = try secrets.read(account: account) ?? ""
                } else {
                    valuesByKey[entry.key]?[environment.id] = entry.value ?? ""
                }
            }
        }

        let environmentIds = project.environments.map(\.id)
        return order.map { key in
            let values = valuesByKey[key] ?? [:]
            return ComparisonRow(key: key, values: values, isSecret: secretKeys.contains(key), status: Self.status(values, environmentIds))
        }
    }

    /// The keys that other environments have and this environment does not. Reads no secrets.
    public static func missingKeys(in environmentId: UUID, target: EnvTarget, project: Project) -> [String] {
        let own = Set(target.entries(for: environmentId).map(\.key))
        var seen = Set<String>()
        var result: [String] = []
        for environment in project.environments where environment.id != environmentId {
            for entry in target.entries(for: environment.id) where !own.contains(entry.key) && seen.insert(entry.key).inserted {
                result.append(entry.key)
            }
        }
        return result
    }

    private static func status(_ values: [UUID: String], _ environmentIds: [UUID]) -> ComparisonRow.Status {
        if environmentIds.contains(where: { values[$0] == nil }) { return .missing }
        return Set(values.values).count > 1 ? .different : .same
    }
}
