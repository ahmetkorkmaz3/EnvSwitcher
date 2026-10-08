import Foundation
import Testing
@testable import EnvCore

struct EnvComparerTests {
    private func fixture() throws -> ProjectFixture {
        var f = try ProjectFixture()
        f.setEntries([
            EnvEntry(key: "A", value: "1"),
            EnvEntry(key: "TOKEN", value: nil, isSecret: true),
            EnvEntry(key: "ONLY_LOCAL", value: "x"),
        ], target: f.cart, env: f.local)
        f.setEntries([
            EnvEntry(key: "A", value: "1"),
            EnvEntry(key: "TOKEN", value: nil, isSecret: true),
            EnvEntry(key: "ONLY_TEST", value: "y"),
        ], target: f.cart, env: f.test)
        f.setEntries([
            EnvEntry(key: "A", value: "1"),
            EnvEntry(key: "TOKEN", value: nil, isSecret: true),
        ], target: f.cart, env: f.canli)
        try f.secrets.write("t-local", account: f.account(f.cart, f.local, "TOKEN"))
        try f.secrets.write("t-test", account: f.account(f.cart, f.test, "TOKEN"))
        try f.secrets.write("t-canli", account: f.account(f.cart, f.canli, "TOKEN"))
        return f
    }

    @Test func comparesEveryKeyAcrossEnvironments() throws {
        let f = try fixture()
        let rows = try EnvComparer(secrets: f.secrets).compare(project: f.project, targetId: f.cart.id)

        #expect(rows.map(\.key) == ["A", "TOKEN", "ONLY_LOCAL", "ONLY_TEST"])
        #expect(rows[0] == ComparisonRow(key: "A", values: [f.local: "1", f.test: "1", f.canli: "1"], isSecret: false, status: .same))
        #expect(rows[1] == ComparisonRow(
            key: "TOKEN",
            values: [f.local: "t-local", f.test: "t-test", f.canli: "t-canli"],
            isSecret: true,
            status: .different
        ))
        #expect(rows[2] == ComparisonRow(key: "ONLY_LOCAL", values: [f.local: "x"], isSecret: false, status: .missing))
        #expect(rows[3].status == .missing)
        #expect(rows[3].values == [f.test: "y"])
    }

    @Test func emptyValueIsDifferentFromAFilledOne() throws {
        var f = try ProjectFixture()
        for env in [f.local, f.test, f.canli] {
            f.setEntries([EnvEntry(key: "A", value: env == f.test ? "" : "1")], target: f.cart, env: env)
        }
        let rows = try EnvComparer(secrets: f.secrets).compare(project: f.project, targetId: f.cart.id)
        #expect(rows.map(\.status) == [.different])
    }

    @Test func throwsForUnknownTarget() throws {
        let f = try fixture()
        #expect(throws: EntryEditor.EditError.unknownTarget) {
            try EnvComparer(secrets: f.secrets).compare(project: f.project, targetId: UUID())
        }
    }

    @Test func missingKeysListsKeysFromOtherEnvironments() throws {
        let f = try fixture()
        let target = f.project.targets[0]
        #expect(EnvComparer.missingKeys(in: f.local, target: target, project: f.project) == ["ONLY_TEST"])
        #expect(EnvComparer.missingKeys(in: f.canli, target: target, project: f.project) == ["ONLY_LOCAL", "ONLY_TEST"])
    }
}
