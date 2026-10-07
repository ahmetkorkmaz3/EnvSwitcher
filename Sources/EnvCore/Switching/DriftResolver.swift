import Foundation

public struct DriftResolver: Sendable {
    let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    /// "Mevcut ortama kaydet": copies the file contents into one environment of the target.
    /// Changed keys get the new value, new keys go to the end, and missing keys are removed.
    public func saveFile(_ contents: String, into environmentId: UUID, targetId: UUID, project: Project) throws -> Project {
        guard let index = project.targetIndex(id: targetId) else { throw SwitchError.unknownTarget }
        let projectId = project.id
        let account = { (key: String) in
            SecretAccount.make(projectId: projectId, targetId: targetId, environmentId: environmentId, key: key)
        }
        let filePairs = DotEnvParser.parse(contents).pairs
        let fileValues = Dictionary(filePairs.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        let existing = project.targets[index].entries(for: environmentId)

        var entries: [EnvEntry] = []
        for entry in existing {
            guard let newValue = fileValues[entry.key] else {
                if entry.isSecret { try secrets.delete(account: account(entry.key)) }
                continue
            }
            if entry.isSecret {
                try secrets.write(newValue, account: account(entry.key))
                entries.append(entry)
            } else {
                entries.append(EnvEntry(key: entry.key, value: newValue))
            }
        }
        let existingKeys = Set(existing.map(\.key))
        for pair in filePairs where !existingKeys.contains(pair.key) {
            if SecretSuggester.isLikelySecret(pair.key) {
                try secrets.write(pair.value, account: account(pair.key))
                entries.append(EnvEntry(key: pair.key, value: nil, isSecret: true))
            } else {
                entries.append(EnvEntry(key: pair.key, value: pair.value))
            }
        }

        var project = project
        project.targets[index].setEntries(entries, for: environmentId)
        return project
    }
}
