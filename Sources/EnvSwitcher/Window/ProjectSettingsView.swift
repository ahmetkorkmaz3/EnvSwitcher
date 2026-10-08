import EnvCore
import SwiftUI

struct ProjectSettingsView: View {
    @Environment(AppState.self) private var state
    let project: Project
    @State private var newFiles: [ScannedFile] = []
    @State private var confirmDelete = false

    private var current: Project { state.project(id: project.id) ?? project }

    var body: some View {
        Form {
            Section("Project") {
                TextField("Name", text: Binding(
                    get: { current.name },
                    set: { name in state.apply { var p = current; p.name = name; return p } }
                ))
                LabeledContent("Root Folder") {
                    HStack {
                        Text(current.rootPath)
                            .foregroundStyle(state.rootExists(current) ? .secondary : Color.red)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(state.rootExists(current) ? "Change…" : "Choose the Folder Again…") {
                            guard let url = Panels.chooseFolder() else { return }
                            state.apply { state.projectEditor.relocate(current, to: url) }
                        }
                    }
                }
            }

            Section("Environments") {
                ForEach(current.environments) { environment in
                    EnvironmentRow(project: current, environment: environment)
                }
                Button {
                    state.apply { state.projectEditor.addEnvironment(named: newEnvironmentName, color: .blue, to: current) }
                } label: {
                    Label("Add Environment", systemImage: "plus")
                }
            }

            Section("Target Files") {
                ForEach(current.targets) { target in
                    TargetRow(project: current, target: target)
                }
                Menu("Add File") {
                    if newFiles.isEmpty {
                        Text("No new .env files to add")
                    }
                    ForEach(newFiles, id: \.relativePath) { file in
                        Button("\(file.relativePath) (keys: \(file.keyCount))") { addTarget(file.relativePath) }
                    }
                }
                .fixedSize()
            }

            Section {
                Button("Delete Project", role: .destructive) { confirmDelete = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(current.name)
        .task(id: ScanKey(rootPath: current.rootPath, targetPaths: current.targets.map(\.relativePath))) { loadNewFiles() }
        .confirmationDialog("Delete \(current.name)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { state.deleteProject(current) }
        } message: {
            Text("The app deletes the saved values and the Keychain items. The .env files on disk do not change.")
        }
    }

    /// "yeni", then "yeni 2", "yeni 3" and so on.
    private var newEnvironmentName: String {
        let names = Set(current.environments.map(\.name))
        var name = "yeni"
        var n = 2
        while names.contains(name) {
            name = "yeni \(n)"
            n += 1
        }
        return name
    }

    /// The file's current contents become the values of the project's disk environment.
    private func addTarget(_ relativePath: String) {
        do {
            let result = try ProjectImporter(secrets: state.secrets).addTarget(relativePath: relativePath, to: current)
            state.replace(result.project)
            state.refreshDrift()
            Alerts.showImportWarnings(result.warnings)
        } catch {
            state.report(error)
        }
    }

    private func loadNewFiles() {
        let known = Set(current.targets.map(\.relativePath))
        newFiles = ProjectScanner.scan(root: current.rootURL).filter { !known.contains($0.relativePath) }
    }
}

private struct ScanKey: Hashable {
    let rootPath: String
    let targetPaths: [String]
}

private struct TargetRow: View {
    @Environment(AppState.self) private var state
    let project: Project
    let target: EnvTarget
    @State private var confirmRemove = false

    var body: some View {
        HStack {
            Text(target.relativePath).font(.system(.body, design: .monospaced))
            Spacer()
            Button(role: .destructive) {
                confirmRemove = true
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove the file from the project. The file on disk does not change.")
        }
        .confirmationDialog("Remove \(target.relativePath) from the project?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) {
                state.apply { try state.projectEditor.removeTarget(id: target.id, from: project) }
            }
        } message: {
            Text("The app deletes all environment values and Keychain items of this file. The file on disk does not change.")
        }
    }
}

private struct EnvironmentRow: View {
    @Environment(AppState.self) private var state
    let project: Project
    let environment: EnvEnvironment
    @State private var confirmDelete = false

    var body: some View {
        HStack {
            TextField("Name", text: binding(\.name))
                .labelsHidden()
                .frame(maxWidth: 160)
            Picker("Color", selection: binding(\.color)) {
                ForEach(EnvColor.allCases, id: \.self) { color in
                    Label { Text(color.title) } icon: { Image(nsImage: DotImage.make(color.nsColor)) }
                        .tag(color)
                }
            }
            .labelsHidden()
            .fixedSize()
            Toggle("Protected", isOn: binding(\.isProtected))
            Spacer()
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete the environment and its values")
        }
        .confirmationDialog("Delete the \(environment.name) environment?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                state.apply { try state.projectEditor.deleteEnvironment(id: environment.id, from: project) }
            }
        } message: {
            Text("The app deletes all values and Keychain items of this environment. The .env files on disk do not change.")
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<EnvEnvironment, Value>) -> Binding<Value> {
        Binding(
            get: { environment[keyPath: keyPath] },
            set: { value in
                var updated = environment
                updated[keyPath: keyPath] = value
                state.apply { try state.projectEditor.updateEnvironment(updated, in: project) }
            }
        )
    }
}
