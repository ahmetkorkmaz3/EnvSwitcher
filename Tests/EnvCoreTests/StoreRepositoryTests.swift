import Foundation
import Testing
@testable import EnvCore

struct StoreRepositoryTests {
    private let fixedDate = Date(timeIntervalSince1970: 1_791_400_000) // 2026-10-07 19:06:40 UTC

    private func sampleStore(name: String) -> Store {
        Store(projects: [Project(name: name, rootPath: "/tmp/x", environments: EnvEnvironment.defaults(), targets: [])])
    }

    @Test func loadReturnsEmptyStoreWhenFileIsMissing() throws {
        let repo = StoreRepository(directory: try TempDir.make())
        #expect(try repo.load() == StoreLoadResult(store: Store(), notice: nil))
    }

    @Test func saveThenLoadReturnsSameStore() throws {
        let repo = StoreRepository(directory: try TempDir.make().appendingPathComponent("nested"))
        let store = sampleStore(name: "karaca")
        try repo.save(store)
        #expect(try repo.load() == StoreLoadResult(store: store, notice: nil))
    }

    @Test func saveKeepsPreviousVersionAsBackup() throws {
        let repo = StoreRepository(directory: try TempDir.make())
        try repo.save(sampleStore(name: "first"))
        try repo.save(sampleStore(name: "second"))
        let backup = try JSONDecoder().decode(Store.self, from: Data(contentsOf: repo.backupURL))
        #expect(backup.projects.map(\.name) == ["first"])
    }

    @Test func loadUsesBackupWhenStoreIsCorrupt() throws {
        let repo = StoreRepository(directory: try TempDir.make())
        try repo.save(sampleStore(name: "first"))
        try repo.save(sampleStore(name: "second"))
        try Data("{ broken".utf8).write(to: repo.storeURL)
        let result = try repo.load()
        #expect(result.store.projects.map(\.name) == ["first"])
        #expect(result.notice == .restoredFromBackup)
    }

    @Test func loadUsesBackupWhenStoreIsMissing() throws {
        let repo = StoreRepository(directory: try TempDir.make())
        try repo.save(sampleStore(name: "first"))
        try repo.save(sampleStore(name: "second"))
        try FileManager.default.removeItem(at: repo.storeURL)
        let result = try repo.load()
        #expect(result.store.projects.map(\.name) == ["first"])
        #expect(result.notice == .restoredFromBackup)
    }

    @Test func loadResetsAndKeepsCorruptFileWhenBackupIsAlsoCorrupt() throws {
        let dir = try TempDir.make()
        let repo = StoreRepository(directory: dir, now: { [fixedDate] in fixedDate })
        try Data("{ broken".utf8).write(to: repo.storeURL)
        try Data("also broken".utf8).write(to: repo.backupURL)
        let result = try repo.load()
        let corrupt = dir.appendingPathComponent("store.json.corrupt-20261007-190640")
        #expect(result == StoreLoadResult(store: Store(), notice: .resetAfterCorruption(savedAs: corrupt)))
        #expect(FileManager.default.fileExists(atPath: corrupt.path))
        #expect(!FileManager.default.fileExists(atPath: repo.storeURL.path))
    }

    @Test func loadPropagatesReadErrorsInsteadOfResetting() throws {
        let repo = StoreRepository(directory: try TempDir.make())
        try repo.save(sampleStore(name: "first"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: repo.storeURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: repo.storeURL.path) }
        #expect(throws: (any Error).self) { try repo.load() }
        #expect(FileManager.default.fileExists(atPath: repo.storeURL.path))
    }

    @Test func defaultDirectoryIsInApplicationSupport() {
        #expect(StoreRepository.defaultDirectory.path.hasSuffix("Library/Application Support/EnvSwitcher"))
    }
}
