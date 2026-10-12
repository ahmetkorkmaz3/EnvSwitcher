import Foundation

/// Moves the values of one environment of one file in and out of the app as a plain .env file.
/// The exported file holds secret values in plain text, so the user can send it to another person.
public struct EnvironmentTransfer: Sendable {
    public enum Destination: Equatable, Sendable {
        case newEnvironment(name: String, color: EnvColor)
        /// Replaces the values of this environment: keys that are not in the file are removed.
        case existing(UUID)
    }

    public struct ImportOutcome: Sendable {
        public var project: Project
        public var environmentId: UUID
        public var warnings: [DotEnvWarning]
    }

    static let headerPrefix = "Exported by EnvSwitcher"

    let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    public func exportText(project: Project, targetId: UUID, environmentId: UUID) throws -> String {
        guard let target = project.targets.first(where: { $0.id == targetId }) else { throw SwitchError.unknownTarget }
        guard let environment = project.environment(id: environmentId) else { throw SwitchError.unknownEnvironment }
        let pairs = try ValueResolver(secrets: secrets).resolve(project: project, target: target, environmentId: environmentId)
        let header = [
            "\(Self.headerPrefix) — project: \(project.name), file: \(target.relativePath), environment: \(environment.name)",
            "This file holds secret values in plain text. Send it only to people you trust.",
        ]
        return DotEnvSerializer.serialize(pairs, headerLines: header)
    }

    public func importText(_ text: String, into destination: Destination, targetId: UUID, project: Project) throws -> ImportOutcome {
        guard project.targetIndex(id: targetId) != nil else { throw SwitchError.unknownTarget }
        var project = project
        let environmentId: UUID
        switch destination {
        case .newEnvironment(let name, let color):
            project = ProjectEditor(secrets: secrets).addEnvironment(named: name, color: color, to: project)
            environmentId = project.environments[project.environments.count - 1].id
        case .existing(let id):
            guard project.environment(id: id) != nil else { throw ProjectEditor.EditError.unknownEnvironment }
            environmentId = id
        }
        project = try DriftResolver(secrets: secrets).saveFile(text, into: environmentId, targetId: targetId, project: project)
        return ImportOutcome(project: project, environmentId: environmentId, warnings: DotEnvParser.parse(text).warnings)
    }

    /// The environment name in the header of an exported file, or nil when the file has no such header.
    public static func suggestedEnvironmentName(in text: String) -> String? {
        let marker = ", environment: "
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("# \(headerPrefix)") {
            guard let range = line.range(of: marker, options: .backwards) else { continue }
            let name = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        return nil
    }
}
