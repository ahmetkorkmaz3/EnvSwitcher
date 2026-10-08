import Foundation
import Testing
@testable import EnvCore

struct ModelsTests {
    private let envs = EnvEnvironment.defaults()

    private func project(_ targets: [EnvTarget]) -> Project {
        Project(name: "p", rootPath: "/tmp/p", environments: envs, targets: targets)
    }

    @Test func defaultsMarkOnlyProdAsProtected() {
        #expect(envs.map(\.name) == ["local", "test", "prod"])
        #expect(envs.map(\.isProtected) == [false, false, true])
        #expect(envs.map(\.color) == [.green, .orange, .red])
    }

    @Test func displayStateIsNoneWithoutActiveEnvironments() {
        #expect(project([EnvTarget(relativePath: ".env")]).displayState == .none)
    }

    @Test func displayStateIsSingleWhenAllTargetsMatch() {
        let p = project([
            EnvTarget(relativePath: "a/.env", activeEnvironmentId: envs[1].id),
            EnvTarget(relativePath: "b/.env", activeEnvironmentId: envs[1].id),
        ])
        #expect(p.displayState == .single(envs[1].id))
    }

    @Test func displayStateIsMixedWhenTargetsDiffer() {
        let p = project([
            EnvTarget(relativePath: "a/.env", activeEnvironmentId: envs[0].id),
            EnvTarget(relativePath: "b/.env", activeEnvironmentId: envs[2].id),
        ])
        #expect(p.displayState == .mixed)
    }

    @Test func displayStateIsMixedWhenOneTargetHasNoEnvironment() {
        let p = project([
            EnvTarget(relativePath: "a/.env", activeEnvironmentId: envs[0].id),
            EnvTarget(relativePath: "b/.env"),
        ])
        #expect(p.displayState == .mixed)
    }

    @Test func targetEntriesAreStoredPerEnvironment() {
        var target = EnvTarget(relativePath: ".env")
        target.setEntries([EnvEntry(key: "A", value: "1")], for: envs[0].id)
        #expect(target.entries(for: envs[0].id) == [EnvEntry(key: "A", value: "1")])
        #expect(target.entries(for: envs[1].id).isEmpty)
    }

    @Test func projectBuildsTargetURLFromRoot() {
        let target = EnvTarget(relativePath: "apps/cart/.env.local")
        #expect(project([target]).url(for: target).path == "/tmp/p/apps/cart/.env.local")
    }

    @Test func storeRoundTripsThroughJSON() throws {
        var target = EnvTarget(relativePath: ".env", activeEnvironmentId: envs[0].id, lastWrittenHash: "abc")
        target.setEntries([EnvEntry(key: "A", value: "1"), EnvEntry(key: "S", value: nil, isSecret: true)], for: envs[0].id)
        let store = Store(projects: [project([target])], settings: AppSettings(editorAppPath: "/Applications/Zed.app"))
        let data = try JSONEncoder().encode(store)
        #expect(try JSONDecoder().decode(Store.self, from: data) == store)
        #expect(store.version == 1)
    }
}
