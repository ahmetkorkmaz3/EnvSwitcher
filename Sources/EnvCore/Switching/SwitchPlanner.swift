import Foundation

public enum SwitchScope: Hashable, Sendable {
    case project
    case target(UUID)
}

public enum SwitchError: Error, Equatable {
    case unknownEnvironment
    case unknownTarget
    case directoryMissing([String])
    case writeFailed(path: String, reason: String)
    case rollbackFailed(paths: [String], recoveryFolder: URL)
    /// The rollback failed and the old content of these files could not be saved anywhere.
    case recoveryFailed(paths: [String])
    /// These files changed on disk after preflight read them. Nothing was written.
    case fileChanged(paths: [String])
    /// A secret entry has no value in the SecretStore. Nothing was written.
    case secretMissing(path: String, key: String)
}

public struct DriftedTarget: Equatable, Sendable {
    public var targetId: UUID
    public var relativePath: String
    public var status: DriftStatus
    public var diff: EnvDiff
    public var fileContents: String

    public init(targetId: UUID, relativePath: String, status: DriftStatus, diff: EnvDiff, fileContents: String) {
        self.targetId = targetId
        self.relativePath = relativePath
        self.status = status
        self.diff = diff
        self.fileContents = fileContents
    }
}

public struct SwitchPreflight: Equatable, Sendable {
    public var environment: EnvEnvironment
    public var targetIds: [UUID]
    public var missingDirectories: [String]
    public var drifted: [DriftedTarget]
    /// Files that have no values in the chosen environment. The switch writes them with the header only.
    public var emptyTargets: [String]
    /// The bytes preflight read for each in-scope target whose folder exists. nil = the file was missing.
    public var observed: [UUID: Data?]

    public var needsProtectedConfirmation: Bool { environment.isProtected }
}

public struct PreparedWrite: Equatable, Sendable {
    public var targetId: UUID
    public var relativePath: String
    public var url: URL
    public var data: Data
}

public struct SwitchPlanner: Sendable {
    let secrets: any SecretStore
    let files: any FileWriter

    public init(secrets: any SecretStore, files: any FileWriter = LocalFileWriter()) {
        self.secrets = secrets
        self.files = files
    }

    /// Steps 1–3 of the switch flow: protected check data, missing folders and drift.
    public func preflight(project: Project, scope: SwitchScope, environmentId: UUID) throws -> SwitchPreflight {
        guard let environment = project.environment(id: environmentId) else { throw SwitchError.unknownEnvironment }
        let targets = try targets(in: project, scope: scope)
        let resolver = ValueResolver(secrets: secrets)
        var missing: [String] = []
        var drifted: [DriftedTarget] = []
        var observed: [UUID: Data?] = [:]

        for target in targets {
            let url = project.url(for: target)
            guard files.directoryExists(url.deletingLastPathComponent()) else {
                missing.append(target.relativePath)
                continue
            }
            let data = try files.read(url)
            observed[target.id] = .some(data)
            let status = DriftDetector.status(fileData: data, lastWrittenHash: target.lastWrittenHash)
            guard status == .modified || status == .unmanaged, let data else { continue }

            let text = String(decoding: data, as: UTF8.self)
            var stored: [DotEnvPair] = []
            if status == .modified, let active = target.activeEnvironmentId {
                stored = try resolver.resolve(project: project, target: target, environmentId: active)
            }
            drifted.append(DriftedTarget(
                targetId: target.id,
                relativePath: target.relativePath,
                status: status,
                diff: EnvDiffer.diff(old: stored, new: DotEnvParser.parse(text).pairs),
                fileContents: text
            ))
        }
        let empty = targets.filter { $0.entries(for: environmentId).isEmpty }.map(\.relativePath)
        return SwitchPreflight(
            environment: environment,
            targetIds: targets.map(\.id),
            missingDirectories: missing,
            drifted: drifted,
            emptyTargets: empty,
            observed: observed
        )
    }

    /// Step 4: builds the new file contents in memory. Writes nothing to disk.
    public func prepare(project: Project, scope: SwitchScope, environmentId: UUID) throws -> [PreparedWrite] {
        guard let environment = project.environment(id: environmentId) else { throw SwitchError.unknownEnvironment }
        let targets = try targets(in: project, scope: scope)
        let missing = targets.filter { !files.directoryExists(project.url(for: $0).deletingLastPathComponent()) }
        guard missing.isEmpty else { throw SwitchError.directoryMissing(missing.map(\.relativePath)) }

        let resolver = ValueResolver(secrets: secrets)
        let header = Self.header(project: project, environment: environment)
        return try targets.map { target in
            let pairs = try resolver.resolve(project: project, target: target, environmentId: environmentId)
            let text = DotEnvSerializer.serialize(pairs, headerLines: header)
            return PreparedWrite(targetId: target.id, relativePath: target.relativePath, url: project.url(for: target), data: Data(text.utf8))
        }
    }

    public static func header(project: Project, environment: EnvEnvironment) -> [String] {
        [
            "Generated by EnvSwitcher — project: \(project.name), environment: \(environment.name)",
            "If you edit this file by hand, the app asks before it switches the environment.",
        ]
    }

    private func targets(in project: Project, scope: SwitchScope) throws -> [EnvTarget] {
        switch scope {
        case .project:
            return project.targets
        case .target(let id):
            guard let target = project.targets.first(where: { $0.id == id }) else { throw SwitchError.unknownTarget }
            return [target]
        }
    }
}
