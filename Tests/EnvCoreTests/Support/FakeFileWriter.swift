import Foundation
@testable import EnvCore

/// In-memory FileWriter. A write to `failingURL` throws. With
/// `failEverythingAfterFirstFailure`, every later write and remove also throws.
final class FakeFileWriter: FileWriter, @unchecked Sendable {
    struct Failure: Error {}

    var contents: [URL: Data] = [:]
    var failingURL: URL?
    var failEverythingAfterFirstFailure = false
    private var broken = false

    func read(_ url: URL) throws -> Data? { contents[url] }

    func write(_ data: Data, to url: URL) throws {
        if broken { throw Failure() }
        if url == failingURL {
            broken = failEverythingAfterFirstFailure
            throw Failure()
        }
        contents[url] = data
    }

    func remove(_ url: URL) throws {
        if broken { throw Failure() }
        contents[url] = nil
    }

    func directoryExists(_ url: URL) -> Bool { true }
}
