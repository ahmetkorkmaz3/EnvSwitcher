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
            Section("Proje") {
                TextField("Ad", text: Binding(
                    get: { current.name },
                    set: { name in state.apply { var p = current; p.name = name; return p } }
                ))
                LabeledContent("Kök klasör") {
                    HStack {
                        Text(current.rootPath)
                            .foregroundStyle(state.rootExists(current) ? .secondary : Color.red)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(state.rootExists(current) ? "Değiştir…" : "Klasörü yeniden seç…") {
                            guard let url = Panels.chooseFolder() else { return }
                            state.apply { state.projectEditor.relocate(current, to: url) }
                        }
                    }
                }
            }

            Section("Ortamlar") {
                ForEach(current.environments) { environment in
                    EnvironmentRow(project: current, environment: environment)
                }
                Button {
                    state.apply { state.projectEditor.addEnvironment(named: newEnvironmentName, color: .blue, to: current) }
                } label: {
                    Label("Ortam ekle", systemImage: "plus")
                }
            }

            Section("Hedef dosyalar") {
                ForEach(current.targets) { target in
                    TargetRow(project: current, target: target)
                }
                Menu("Dosya ekle") {
                    if newFiles.isEmpty {
                        Text("Eklenecek yeni .env dosyası yok")
                    }
                    ForEach(newFiles, id: \.relativePath) { file in
                        Button("\(file.relativePath) (\(file.keyCount) anahtar)") { addTarget(file.relativePath) }
                    }
                }
                .fixedSize()
            }

            Section {
                Button("Projeyi sil", role: .destructive) { confirmDelete = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(current.name)
        .task(id: ScanKey(rootPath: current.rootPath, targetPaths: current.targets.map(\.relativePath))) { loadNewFiles() }
        .confirmationDialog("\(current.name) silinsin mi?", isPresented: $confirmDelete) {
            Button("Sil", role: .destructive) { state.deleteProject(current) }
        } message: {
            Text("Kayıtlı değerler ve Keychain kayıtları silinir. Diskteki .env dosyaları değişmez.")
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
            .help("Dosyayı projeden çıkar. Diskteki dosya değişmez.")
        }
        .confirmationDialog("\(target.relativePath) projeden çıkarılsın mı?", isPresented: $confirmRemove) {
            Button("Çıkar", role: .destructive) {
                state.apply { try state.projectEditor.removeTarget(id: target.id, from: project) }
            }
        } message: {
            Text("Bu dosyanın tüm ortam değerleri ve Keychain kayıtları silinir. Diskteki dosya değişmez.")
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
            TextField("Ad", text: binding(\.name))
                .labelsHidden()
                .frame(maxWidth: 160)
            Picker("Renk", selection: binding(\.color)) {
                ForEach(EnvColor.allCases, id: \.self) { color in
                    Label { Text(color.title) } icon: { Image(nsImage: DotImage.make(color.nsColor)) }
                        .tag(color)
                }
            }
            .labelsHidden()
            .fixedSize()
            Toggle("Korumalı", isOn: binding(\.isProtected))
            Spacer()
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Ortamı ve değerlerini sil")
        }
        .confirmationDialog("\(environment.name) ortamı silinsin mi?", isPresented: $confirmDelete) {
            Button("Sil", role: .destructive) {
                state.apply { try state.projectEditor.deleteEnvironment(id: environment.id, from: project) }
            }
        } message: {
            Text("Bu ortamın tüm değerleri ve Keychain kayıtları silinir. Diskteki .env dosyaları değişmez.")
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
