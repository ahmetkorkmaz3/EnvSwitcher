import Foundation
import Testing
@testable import EnvCore

struct ProjectImporterTests {
    @Test func importsFilesIntoChosenEnvironment() throws {
        let root = try TempDir.make()
        let text = "A=1\nAPI_TOKEN=s3cret\nbad line\n"
        try TempDir.write(text, to: "apps/cart/.env.local", in: root)
        try TempDir.write("B=2\n", to: "apps/shell/.env.local", in: root)
        let envs = EnvEnvironment.defaults()
        let secrets = InMemorySecretStore()

        let result = try ProjectImporter(secrets: secrets).makeProject(
            name: "my-app",
            root: root,
            relativePaths: ["apps/cart/.env.local", "apps/shell/.env.local"],
            environments: envs,
            importInto: envs[0].id
        )

        let project = result.project
        #expect(project.name == "my-app")
        #expect(project.rootPath == root.path)
        #expect(project.environments == envs)
        #expect(project.targets.map(\.relativePath) == ["apps/cart/.env.local", "apps/shell/.env.local"])

        let cart = project.targets[0]
        #expect(cart.activeEnvironmentId == envs[0].id)
        #expect(cart.lastWrittenHash == ContentHash.sha256(Data(text.utf8)))
        #expect(cart.entries(for: envs[0].id) == [
            EnvEntry(key: "A", value: "1"),
            EnvEntry(key: "API_TOKEN", value: nil, isSecret: true),
        ])
        #expect(cart.entries(for: envs[1].id).isEmpty)

        let account = SecretAccount.make(projectId: project.id, targetId: cart.id, environmentId: envs[0].id, key: "API_TOKEN")
        #expect(secrets.snapshot == [account: "s3cret"])
        #expect(result.warnings == ["apps/cart/.env.local": [.invalidLine(line: 3)]])
    }

    @Test func secretValueNeverReachesStoreJSON() throws {
        let root = try TempDir.make()
        try TempDir.write("A=1\nAPI_TOKEN=s3cret-value\n", to: ".env", in: root)
        let envs = EnvEnvironment.defaults()
        let project = try ProjectImporter(secrets: InMemorySecretStore()).makeProject(
            name: "my-app", root: root, relativePaths: [".env"], environments: envs, importInto: envs[0].id
        ).project

        let json = String(decoding: try JSONEncoder().encode(Store(projects: [project])), as: UTF8.self)

        #expect(json.contains("API_TOKEN"))
        #expect(!json.contains("s3cret-value"))
    }

    @Test func throwsWhenFileIsMissing() throws {
        let root = try TempDir.make()
        let envs = EnvEnvironment.defaults()
        #expect(throws: (any Error).self) {
            try ProjectImporter(secrets: InMemorySecretStore()).makeProject(
                name: "x", root: root, relativePaths: [".env"], environments: envs, importInto: envs[0].id)
        }
    }

    @Test func addTargetImportsTheFileIntoTheProjectEnvironment() throws {
        var f = try ProjectFixture()
        let test = f.test
        for target in f.project.targets {
            f.update(target) { $0.activeEnvironmentId = test }
        }
        let text = "A=1\nAPI_TOKEN=s3cret\n"
        try TempDir.write(text, to: "apps/plp/.env.local", in: f.root)

        let result = try ProjectImporter(secrets: f.secrets).addTarget(relativePath: "apps/plp/.env.local", to: f.project)

        let added = try #require(result.project.targets.last)
        #expect(added.relativePath == "apps/plp/.env.local")
        #expect(added.activeEnvironmentId == f.test)
        #expect(added.lastWrittenHash == ContentHash.sha256(Data(text.utf8)))
        #expect(added.entries(for: f.test) == [
            EnvEntry(key: "A", value: "1"),
            EnvEntry(key: "API_TOKEN", value: nil, isSecret: true),
        ])
        #expect(f.secrets.snapshot == [f.account(added, f.test, "API_TOKEN"): "s3cret"])
    }

    @Test func addTargetUsesTheFirstEnvironmentWhenTheProjectIsMixed() throws {
        let f = try ProjectFixture()
        try TempDir.write("A=1\n", to: "apps/plp/.env.local", in: f.root)
        let result = try ProjectImporter(secrets: f.secrets).addTarget(relativePath: "apps/plp/.env.local", to: f.project)
        #expect(result.project.targets.last?.activeEnvironmentId == f.local)
    }

    @Test func addTargetRejectsAKnownFile() throws {
        let f = try ProjectFixture()
        #expect(throws: ProjectEditor.EditError.duplicateTarget("apps/cart/.env.local")) {
            try ProjectImporter(secrets: f.secrets).addTarget(relativePath: "apps/cart/.env.local", to: f.project)
        }
    }
}
