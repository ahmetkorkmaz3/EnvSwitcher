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
