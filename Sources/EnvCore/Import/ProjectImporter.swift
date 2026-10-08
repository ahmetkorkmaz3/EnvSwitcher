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
            let (target, fileWarnings) = try importTarget(relativePath: path, root: root, projectId: project.id, environmentId: environmentId)
            if !fileWarnings.isEmpty { warnings[path] = fileWarnings }
            project.targets.append(target)
        }
        return ImportResult(project: project, warnings: warnings)
    }

    /// Adds one more file to an existing project. Its contents go into the environment that is on
    /// disk for the whole project, or into the first environment when the files are mixed.
    public func addTarget(relativePath: String, to project: Project) throws -> ImportResult {
        guard !project.targets.contains(where: { $0.relativePath == relativePath }) else {
            throw ProjectEditor.EditError.duplicateTarget(relativePath)
        }
        let environmentId: UUID
        if case .single(let id) = project.displayState {
            environmentId = id
        } else {
            environmentId = project.environments[0].id
        }
        let (target, fileWarnings) = try importTarget(relativePath: relativePath, root: project.rootURL, projectId: project.id, environmentId: environmentId)
        var updated = project
        updated.targets.append(target)
        return ImportResult(project: updated, warnings: fileWarnings.isEmpty ? [:] : [relativePath: fileWarnings])
    }

    /// Reads the file and stores its values in one environment. Likely secrets go to the SecretStore.
    private func importTarget(relativePath: String, root: URL, projectId: UUID, environmentId: UUID) throws -> (EnvTarget, [DotEnvWarning]) {
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        let parsed = DotEnvParser.parse(String(decoding: data, as: UTF8.self))

        var target = EnvTarget(relativePath: relativePath, activeEnvironmentId: environmentId, lastWrittenHash: ContentHash.sha256(data))
        var entries: [EnvEntry] = []
        for pair in parsed.pairs {
            if SecretSuggester.isLikelySecret(pair.key) {
                let account = SecretAccount.make(projectId: projectId, targetId: target.id, environmentId: environmentId, key: pair.key)
                try secrets.write(pair.value, account: account)
                entries.append(EnvEntry(key: pair.key, value: nil, isSecret: true))
            } else {
                entries.append(EnvEntry(key: pair.key, value: pair.value))
            }
        }
        target.setEntries(entries, for: environmentId)
        return (target, parsed.warnings)
    }
}
