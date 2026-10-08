import Testing
@testable import EnvCore

struct UniqueNameTests {
    @Test func newKeyIsEnglishInEveryLanguage() {
        #expect(UniqueName.newKey(existing: []) == "NEW_KEY_1")
    }

    @Test func newKeySkipsTakenNumbers() {
        #expect(UniqueName.newKey(existing: ["NEW_KEY_1", "NEW_KEY_2", "NEW_KEY_4"]) == "NEW_KEY_3")
    }

    @Test func numberedUsesTheBaseWhenItIsFree() {
        #expect(UniqueName.numbered(base: "new", existing: ["local", "test"]) == "new")
    }

    @Test func numberedAddsTheFirstFreeNumber() {
        #expect(UniqueName.numbered(base: "yeni", existing: ["yeni", "yeni 2"]) == "yeni 3")
    }
}
