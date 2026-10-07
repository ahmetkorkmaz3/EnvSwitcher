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

        for target in targets {
            let url = project.url(for: target)
            guard files.directoryExists(url.deletingLastPathComponent()) else {
                missing.append(target.relativePath)
                continue
            }
            let data = try files.read(url)
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
        return SwitchPreflight(environment: environment, targetIds: targets.map(\.id), missingDirectories: missing, drifted: drifted)
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
            "EnvSwitcher tarafından üretildi — proje: \(project.name), ortam: \(environment.name)",
            "Bu dosyayı elle düzenlerseniz, ortam değişirken uygulama sorar.",
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
