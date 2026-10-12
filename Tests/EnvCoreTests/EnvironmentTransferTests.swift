import Foundation
import Testing
@testable import EnvCore

struct EnvironmentTransferTests {
    @Test func exportWritesPlainDotEnvWithSecretValues() throws {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "A", value: "1"), EnvEntry(key: "API_TOKEN", value: nil, isSecret: true)], target: f.cart, env: f.test)
        try f.secrets.write("s3 cret", account: f.account(f.cart, f.test, "API_TOKEN"))

        let text = try EnvironmentTransfer(secrets: f.secrets).exportText(project: f.project, targetId: f.cart.id, environmentId: f.test)

        #expect(text.hasPrefix("# Exported by EnvSwitcher — project: my-app, file: apps/cart/.env.local, environment: test\n"))
        #expect(text.hasSuffix("A=1\nAPI_TOKEN=\"s3 cret\"\n"))
        #expect(DotEnvParser.parse(text).pairs == [DotEnvPair(key: "A", value: "1"), DotEnvPair(key: "API_TOKEN", value: "s3 cret")])
    }

    @Test func exportFailsWhenSecretIsMissing() throws {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "API_TOKEN", value: nil, isSecret: true)], target: f.cart, env: f.test)

        #expect(throws: SwitchError.secretMissing(path: "apps/cart/.env.local", key: "API_TOKEN")) {
            try EnvironmentTransfer(secrets: f.secrets).exportText(project: f.project, targetId: f.cart.id, environmentId: f.test)
        }
    }

    @Test func suggestedNameComesFromExportHeader() {
        let text = "# Exported by EnvSwitcher — project: my-app, file: .env, environment: staging eu\nA=1\n"
        #expect(EnvironmentTransfer.suggestedEnvironmentName(in: text) == "staging eu")
        #expect(EnvironmentTransfer.suggestedEnvironmentName(in: "A=1\n") == nil)
    }

    @Test func importIntoNewEnvironmentAddsEnvironmentAndValues() throws {
        let f = try ProjectFixture()
        let text = "# Exported by EnvSwitcher — project: x, file: y, environment: test\nA=1\nAPI_TOKEN=s3cret\nbad line\n"

        let outcome = try EnvironmentTransfer(secrets: f.secrets).importText(
            text, into: .newEnvironment(name: "test 2", color: .purple), targetId: f.cart.id, project: f.project)

        let added = try #require(outcome.project.environments.last)
        #expect(outcome.project.environments.count == 4)
        #expect(added.name == "test 2")
        #expect(added.color == .purple)
        #expect(outcome.environmentId == added.id)
        let cart = outcome.project.targets[0]
        #expect(cart.entries(for: added.id) == [EnvEntry(key: "A", value: "1"), EnvEntry(key: "API_TOKEN", value: nil, isSecret: true)])
        #expect(cart.activeEnvironmentId == f.cart.activeEnvironmentId)
        #expect(outcome.project.targets[1].entries(for: added.id).isEmpty)
        let account = SecretAccount.make(projectId: f.project.id, targetId: f.cart.id, environmentId: added.id, key: "API_TOKEN")
        #expect(f.secrets.snapshot == [account: "s3cret"])
        #expect(outcome.warnings == [.invalidLine(line: 4)])
    }

    @Test func importIntoExistingEnvironmentReplacesValues() throws {
        var f = try ProjectFixture()
        f.setEntries([
            EnvEntry(key: "A", value: "old"),
            EnvEntry(key: "GONE", value: "x"),
            EnvEntry(key: "PASSWORD", value: nil, isSecret: true),
        ], target: f.cart, env: f.test)
        try f.secrets.write("old-secret", account: f.account(f.cart, f.test, "PASSWORD"))
        f.setEntries([EnvEntry(key: "L", value: "keep")], target: f.cart, env: f.local)

        let outcome = try EnvironmentTransfer(secrets: f.secrets).importText(
            "PASSWORD=new-secret\nA=new\nB=2\n", into: .existing(f.test), targetId: f.cart.id, project: f.project)

        #expect(outcome.environmentId == f.test)
        #expect(outcome.project.environments == f.project.environments)
        let cart = outcome.project.targets[0]
        #expect(cart.entries(for: f.test) == [
            EnvEntry(key: "A", value: "new"),
            EnvEntry(key: "PASSWORD", value: nil, isSecret: true),
            EnvEntry(key: "B", value: "2"),
        ])
        #expect(cart.entries(for: f.local) == [EnvEntry(key: "L", value: "keep")])
        #expect(f.secrets.snapshot == [f.account(f.cart, f.test, "PASSWORD"): "new-secret"])
    }

    @Test func importIntoUnknownEnvironmentFails() throws {
        let f = try ProjectFixture()
        #expect(throws: ProjectEditor.EditError.unknownEnvironment) {
            try EnvironmentTransfer(secrets: f.secrets).importText("A=1\n", into: .existing(UUID()), targetId: f.cart.id, project: f.project)
        }
    }

    @Test func exportThenImportRoundTrips() throws {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "MSG", value: "a \"b\" #c\nd"), EnvEntry(key: "SECRET_KEY", value: nil, isSecret: true)], target: f.cart, env: f.prod)
        try f.secrets.write("p@ss word", account: f.account(f.cart, f.prod, "SECRET_KEY"))
        let transfer = EnvironmentTransfer(secrets: f.secrets)

        let text = try transfer.exportText(project: f.project, targetId: f.cart.id, environmentId: f.prod)
        let outcome = try transfer.importText(text, into: .newEnvironment(name: "prod 2", color: .red), targetId: f.cart.id, project: f.project)

        let target = outcome.project.targets[0]
        let pairs = try ValueResolver(secrets: f.secrets).resolve(project: outcome.project, target: target, environmentId: outcome.environmentId)
        #expect(pairs == [DotEnvPair(key: "MSG", value: "a \"b\" #c\nd"), DotEnvPair(key: "SECRET_KEY", value: "p@ss word")])
        #expect(outcome.warnings.isEmpty)
    }
}
