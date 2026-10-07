import Foundation
import Testing
@testable import EnvCore

struct SwitchPlannerTests {
    private let header = "# EnvSwitcher tarafından üretildi — proje: karaca, ortam: test\n# Bu dosyayı elle düzenlerseniz, ortam değişirken uygulama sorar.\n"

    @Test func prepareBuildsHeaderAndResolvesSecrets() throws {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "A", value: "2"), EnvEntry(key: "TOKEN", value: nil, isSecret: true)], target: f.cart, env: f.test)
        try f.secrets.write("xyz", account: f.account(f.cart, f.test, "TOKEN"))

        let writes = try SwitchPlanner(secrets: f.secrets).prepare(project: f.project, scope: .target(f.cart.id), environmentId: f.test)

        #expect(writes.count == 1)
        #expect(writes[0].targetId == f.cart.id)
        #expect(writes[0].relativePath == "apps/cart/.env.local")
        #expect(writes[0].url == f.root.appendingPathComponent("apps/cart/.env.local"))
        #expect(String(decoding: writes[0].data, as: UTF8.self) == header + "A=2\nTOKEN=xyz\n")
    }

    @Test func prepareWritesHeaderOnlyForEmptyEnvironment() throws {
        let f = try ProjectFixture()
        let writes = try SwitchPlanner(secrets: f.secrets).prepare(project: f.project, scope: .project, environmentId: f.test)
        #expect(writes.map { String(decoding: $0.data, as: UTF8.self) } == [header, header])
    }

    @Test func prepareThrowsWhenDirectoryIsMissing() throws {
        let f = try ProjectFixture()
        try FileManager.default.removeItem(at: f.root.appendingPathComponent("apps/shell"))
        #expect(throws: SwitchError.directoryMissing(["apps/shell/.env.local"])) {
            try SwitchPlanner(secrets: f.secrets).prepare(project: f.project, scope: .project, environmentId: f.test)
        }
    }

    @Test func prepareStopsWhenSecretReadFails() throws {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "TOKEN", value: nil, isSecret: true)], target: f.cart, env: f.test)
        f.secrets.failReads = true
        #expect(throws: SecretStoreError.simulatedFailure) {
            try SwitchPlanner(secrets: f.secrets).prepare(project: f.project, scope: .project, environmentId: f.test)
        }
    }

    @Test func prepareThrowsForUnknownEnvironmentOrTarget() throws {
        let f = try ProjectFixture()
        let planner = SwitchPlanner(secrets: f.secrets)
        #expect(throws: SwitchError.unknownEnvironment) {
            try planner.prepare(project: f.project, scope: .project, environmentId: UUID())
        }
        #expect(throws: SwitchError.unknownTarget) {
            try planner.prepare(project: f.project, scope: .target(UUID()), environmentId: f.test)
        }
    }

    @Test func preflightReportsMissingDirectory() throws {
        let f = try ProjectFixture()
        try FileManager.default.removeItem(at: f.root.appendingPathComponent("apps/cart"))
        let result = try SwitchPlanner(secrets: f.secrets).preflight(project: f.project, scope: .project, environmentId: f.test)
        #expect(result.missingDirectories == ["apps/cart/.env.local"])
        #expect(result.targetIds == [f.cart.id, f.shell.id])
    }

    @Test func preflightIgnoresMissingAndCleanFiles() throws {
        var f = try ProjectFixture()
        try TempDir.write("A=1\n", to: "apps/cart/.env.local", in: f.root)
        f.update(f.cart) { $0.lastWrittenHash = ContentHash.sha256(Data("A=1\n".utf8)) }
        let result = try SwitchPlanner(secrets: f.secrets).preflight(project: f.project, scope: .project, environmentId: f.test)
        #expect(result.drifted.isEmpty)
        #expect(result.missingDirectories.isEmpty)
    }

    @Test func preflightReportsModifiedFileWithDiffAgainstActiveEnvironment() throws {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "A", value: "1"), EnvEntry(key: "C", value: "3")], target: f.cart, env: f.local)
        let local = f.local // read before the mutating call: the closure cannot capture `f`
        f.update(f.cart) {
            $0.activeEnvironmentId = local
            $0.lastWrittenHash = "stale"
        }
        try TempDir.write("A=9\nB=2\n", to: "apps/cart/.env.local", in: f.root)

        let result = try SwitchPlanner(secrets: f.secrets).preflight(project: f.project, scope: .project, environmentId: f.test)

        #expect(result.drifted == [DriftedTarget(
            targetId: f.cart.id,
            relativePath: "apps/cart/.env.local",
            status: .modified,
            diff: EnvDiff(
                added: [DotEnvPair(key: "B", value: "2")],
                changed: [DotEnvChange(key: "A", oldValue: "1", newValue: "9")],
                removed: ["C"]
            ),
            fileContents: "A=9\nB=2\n"
        )])
    }

    @Test func preflightReportsUnmanagedFileWithAllKeysAdded() throws {
        let f = try ProjectFixture()
        try TempDir.write("A=1\n", to: "apps/shell/.env.local", in: f.root)
        let result = try SwitchPlanner(secrets: f.secrets).preflight(project: f.project, scope: .project, environmentId: f.test)
        #expect(result.drifted.map(\.status) == [.unmanaged])
        #expect(result.drifted.first?.diff.added == [DotEnvPair(key: "A", value: "1")])
    }

    @Test func preflightAsksConfirmationOnlyForProtectedEnvironment() throws {
        let f = try ProjectFixture()
        let planner = SwitchPlanner(secrets: f.secrets)
        #expect(try planner.preflight(project: f.project, scope: .project, environmentId: f.canli).needsProtectedConfirmation)
        #expect(try !planner.preflight(project: f.project, scope: .project, environmentId: f.test).needsProtectedConfirmation)
    }

    @Test func targetScopeLimitsPreflightToOneFile() throws {
        let f = try ProjectFixture()
        let result = try SwitchPlanner(secrets: f.secrets).preflight(project: f.project, scope: .target(f.shell.id), environmentId: f.test)
        #expect(result.targetIds == [f.shell.id])
    }

    @Test func preflightReturnsObservedFileContents() throws {
        let f = try ProjectFixture()
        try TempDir.write("A=1\n", to: "apps/cart/.env.local", in: f.root)
        let result = try SwitchPlanner(secrets: f.secrets).preflight(project: f.project, scope: .project, environmentId: f.test)
        #expect(result.observed == [f.cart.id: Data("A=1\n".utf8), f.shell.id: Optional<Data>.none])
    }
}
