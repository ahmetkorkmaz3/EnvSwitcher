import Foundation
import Testing
@testable import EnvCore

struct DiffTests {
    @Test func hashesKnownValue() {
        #expect(ContentHash.sha256(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func driftIsMissingWithoutFile() {
        #expect(DriftDetector.status(fileData: nil, lastWrittenHash: "x") == .missing)
    }

    @Test func driftIsUnmanagedWithoutStoredHash() {
        #expect(DriftDetector.status(fileData: Data("A=1".utf8), lastWrittenHash: nil) == .unmanaged)
    }

    @Test func driftIsCleanWhenHashMatches() {
        let data = Data("A=1\n".utf8)
        #expect(DriftDetector.status(fileData: data, lastWrittenHash: ContentHash.sha256(data)) == .clean)
    }

    @Test func driftIsModifiedWhenHashDiffers() {
        let stored = ContentHash.sha256(Data("A=1\n".utf8))
        #expect(DriftDetector.status(fileData: Data("A=2\n".utf8), lastWrittenHash: stored) == .modified)
    }

    @Test func diffFindsAddedChangedAndRemovedKeys() {
        let old = [DotEnvPair(key: "A", value: "1"), DotEnvPair(key: "B", value: "2"), DotEnvPair(key: "C", value: "3")]
        let new = [DotEnvPair(key: "A", value: "1"), DotEnvPair(key: "B", value: "9"), DotEnvPair(key: "D", value: "4")]
        let diff = EnvDiffer.diff(old: old, new: new)
        #expect(diff.added == [DotEnvPair(key: "D", value: "4")])
        #expect(diff.changed == [DotEnvChange(key: "B", oldValue: "2", newValue: "9")])
        #expect(diff.removed == ["C"])
        #expect(!diff.isEmpty)
    }

    @Test func diffIsEmptyForSameValues() {
        let pairs = [DotEnvPair(key: "A", value: "1")]
        #expect(EnvDiffer.diff(old: pairs, new: pairs).isEmpty)
    }
}
