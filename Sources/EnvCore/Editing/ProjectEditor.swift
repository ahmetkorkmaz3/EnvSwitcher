import Foundation

public struct ProjectEditor: Sendable {
    public enum EditError: Error, Equatable {
        case lastEnvironment
        case unknownEnvironment
        case unknownTarget
        case duplicateTarget(String)
    }

    let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    public func addEnvironment(named name: String, color: EnvColor, to project: Project) -> Project {
        var updated = project
        updated.environments.append(EnvEnvironment(name: name, color: color))
        return updated
    }

    /// Changes name, color or protection. Secrets stay readable because accounts use ids.
    public func updateEnvironment(_ environment: EnvEnvironment, in project: Project) throws -> Project {
        guard let i = project.environments.firstIndex(where: { $0.id == environment.id }) else {
            throw EditError.unknownEnvironment
        }
        var updated = project
        updated.environments[i] = environment
        return updated
    }

    public func deleteEnvironment(id: UUID, from project: Project) throws -> Project {
        guard project.environments.contains(where: { $0.id == id }) else { throw EditError.unknownEnvironment }
        guard project.environments.count > 1 else { throw EditError.lastEnvironment }
        var updated = project
        updated.environments.removeAll { $0.id == id }
        for i in updated.targets.indices {
            try deleteSecrets(project: project, target: updated.targets[i], environmentId: id)
            updated.targets[i].values[id.uuidString] = nil
            if updated.targets[i].activeEnvironmentId == id {
                updated.targets[i].activeEnvironmentId = nil
            }
        }
        return updated
    }

    public func addTarget(relativePath: String, to project: Project) throws -> Project {
        guard !project.targets.contains(where: { $0.relativePath == relativePath }) else {
            throw EditError.duplicateTarget(relativePath)
        }
        var updated = project
        updated.targets.append(EnvTarget(relativePath: relativePath))
        return updated
    }

    public func removeTarget(id: UUID, from project: Project) throws -> Project {
        guard let target = project.targets.first(where: { $0.id == id }) else { throw EditError.unknownTarget }
        for environment in project.environments {
            try deleteSecrets(project: project, target: target, environmentId: environment.id)
        }
        var updated = project
        updated.targets.removeAll { $0.id == id }
        return updated
    }

    public func relocate(_ project: Project, to root: URL) -> Project {
        var updated = project
        updated.rootPath = root.standardizedFileURL.path
        return updated
    }

    public func deleteAllSecrets(of project: Project) throws {
        for target in project.targets {
            for environment in project.environments {
                try deleteSecrets(project: project, target: target, environmentId: environment.id)
            }
        }
    }

    private func deleteSecrets(project: Project, target: EnvTarget, environmentId: UUID) throws {
        for entry in target.entries(for: environmentId) where entry.isSecret {
            try secrets.delete(account: SecretAccount.make(
                projectId: project.id, targetId: target.id, environmentId: environmentId, key: entry.key))
        }
    }
}
