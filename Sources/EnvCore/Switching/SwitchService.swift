import Foundation

public struct SwitchService: Sendable {
    public let planner: SwitchPlanner
    public let executor: SwitchExecutor

    public init(planner: SwitchPlanner, executor: SwitchExecutor) {
        self.planner = planner
        self.executor = executor
    }

    /// Steps 4–6: prepares the contents, writes the files, and returns the project
    /// with the new active environment and hash for each written target.
    public func commit(project: Project, scope: SwitchScope, environmentId: UUID) throws -> Project {
        let writes = try planner.prepare(project: project, scope: scope, environmentId: environmentId)
        let hashes = try executor.execute(writes)
        var project = project
        for (targetId, hash) in hashes {
            guard let index = project.targetIndex(id: targetId) else { continue }
            project.targets[index].activeEnvironmentId = environmentId
            project.targets[index].lastWrittenHash = hash
        }
        return project
    }
}
