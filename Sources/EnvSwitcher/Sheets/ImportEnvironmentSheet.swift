import EnvCore
import SwiftUI

/// The .env file that the user chose to import. The sheet asks where its values go.
struct PendingEnvImport: Identifiable {
    let id = UUID()
    let fileName: String
    let text: String
}

private enum ImportMode: Hashable {
    case new
    case existing
}

struct ImportEnvironmentSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let project: Project
    let target: EnvTarget
    let file: PendingEnvImport
    /// Gets the environment that received the values.
    let onImported: (UUID) -> Void

    @State private var mode = ImportMode.new
    @State private var name = ""
    @State private var color = EnvColor.blue
    @State private var existingId: UUID?

    private var keyCount: Int { DotEnvParser.parse(file.text).pairs.count }
    private var existingNames: Set<String> { Set(project.environments.map(\.name)) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var canImport: Bool {
        switch mode {
        case .new: !trimmedName.isEmpty && !existingNames.contains(trimmedName)
        case .existing: existingId != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import .env File").font(.title2.bold())
            Text("\(file.fileName) → \(target.relativePath) · keys: \(keyCount)")
                .foregroundStyle(.secondary)
            Picker("Destination", selection: $mode) {
                Text("New environment").tag(ImportMode.new)
                Text("Replace an environment").tag(ImportMode.existing)
            }
            .pickerStyle(.radioGroup)
            Form {
                if mode == .new {
                    TextField("Name", text: $name)
                    Picker("Color", selection: $color) {
                        ForEach(EnvColor.allCases, id: \.self) { color in
                            Label { Text(color.title) } icon: { Image(nsImage: DotImage.make(color.nsColor)) }
                                .tag(color)
                        }
                    }
                    if existingNames.contains(trimmedName) {
                        Label("An environment with this name already exists.", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                } else {
                    Picker("Environment", selection: $existingId) {
                        ForEach(project.environments) { environment in
                            Text(environment.isProtected ? "\(environment.name) 🔒" : environment.name).tag(UUID?.some(environment.id))
                        }
                    }
                    Label("The values in the file replace the values of this environment. Keys that are not in the file are removed.", systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.callout)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") { importFile() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canImport)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            let base = EnvironmentTransfer.suggestedEnvironmentName(in: file.text) ?? String(localized: "Imported")
            name = UniqueName.numbered(base: base, existing: existingNames)
            existingId = project.environment(id: target.activeEnvironmentId ?? UUID())?.id ?? project.environments.first?.id
        }
    }

    private func importFile() {
        let destination: EnvironmentTransfer.Destination
        switch mode {
        case .new:
            destination = .newEnvironment(name: trimmedName, color: color)
        case .existing:
            guard let id = existingId, let environment = project.environment(id: id) else { return }
            if environment.isProtected, !Alerts.confirmReplaceProtected(environmentName: environment.name) { return }
            destination = .existing(id)
        }
        let current = state.project(id: project.id) ?? project
        do {
            let outcome = try EnvironmentTransfer(secrets: state.secrets).importText(file.text, into: destination, targetId: target.id, project: current)
            state.replace(outcome.project)
            dismiss()
            onImported(outcome.environmentId)
            Alerts.showImportWarnings(outcome.warnings.isEmpty ? [:] : [file.fileName: outcome.warnings])
        } catch {
            state.report(error)
        }
    }
}
