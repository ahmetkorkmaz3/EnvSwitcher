import Foundation
import Testing
@testable import EnvCore

struct SwitchServiceTests {
    private func service(_ f: ProjectFixture) -> SwitchService {
        SwitchService(
            planner: SwitchPlanner(secrets: f.secrets),
            executor: SwitchExecutor(recoveryDirectory: f.root.appendingPathComponent("recovery"))
        )
    }

    @Test func commitWritesFilesAndUpdatesActiveEnvironmentAndHash() throws {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "A", value: "local")], target: f.cart, env: f.local)
        f.setEntries([EnvEntry(key: "B", value: "local")], target: f.shell, env: f.local)

        let updated = try service(f).commit(project: f.project, scope: .project, environmentId: f.local)

        for target in updated.targets {
            let data = try Data(contentsOf: updated.url(for: target))
            #expect(target.activeEnvironmentId == f.local)
            #expect(target.lastWrittenHash == ContentHash.sha256(data))
        }
        #expect(try TempDir.read("apps/cart/.env.local", in: f.root).hasSuffix("A=local\n"))
        #expect(updated.displayState == .single(f.local))
    }

    @Test func targetScopeChangesOnlyOneFile() throws {
        let f = try ProjectFixture()
        let updated = try service(f).commit(project: f.project, scope: .target(f.shell.id), environmentId: f.canli)
        #expect(updated.targets.map(\.activeEnvironmentId) == [nil, f.canli])
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("apps/cart/.env.local").path))
    }

    @Test func commitLeavesProjectUnchangedWhenDirectoryIsMissing() throws {
        let f = try ProjectFixture()
        try FileManager.default.removeItem(at: f.root.appendingPathComponent("apps/shell"))
        #expect(throws: SwitchError.directoryMissing(["apps/shell/.env.local"])) {
            try service(f).commit(project: f.project, scope: .project, environmentId: f.test)
        }
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("apps/cart/.env.local").path))
    }

    @Test func saveFileUpdatesChangedAddsNewAndRemovesMissingKeys() throws {
        var f = try ProjectFixture()
        f.setEntries([
            EnvEntry(key: "A", value: "1"),
            EnvEntry(key: "DB_PASSWORD", value: nil, isSecret: true),
            EnvEntry(key: "GONE", value: "x"),
            EnvEntry(key: "GONE_TOKEN", value: nil, isSecret: true),
        ], target: f.cart, env: f.local)
        try f.secrets.write("old-pass", account: f.account(f.cart, f.local, "DB_PASSWORD"))
        try f.secrets.write("old-token", account: f.account(f.cart, f.local, "GONE_TOKEN"))

        let file = "A=2\nDB_PASSWORD=new-pass\nNEW=3\nNEW_SECRET=s\n"
        let updated = try DriftResolver(secrets: f.secrets).saveFile(file, into: f.local, targetId: f.cart.id, project: f.project)

        #expect(updated.targets[0].entries(for: f.local) == [
            EnvEntry(key: "A", value: "2"),
            EnvEntry(key: "DB_PASSWORD", value: nil, isSecret: true),
            EnvEntry(key: "NEW", value: "3"),
            EnvEntry(key: "NEW_SECRET", value: nil, isSecret: true),
        ])
        #expect(f.secrets.snapshot == [
            f.account(f.cart, f.local, "DB_PASSWORD"): "new-pass",
            f.account(f.cart, f.local, "NEW_SECRET"): "s",
        ])
        #expect(updated.targets[1] == f.shell)
    }

    @Test func saveFileThrowsForUnknownTarget() throws {
        let f = try ProjectFixture()
        #expect(throws: SwitchError.unknownTarget) {
            try DriftResolver(secrets: f.secrets).saveFile("A=1", into: f.local, targetId: UUID(), project: f.project)
        }
    }
}
