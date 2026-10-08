import Foundation
import Testing
@testable import EnvCore

struct SemanticVersionTests {
    @Test(arguments: ["1.2.3", "v1.2.3"])
    func parses(text: String) {
        #expect(SemanticVersion(text) == SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    @Test(arguments: ["", "1.2", "1.2.3.4", "0.0.0-dev", "1..3", "a.b.c", "+1.2.3", "1.2.3 ", "V1.2.3", "1.2.٣"])
    func rejects(text: String) {
        #expect(SemanticVersion(text) == nil)
    }

    @Test func compares() throws {
        let v = { (s: String) in SemanticVersion(s)! }
        #expect(v("0.2.0") < v("0.2.1"))
        #expect(v("0.2.9") < v("0.10.0"))
        #expect(v("0.99.99") < v("1.0.0"))
        #expect(!(v("1.0.0") < v("1.0.0")))
        #expect(v("v2.0.0").description == "2.0.0")
    }
}

struct UpdateScheduleTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func dueWithoutAnEarlierCheck() {
        #expect(UpdateSchedule.isDue(lastCheck: nil, now: now))
    }

    @Test func notDueAfter23Hours() {
        #expect(!UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-23 * 3600), now: now))
    }

    @Test func dueAfter25Hours() {
        #expect(UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-25 * 3600), now: now))
    }

    @Test func dueWhenClockMovedBack() {
        #expect(UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }
}

private struct StubHTTPClient: HTTPClient {
    let body: String
    var status = 200
    func get(_ url: URL) async throws -> (Data, Int) { (Data(body.utf8), status) }
}

private struct FailingHTTPClient: HTTPClient {
    func get(_ url: URL) async throws -> (Data, Int) { throw URLError(.notConnectedToInternet) }
}

struct UpdateCheckerTests {
    let current = SemanticVersion("0.2.0")!
    let page = "https://github.com/ahmetkorkmaz3/env-management/releases/tag/v0.3.0"

    private func body(tag: String) -> String {
        #"{"tag_name":"\#(tag)","html_url":"\#(page)","name":"x","assets":[]}"#
    }

    @Test func reportsANewerRelease() async throws {
        let checker = UpdateChecker(client: StubHTTPClient(body: body(tag: "v0.3.0")))
        let result = try await checker.check(current: current)
        #expect(result == .available(AvailableUpdate(version: SemanticVersion("0.3.0")!, url: URL(string: page)!)))
    }

    @Test(arguments: ["v0.2.0", "v0.1.9"])
    func reportsUpToDateForTheSameOrAnOlderRelease(tag: String) async throws {
        let checker = UpdateChecker(client: StubHTTPClient(body: body(tag: tag)))
        #expect(try await checker.check(current: current) == .upToDate)
    }

    @Test func rejectsABadStatus() async {
        let checker = UpdateChecker(client: StubHTTPClient(body: "{}", status: 404))
        await #expect(throws: UpdateError.badStatus(404)) { try await checker.check(current: current) }
    }

    @Test(arguments: ["not json", #"{"html_url":"https://x"}"#, #"{"tag_name":"latest","html_url":"https://x"}"#])
    func rejectsAnInvalidBody(body: String) async {
        let checker = UpdateChecker(client: StubHTTPClient(body: body))
        await #expect(throws: UpdateError.invalidResponse) { try await checker.check(current: current) }
    }

    @Test func passesNetworkErrorsThrough() async {
        let checker = UpdateChecker(client: FailingHTTPClient())
        await #expect(throws: URLError.self) { try await checker.check(current: current) }
    }
}

struct StoredUpdateTests {
    let found = AvailableUpdate(version: SemanticVersion("0.3.0")!, url: URL(string: "https://example.com")!)

    @Test func showsAStoredNewerVersion() {
        #expect(StoredUpdate(found: found).available(current: SemanticVersion("0.2.0")!) == found)
    }

    @Test func hidesTheStoredVersionAfterTheUserInstallsIt() {
        #expect(StoredUpdate(found: found).available(current: SemanticVersion("0.3.0")!) == nil)
        #expect(StoredUpdate(found: found).available(current: SemanticVersion("0.4.0")!) == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let stored = StoredUpdate(lastCheck: Date(timeIntervalSince1970: 1_800_000_000), found: found)
        let data = try JSONEncoder().encode(stored)
        #expect(try JSONDecoder().decode(StoredUpdate.self, from: data) == stored)
    }
}
