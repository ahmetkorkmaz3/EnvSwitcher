import Foundation
import Testing
@testable import EnvCore

struct ProjectEditorTests {
    @Test func addsEnvironment() throws {
        let f = try ProjectFixture()
        let p = ProjectEditor(secrets: f.secrets).addEnvironment(named: "staging", color: .blue, to: f.project)
        #expect(p.environments.map(\.name) == ["local", "test", "canli", "staging"])
        #expect(p.environments.last?.color == .blue)
        #expect(p.environments.last?.isProtected == false)
    }

    @Test func renamingEnvironmentKeepsSecretsReadable() throws {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "TOKEN", value: nil, isSecret: true)], target: f.cart, env: f.test)
        try f.secrets.write("t", account: f.account(f.cart, f.test, "TOKEN"))
        var renamed = f.envs[1]
        renamed.name = "staging"
        renamed.isProtected = true

        let p = try ProjectEditor(secrets: f.secrets).updateEnvironment(renamed, in: f.project)

        #expect(p.environment(id: f.test)?.name == "staging")
        #expect(p.environment(id: f.test)?.isProtected == true)
        let pairs = try ValueResolver(secrets: f.secrets).resolve(project: p, target: p.targets[0], environmentId: f.test)
        #expect(pairs == [DotEnvPair(key: "TOKEN", value: "t")])
    }

    @Test func deletingEnvironmentClearsActiveStateAndSecrets() throws {
        var f = try ProjectFixture()
        let test = f.test
        f.setEntries([EnvEntry(key: "TOKEN", value: nil, isSecret: true)], target: f.cart, env: test)
        f.update(f.cart) { $0.activeEnvironmentId = test }
        try f.secrets.write("t", account: f.account(f.cart, test, "TOKEN"))

        let p = try ProjectEditor(secrets: f.secrets).deleteEnvironment(id: test, from: f.project)

        #expect(p.environments.map(\.name) == ["local", "canli"])
        #expect(p.targets[0].activeEnvironmentId == nil)
        #expect(p.targets[0].values[test.uuidString] == nil)
        #expect(f.secrets.snapshot.isEmpty)
    }

    @Test func refusesToDeleteLastEnvironment() throws {
        let f = try ProjectFixture()
        let editor = ProjectEditor(secrets: f.secrets)
        var p = try editor.deleteEnvironment(id: f.local, from: f.project)
        p = try editor.deleteEnvironment(id: f.test, from: p)
        #expect(throws: ProjectEditor.EditError.lastEnvironment) {
            try editor.deleteEnvironment(id: f.canli, from: p)
        }
    }

    @Test func addsAndRemovesTargets() throws {
        var f = try ProjectFixture()
        let local = f.local
        f.setEntries([EnvEntry(key: "TOKEN", value: nil, isSecret: true)], target: f.cart, env: local)
        try f.secrets.write("t", account: f.account(f.cart, local, "TOKEN"))
        let editor = ProjectEditor(secrets: f.secrets)

        var p = try editor.addTarget(relativePath: "apps/plp/.env.local", to: f.project)
        #expect(p.targets.map(\.relativePath) == ["apps/cart/.env.local", "apps/shell/.env.local", "apps/plp/.env.local"])
        #expect(throws: ProjectEditor.EditError.duplicateTarget("apps/plp/.env.local")) {
            try editor.addTarget(relativePath: "apps/plp/.env.local", to: p)
        }

        p = try editor.removeTarget(id: f.cart.id, from: p)
        #expect(p.targets.map(\.relativePath) == ["apps/shell/.env.local", "apps/plp/.env.local"])
        #expect(f.secrets.snapshot.isEmpty)
    }

    @Test func relocateChangesRootPath() throws {
        let f = try ProjectFixture()
        let p = ProjectEditor(secrets: f.secrets).relocate(f.project, to: URL(fileURLWithPath: "/tmp/moved/"))
        #expect(p.rootPath == "/tmp/moved")
    }

    @Test func deleteAllSecretsRemovesEverySecretOfProject() throws {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "T1", value: nil, isSecret: true)], target: f.cart, env: f.local)
        f.setEntries([EnvEntry(key: "T2", value: nil, isSecret: true)], target: f.shell, env: f.canli)
        try f.secrets.write("1", account: f.account(f.cart, f.local, "T1"))
        try f.secrets.write("2", account: f.account(f.shell, f.canli, "T2"))
        try f.secrets.write("other", account: "other-project")

        try ProjectEditor(secrets: f.secrets).deleteAllSecrets(of: f.project)

        #expect(f.secrets.snapshot == ["other-project": "other"])
    }
}
