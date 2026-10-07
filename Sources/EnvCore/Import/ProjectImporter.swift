import Foundation

public struct ImportResult: Sendable {
    public var project: Project
    /// Keyed by relative path. Only files with warnings appear.
    public var warnings: [String: [DotEnvWarning]]
}

public struct ProjectImporter: Sendable {
    let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    public func makeProject(
        name: String,
        root: URL,
        relativePaths: [String],
        environments: [EnvEnvironment],
        importInto environmentId: UUID
    ) throws -> ImportResult {
        var project = Project(name: name, rootPath: root.standardizedFileURL.path, environments: environments, targets: [])
        var warnings: [String: [DotEnvWarning]] = [:]

        for path in relativePaths {
            let data = try Data(contentsOf: root.appendingPathComponent(path))
            let parsed = DotEnvParser.parse(String(decoding: data, as: UTF8.self))
            if !parsed.warnings.isEmpty { warnings[path] = parsed.warnings }

            var target = EnvTarget(relativePath: path, activeEnvironmentId: environmentId, lastWrittenHash: ContentHash.sha256(data))
            var entries: [EnvEntry] = []
            for pair in parsed.pairs {
                if SecretSuggester.isLikelySecret(pair.key) {
                    let account = SecretAccount.make(projectId: project.id, targetId: target.id, environmentId: environmentId, key: pair.key)
                    try secrets.write(pair.value, account: account)
                    entries.append(EnvEntry(key: pair.key, value: nil, isSecret: true))
                } else {
                    entries.append(EnvEntry(key: pair.key, value: pair.value))
                }
            }
            target.setEntries(entries, for: environmentId)
            project.targets.append(target)
        }
        return ImportResult(project: project, warnings: warnings)
    }
}
