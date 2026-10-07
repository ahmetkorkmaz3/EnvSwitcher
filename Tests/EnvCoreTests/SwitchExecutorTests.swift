import Foundation
import Testing
@testable import EnvCore

struct SwitchExecutorTests {
    private let a = URL(fileURLWithPath: "/p/apps/a/.env.local")
    private let b = URL(fileURLWithPath: "/p/apps/b/.env.local")
    private let idA = UUID()
    private let idB = UUID()
    private let fixedDate = Date(timeIntervalSince1970: 1_791_400_000) // 20261007-190640 UTC

    private func writes() -> [PreparedWrite] {
        [
            PreparedWrite(targetId: idA, relativePath: "apps/a/.env.local", url: a, data: Data("A=new\n".utf8)),
            PreparedWrite(targetId: idB, relativePath: "apps/b/.env.local", url: b, data: Data("B=new\n".utf8)),
        ]
    }

    @Test func writesAllFilesAndReturnsHashes() throws {
        let files = FakeFileWriter()
        let hashes = try SwitchExecutor(files: files, recoveryDirectory: try TempDir.make()).execute(writes())
        #expect(files.contents == [a: Data("A=new\n".utf8), b: Data("B=new\n".utf8)])
        #expect(hashes == [
            idA: ContentHash.sha256(Data("A=new\n".utf8)),
            idB: ContentHash.sha256(Data("B=new\n".utf8)),
        ])
    }

    @Test func restoresEarlierFilesWhenALaterWriteFails() throws {
        let files = FakeFileWriter()
        files.contents = [a: Data("A=old\n".utf8), b: Data("B=old\n".utf8)]
        files.failingURL = b
        #expect(throws: SwitchError.writeFailed(path: "apps/b/.env.local", reason: "Failure()")) {
            try SwitchExecutor(files: files, recoveryDirectory: try TempDir.make()).execute(writes())
        }
        #expect(files.contents == [a: Data("A=old\n".utf8), b: Data("B=old\n".utf8)])
    }

    @Test func removesNewFilesWhenALaterWriteFails() throws {
        let files = FakeFileWriter()
        files.failingURL = b
        #expect(throws: SwitchError.self) {
            try SwitchExecutor(files: files, recoveryDirectory: try TempDir.make()).execute(writes())
        }
        #expect(files.contents.isEmpty)
    }

    @Test func savesRecoveryCopyWhenRollbackFails() throws {
        let files = FakeFileWriter()
        files.contents = [a: Data("A=old\n".utf8)]
        files.failingURL = b
        files.failEverythingAfterFirstFailure = true
        let recovery = try TempDir.make()
        let folder = recovery.appendingPathComponent("20261007-190640", isDirectory: true)

        #expect(throws: SwitchError.rollbackFailed(paths: ["apps/a/.env.local"], recoveryFolder: folder)) {
            try SwitchExecutor(files: files, recoveryDirectory: recovery, now: { [fixedDate] in fixedDate }).execute(writes())
        }
        #expect(try TempDir.read("apps__a__.env.local", in: folder) == "A=old\n")
    }

    @Test func reportsRecoveryFailureWhenRecoveryFolderCannotBeCreated() throws {
        let files = FakeFileWriter()
        files.contents = [a: Data("A=old\n".utf8)]
        files.failingURL = b
        files.failEverythingAfterFirstFailure = true
        let recovery = try TempDir.make()
        let blocker = recovery.appendingPathComponent("blocker")
        try Data().write(to: blocker)

        #expect(throws: SwitchError.recoveryFailed(paths: ["apps/a/.env.local"])) {
            try SwitchExecutor(files: files, recoveryDirectory: blocker.appendingPathComponent("recovery"), now: { [fixedDate] in fixedDate }).execute(writes())
        }
    }

    @Test func writesNoRecoveryFileForFileThatHadNoOldContent() throws {
        let files = FakeFileWriter()
        files.failingURL = b
        files.failEverythingAfterFirstFailure = true
        let recovery = try TempDir.make()
        let folder = recovery.appendingPathComponent("20261007-190640", isDirectory: true)

        #expect(throws: SwitchError.rollbackFailed(paths: ["apps/a/.env.local"], recoveryFolder: folder)) {
            try SwitchExecutor(files: files, recoveryDirectory: recovery, now: { [fixedDate] in fixedDate }).execute(writes())
        }
        let recoveryFile = folder.appendingPathComponent("apps__a__.env.local")
        #expect(!FileManager.default.fileExists(atPath: recoveryFile.path))
    }
}
