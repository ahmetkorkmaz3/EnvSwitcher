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
            Text("Add Project").font(.title2.bold())
            Text("Drag a folder here or choose one. The app finds the .env files.")
                .foregroundStyle(.secondary)
            dropZone
            if root != nil {
                fileList
                form
            }
            if let existingProject {
                Label("This folder is already in the project \(existingProject.name). Choose a different folder.", systemImage: "xmark.octagon.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.callout)
            }
            if root != nil, files.isEmpty {
                Label("This folder has no .env files.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            if !trackedFiles.isEmpty {
                Label(
                    "Git tracks these files. Values from canli can get into a commit: \(trackedFiles.joined(separator: ", "))",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .symbolRenderingMode(.multicolor)
                .font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
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
            Text(root.map { $0.path(percentEncoded: false) } ?? String(localized: "No folder selected"))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(root == nil ? "Choose…" : "Change…") {
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
            Text("Files Found (\(files.count))").font(.headline)
            List(files, id: \.relativePath) { file in
                Toggle(isOn: selectionBinding(file.relativePath)) {
                    HStack {
                        Text(file.relativePath).font(.system(.body, design: .monospaced))
                        Spacer()
                        Text("Keys: \(file.keyCount)").foregroundStyle(.secondary)
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
                Text("Project Name").gridColumnAlignment(.trailing)
                TextField(String(), text: $name)
            }
            GridRow {
                Text("Environments")
                HStack(spacing: 6) {
                    ForEach(environments) { environment in
                        Text(environment.isProtected ? "\(environment.name) 🔒" : environment.name)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(environment.color.color.opacity(0.18), in: Capsule())
                            .contextMenu {
                                Button("Delete", role: .destructive) { removeEnvironment(environment.id) }
                                    .disabled(environments.count == 1)
                            }
                    }
                    TextField("new environment", text: $newEnvironmentName)
                        .frame(width: 100)
                        .onSubmit(addEnvironment)
                }
            }
            GridRow {
                Text("Current Content")
                HStack {
                    LocalizedFragment("Import into")
                    Picker(String(), selection: $importEnvironmentId) {
                        ForEach(environments) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    LocalizedFragment("environment")
                }
            }
        }
    }

    // MARK: Logic

    /// The project that already manages this folder. Two projects on the same files would fight.
    private var existingProject: Project? {
        guard let root else { return nil }
        let path = root.standardizedFileURL.path
        return state.store.projects.first { $0.rootPath == path }
    }

    private var canAdd: Bool {
        root != nil && existingProject == nil && !selected.isEmpty && importEnvironmentId != nil
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
        // A dropped .env file means its folder.
        let url = url.hasDirectoryPath || FileManager.default.directoryExists(url) ? url : url.deletingLastPathComponent()
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
            Alerts.showImportWarnings(result.warnings)
        } catch {
            state.report(error)
        }
    }
}

/// One part of a sentence around a control. A language can leave a part empty, because the word order
/// differs ("Import into [x] environment" and "[x] ortamına aktarılsın"). An empty part takes no space.
private struct LocalizedFragment: View {
    let text: String

    init(_ key: String.LocalizationValue) {
        text = String(localized: key)
    }

    var body: some View {
        if !text.isEmpty { Text(verbatim: text) }
    }
}
