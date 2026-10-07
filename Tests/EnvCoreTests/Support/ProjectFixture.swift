import Foundation
@testable import EnvCore

/// A project with two targets (apps/cart/.env.local, apps/shell/.env.local) in a temp folder.
/// The target folders exist. The files do not.
struct ProjectFixture {
    let root: URL
    let envs = EnvEnvironment.defaults()
    let secrets = InMemorySecretStore()
    var project: Project

    init() throws {
        root = try TempDir.make()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("apps/cart"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("apps/shell"), withIntermediateDirectories: true)
        project = Project(
            name: "karaca",
            rootPath: root.path,
            environments: envs,
            targets: [EnvTarget(relativePath: "apps/cart/.env.local"), EnvTarget(relativePath: "apps/shell/.env.local")]
        )
    }

    var local: UUID { envs[0].id }
    var test: UUID { envs[1].id }
    var canli: UUID { envs[2].id }
    var cart: EnvTarget { project.targets[0] }
    var shell: EnvTarget { project.targets[1] }

    mutating func setEntries(_ entries: [EnvEntry], target: EnvTarget, env: UUID) {
        let index = project.targetIndex(id: target.id)!
        project.targets[index].setEntries(entries, for: env)
    }

    mutating func update(_ target: EnvTarget, _ change: (inout EnvTarget) -> Void) {
        let index = project.targetIndex(id: target.id)!
        change(&project.targets[index])
    }

    func account(_ target: EnvTarget, _ env: UUID, _ key: String) -> String {
        SecretAccount.make(projectId: project.id, targetId: target.id, environmentId: env, key: key)
    }
}
