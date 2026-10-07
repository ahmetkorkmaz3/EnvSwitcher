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
            if let backup = try decodeIfValid(backupURL) {
                return StoreLoadResult(store: backup, notice: .restoredFromBackup)
            }
            return StoreLoadResult(store: Store(), notice: nil)
        }
        if let store = try decodeIfValid(storeURL) {
            return StoreLoadResult(store: store, notice: nil)
        }
        if let backup = try decodeIfValid(backupURL) {
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
            try Data(contentsOf: storeURL).write(to: backupURL, options: .atomic)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(store).write(to: storeURL, options: .atomic)
    }

    /// Returns nil when the file is missing or is not valid store JSON. Other read errors propagate.
    private func decodeIfValid(_ url: URL) throws -> Store? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(Store.self, from: data)
        } catch is DecodingError {
            return nil
        }
    }
}
