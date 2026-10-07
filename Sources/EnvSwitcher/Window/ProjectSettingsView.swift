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
                    state.apply { state.projectEditor.addEnvironment(named: "yeni", color: .blue, to: current) }
                } label: {
                    Label("Ortam ekle", systemImage: "plus")
                }
            }

            Section("Hedef dosyalar") {
                ForEach(current.targets) { target in
                    HStack {
                        Text(target.relativePath).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            state.apply { try state.projectEditor.removeTarget(id: target.id, from: current) }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Dosyayı projeden çıkar. Diskteki dosya değişmez.")
                    }
                }
                Menu("Dosya ekle") {
                    if newFiles.isEmpty {
                        Text("Eklenecek yeni .env dosyası yok")
                    }
                    ForEach(newFiles, id: \.relativePath) { file in
                        Button(file.relativePath) {
                            state.apply { try state.projectEditor.addTarget(relativePath: file.relativePath, to: current) }
                            loadNewFiles()
                        }
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
        .task(id: project.id) { loadNewFiles() }
        .confirmationDialog("\(current.name) silinsin mi?", isPresented: $confirmDelete) {
            Button("Sil", role: .destructive) { state.deleteProject(current) }
        } message: {
            Text("Kayıtlı değerler ve Keychain kayıtları silinir. Diskteki .env dosyaları değişmez.")
        }
    }

    private func loadNewFiles() {
        let known = Set(current.targets.map(\.relativePath))
        newFiles = ProjectScanner.scan(root: current.rootURL).filter { !known.contains($0.relativePath) }
    }
}

private struct EnvironmentRow: View {
    @Environment(AppState.self) private var state
    let project: Project
    let environment: EnvEnvironment

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
                state.apply { try state.projectEditor.deleteEnvironment(id: environment.id, from: project) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Ortamı ve değerlerini sil")
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
