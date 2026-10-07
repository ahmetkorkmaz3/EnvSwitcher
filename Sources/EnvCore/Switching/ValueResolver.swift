import Foundation

public struct ValueResolver: Sendable {
    let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    /// Returns the key/value pairs of one environment, with secrets read from the SecretStore.
    /// A secret with no stored value becomes an empty string.
    public func resolve(project: Project, target: EnvTarget, environmentId: UUID) throws -> [DotEnvPair] {
        try target.entries(for: environmentId).map { entry in
            guard entry.isSecret else { return DotEnvPair(key: entry.key, value: entry.value ?? "") }
            let account = SecretAccount.make(projectId: project.id, targetId: target.id, environmentId: environmentId, key: entry.key)
            return DotEnvPair(key: entry.key, value: try secrets.read(account: account) ?? "")
        }
    }
}
