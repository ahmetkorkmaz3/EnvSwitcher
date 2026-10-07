import Foundation

public enum EnvColor: String, Codable, CaseIterable, Sendable {
    case green, orange, red, blue, purple, gray
}

public struct EnvEnvironment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var color: EnvColor
    public var isProtected: Bool

    public init(id: UUID = UUID(), name: String, color: EnvColor, isProtected: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.isProtected = isProtected
    }

    public static func defaults() -> [EnvEnvironment] {
        [
            EnvEnvironment(name: "local", color: .green),
            EnvEnvironment(name: "test", color: .orange),
            EnvEnvironment(name: "canli", color: .red, isProtected: true),
        ]
    }
}

public struct EnvEntry: Codable, Equatable, Sendable {
    public var key: String
    /// Always nil when `isSecret` is true. The value then lives in the SecretStore.
    public var value: String?
    public var isSecret: Bool

    public init(key: String, value: String?, isSecret: Bool = false) {
        self.key = key
        self.value = value
        self.isSecret = isSecret
    }
}

public struct EnvTarget: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var relativePath: String
    public var activeEnvironmentId: UUID?
    public var lastWrittenHash: String?
    /// Keyed by environment id (`uuidString`). List order is the order in the written file.
    public var values: [String: [EnvEntry]]

    public init(
        id: UUID = UUID(),
        relativePath: String,
        activeEnvironmentId: UUID? = nil,
        lastWrittenHash: String? = nil,
        values: [String: [EnvEntry]] = [:]
    ) {
        self.id = id
        self.relativePath = relativePath
        self.activeEnvironmentId = activeEnvironmentId
        self.lastWrittenHash = lastWrittenHash
        self.values = values
    }

    public func entries(for environmentId: UUID) -> [EnvEntry] {
        values[environmentId.uuidString] ?? []
    }

    public mutating func setEntries(_ entries: [EnvEntry], for environmentId: UUID) {
        values[environmentId.uuidString] = entries
    }
}

public enum ProjectDisplayState: Equatable, Sendable {
    case none
    case single(UUID)
    case mixed
}

public struct Project: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var rootPath: String
    public var environments: [EnvEnvironment]
    public var targets: [EnvTarget]

    public init(
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        environments: [EnvEnvironment],
        targets: [EnvTarget]
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.environments = environments
        self.targets = targets
    }

    public var rootURL: URL { URL(fileURLWithPath: rootPath, isDirectory: true) }

    public func url(for target: EnvTarget) -> URL {
        rootURL.appendingPathComponent(target.relativePath)
    }

    public func environment(id: UUID) -> EnvEnvironment? {
        environments.first { $0.id == id }
    }

    public func targetIndex(id: UUID) -> Int? {
        targets.firstIndex { $0.id == id }
    }

    public var displayState: ProjectDisplayState {
        let ids = Set(targets.compactMap(\.activeEnvironmentId))
        guard let first = ids.first else { return .none }
        if ids.count == 1, targets.allSatisfy({ $0.activeEnvironmentId != nil }) {
            return .single(first)
        }
        return .mixed
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var editorAppPath: String?
    public var terminalAppPath: String?

    public init(editorAppPath: String? = nil, terminalAppPath: String? = nil) {
        self.editorAppPath = editorAppPath
        self.terminalAppPath = terminalAppPath
    }
}

public struct Store: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var projects: [Project]
    public var settings: AppSettings
    public var lastSwitchedProjectId: UUID?

    public init(
        version: Int = Store.currentVersion,
        projects: [Project] = [],
        settings: AppSettings = AppSettings(),
        lastSwitchedProjectId: UUID? = nil
    ) {
        self.version = version
        self.projects = projects
        self.settings = settings
        self.lastSwitchedProjectId = lastSwitchedProjectId
    }

    public func projectIndex(id: UUID) -> Int? {
        projects.firstIndex { $0.id == id }
    }
}
