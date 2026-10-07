import Foundation

public enum StoreLoadNotice: Equatable, Sendable {
    case restoredFromBackup
    case resetAfterCorruption(savedAs: URL)
}

public struct StoreLoadResult: Equatable, Sendable {
    public var store: Store
    public var notice: StoreLoadNotice?

    public init(store: Store, notice: StoreLoadNotice?) {
        self.store = store
        self.notice = notice
    }
}

public struct StoreRepository: Sendable {
    public let directory: URL
    private let now: @Sendable () -> Date

    public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EnvSwitcher", isDirectory: true)
    }

    public var storeURL: URL { directory.appendingPathComponent("store.json") }
    public var backupURL: URL { directory.appendingPathComponent("store.json.bak") }

    public func load() throws -> StoreLoadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else {
            return StoreLoadResult(store: Store(), notice: nil)
        }
        if let store = try? decode(storeURL) {
            return StoreLoadResult(store: store, notice: nil)
        }
        if let backup = try? decode(backupURL) {
            return StoreLoadResult(store: backup, notice: .restoredFromBackup)
        }
        let corrupt = directory.appendingPathComponent("store.json.corrupt-\(Timestamp.string(now()))")
        try fm.moveItem(at: storeURL, to: corrupt)
        return StoreLoadResult(store: Store(), notice: .resetAfterCorruption(savedAs: corrupt))
    }

    public func save(_ store: Store) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: storeURL.path) {
            if fm.fileExists(atPath: backupURL.path) { try fm.removeItem(at: backupURL) }
            try fm.copyItem(at: storeURL, to: backupURL)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(store).write(to: storeURL, options: .atomic)
    }

    private func decode(_ url: URL) throws -> Store {
        try JSONDecoder().decode(Store.self, from: Data(contentsOf: url))
    }
}
