import EnvCore
import SwiftUI

struct AddProjectSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var root: URL?
    @State private var name = ""
    @State private var files: [ScannedFile] = []
    @State private var selected = Set<String>()
    @State private var environments = EnvEnvironment.defaults()
    @State private var importEnvironmentId: UUID?
    @State private var newEnvironmentName = ""
    @State private var trackedFiles: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Proje Ekle").font(.title2.bold())
            Text("Bir klasörü buraya sürükleyin veya seçin. Uygulama .env dosyalarını otomatik bulur.")
                .foregroundStyle(.secondary)
            dropZone
            if root != nil {
                fileList
                form
            }
            if !trackedFiles.isEmpty {
                Label(
                    "Bu dosyalar git tarafından izleniyor. canli değerler commit'e girebilir: \(trackedFiles.joined(separator: ", "))",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .symbolRenderingMode(.multicolor)
                .font(.callout)
            }
            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Ekle") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onAppear {
            importEnvironmentId = environments.first?.id
            if let url = state.pendingAddURL {
                state.pendingAddURL = nil
                choose(url)
            }
        }
        .onChange(of: selected) { checkGitIgnore() }
    }

    // MARK: Parts

    private var dropZone: some View {
        HStack {
            Image(systemName: "folder")
            Text(root?.path(percentEncoded: false) ?? "Klasör seçilmedi")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(root == nil ? "Seç…" : "Değiştir…") {
                if let url = Panels.chooseFolder() { choose(url) }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(.tertiary)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            choose(url)
            return true
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bulunan dosyalar (\(files.count))").font(.headline)
            List(files, id: \.relativePath) { file in
                Toggle(isOn: selectionBinding(file.relativePath)) {
                    HStack {
                        Text(file.relativePath).font(.system(.body, design: .monospaced))
                        Spacer()
                        Text("\(file.keyCount) anahtar").foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 200)
        }
    }

    private var form: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Text("Proje adı").gridColumnAlignment(.trailing)
                TextField("", text: $name)
            }
            GridRow {
                Text("Ortamlar")
                HStack(spacing: 6) {
                    ForEach(environments) { environment in
                        Text(environment.isProtected ? "\(environment.name) 🔒" : environment.name)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(environment.color.color.opacity(0.18), in: Capsule())
                            .contextMenu {
                                Button("Sil", role: .destructive) { removeEnvironment(environment.id) }
                                    .disabled(environments.count == 1)
                            }
                    }
                    TextField("yeni ortam", text: $newEnvironmentName)
                        .frame(width: 100)
                        .onSubmit(addEnvironment)
                }
            }
            GridRow {
                Text("Mevcut içerik")
                HStack {
                    Picker("", selection: $importEnvironmentId) {
                        ForEach(environments) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Text("ortamına aktarılsın")
                }
            }
        }
    }

    // MARK: Logic

    private var canAdd: Bool {
        root != nil && !selected.isEmpty && importEnvironmentId != nil
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func selectionBinding(_ path: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(path) },
            set: { isOn in
                if isOn { selected.insert(path) } else { selected.remove(path) }
            }
        )
    }

    private func choose(_ url: URL) {
        root = url
        name = url.lastPathComponent
        files = ProjectScanner.scan(root: url)
        selected = Set(files.filter(\.isSelectedByDefault).map(\.relativePath))
        checkGitIgnore()
    }

    private func checkGitIgnore() {
        guard let root else { trackedFiles = []; return }
        trackedFiles = files.map(\.relativePath)
            .filter { selected.contains($0) && GitIgnoreChecker.isIgnored(relativePath: $0, root: root) == false }
    }

    private func addEnvironment() {
        let trimmed = newEnvironmentName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !environments.contains(where: { $0.name == trimmed }) else { return }
        environments.append(EnvEnvironment(name: trimmed, color: .blue))
        newEnvironmentName = ""
    }

    private func removeEnvironment(_ id: UUID) {
        guard environments.count > 1 else { return }
        environments.removeAll { $0.id == id }
        if importEnvironmentId == id { importEnvironmentId = environments.first?.id }
    }

    private func add() {
        guard let root, let environmentId = importEnvironmentId else { return }
        let paths = files.map(\.relativePath).filter(selected.contains)
        do {
            let result = try ProjectImporter(secrets: state.secrets).makeProject(
                name: name.trimmingCharacters(in: .whitespaces),
                root: root,
                relativePaths: paths,
                environments: environments,
                importInto: environmentId
            )
            state.replace(result.project)
            state.selection = .project(result.project.id)
            dismiss()
            if !result.warnings.isEmpty {
                Alerts.showInfo(title: "Bazı satırlar okunamadı", message: Self.describe(result.warnings))
            }
        } catch {
            state.report(error)
        }
    }

    private static func describe(_ warnings: [String: [DotEnvWarning]]) -> String {
        warnings.keys.sorted().map { path in
            let lines = warnings[path]!.map { warning -> String in
                switch warning {
                case .invalidLine(let line): "satır \(line): okunamadı"
                case .unterminatedQuote(let line): "satır \(line): tırnak kapanmıyor"
                case .duplicateKey(let key, let line): "satır \(line): \(key) iki kez var, son değer kullanıldı"
                }
            }
            return "\(path)\n  " + lines.joined(separator: "\n  ")
        }
        .joined(separator: "\n\n")
    }
}
