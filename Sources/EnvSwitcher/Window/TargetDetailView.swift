import EnvCore
import SwiftUI

private struct EditableRow: Identifiable, Equatable {
    var id: String { key }
    var key: String
    var value: String
    var isSecret: Bool
    var isRevealed = false
}

private enum DetailMode: Hashable {
    case edit
    case compare
}

private struct ReloadKey: Hashable {
    let targetId: UUID
    let environmentId: UUID
}

struct TargetDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    let project: Project
    let target: EnvTarget

    @State private var editingEnvironmentId: UUID?
    @State private var rows: [EditableRow] = []
    @State private var selectedKeys = Set<String>()
    @State private var showPreview = false
    @State private var mode = DetailMode.edit
    @State private var compareFilter = CompareFilter.all
    /// The key/value pairs in the file on disk. nil when the file is missing.
    @State private var diskPairs: [DotEnvPair]?

    /// The project and target from the store. The init values can be one edit old.
    private var currentProject: Project { state.project(id: project.id) ?? project }
    private var currentTarget: EnvTarget { currentProject.targets.first { $0.id == target.id } ?? target }

    /// The edited environment. Falls back to the disk environment, then the first one,
    /// when the chosen environment no longer exists.
    private var environmentId: UUID {
        let project = currentProject
        for candidate in [editingEnvironmentId, currentTarget.activeEnvironmentId] {
            if let id = candidate, project.environment(id: id) != nil { return id }
        }
        return project.environments[0].id
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if mode == .compare {
                CompareView(projectId: project.id, targetId: target.id, filter: $compareFilter)
            } else {
                editor
            }
        }
        .navigationTitle(currentTarget.relativePath)
        .navigationSubtitle("\(currentProject.name) · on disk: \(state.environmentName(currentTarget.activeEnvironmentId, in: currentProject))")
        .toolbar { toolbar }
        .task(id: ReloadKey(targetId: target.id, environmentId: environmentId)) { reload() }
        // A write can follow "Mevcut ortama kaydet", which changes the stored values too.
        .task(id: currentTarget.lastWrittenHash) { reload() }
        // The compare view can change any environment.
        .onChange(of: mode) { if mode == .edit { reload() } }
        .sheet(isPresented: $showPreview) { preview }
    }

    // MARK: Parts

    @ViewBuilder
    private var editor: some View {
        Table(rows, selection: $selectedKeys) {
            TableColumn("Key") { row in
                KeyField(key: row.key) { rename(row.key, to: $0) }
            }
            TableColumn("Value") { row in
                ValueField(
                    row: row,
                    onChange: { setValue($0, for: row.key) },
                    onReveal: { toggleReveal(row.key) }
                )
            }
            TableColumn("Secret") { row in
                Toggle(String(), isOn: Binding(get: { row.isSecret }, set: { setSecret($0, for: row.key) }))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .help("Keep the value in the Keychain")
            }
            .width(44)
        }
        .font(.system(.body, design: .monospaced))
        Divider()
        bottomBar
    }

    private var header: some View {
        HStack {
            Picker("View", selection: $mode) {
                Label("Edit", systemImage: "square.and.pencil").tag(DetailMode.edit)
                Label("Compare", systemImage: "rectangle.split.3x1").tag(DetailMode.compare)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if mode == .edit {
                Picker("Environment to Edit", selection: Binding(get: { environmentId }, set: { editingEnvironmentId = $0 })) {
                    ForEach(currentProject.environments) { environment in
                        Text(environment.isProtected ? "\(environment.name) 🔒" : environment.name).tag(environment.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Spacer()
            if mode == .edit { status }
        }
        .padding(12)
    }

    @ViewBuilder
    private var status: some View {
        if !isOnDisk {
            Label("The disk has \(state.environmentName(currentTarget.activeEnvironmentId, in: currentProject)). The app writes these values when you switch to this environment.", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if hasUnwrittenChanges {
            HStack {
                Label("The changes are not on disk yet.", systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Button("Write to Disk") { switchHere() }
            }
        } else {
            Label("The file on disk is up to date.", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// True when the file on disk belongs to the edited environment.
    private var isOnDisk: Bool { environmentId == currentTarget.activeEnvironmentId }

    /// True when the edited values differ from the values in the file on disk.
    /// Compares values, not bytes: an imported file has no header and can have comments.
    private var hasUnwrittenChanges: Bool {
        isOnDisk && diskPairs != rows.map { DotEnvPair(key: $0.key, value: $0.value) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { FolderOpener.reveal(currentProject.url(for: currentTarget)) } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            Button { showPreview = true } label: {
                Label("Preview .env", systemImage: "eye")
            }
            Button { switchHere() } label: {
                if isOnDisk {
                    Label("Write to Disk", systemImage: "square.and.arrow.down")
                } else {
                    Label("Switch to This Environment", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .help(isOnDisk ? "Writes the values of this environment to the file again" : "Switches only this file to the selected environment")
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button { addRow() } label: { Image(systemName: "plus") }
                .help("Add a key")
            Button { removeSelected() } label: { Image(systemName: "minus") }
                .disabled(selectedKeys.isEmpty)
                .help("Delete the selected keys")
            Spacer()
            missingHint
            Button { pasteFromClipboard() } label: {
                Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
            }
            .help("Adds the KEY=value lines on the clipboard to this environment")
            Menu("Copy from Another Environment") {
                ForEach(currentProject.environments.filter { $0.id != environmentId }) { environment in
                    Button(environment.name) { copy(from: environment.id) }
                }
            }
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .padding(8)
    }

    /// Points to the compare view when other environments have keys that this one lacks.
    @ViewBuilder
    private var missingHint: some View {
        let missing = EnvComparer.missingKeys(in: environmentId, target: currentTarget, project: currentProject)
        if !missing.isEmpty {
            Button {
                compareFilter = .missing
                mode = .compare
            } label: {
                Label("Keys missing in this environment: \(missing.count)", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
            .help(missing.joined(separator: ", "))
        }
    }

    private var preview: some View {
        let environment = currentProject.environment(id: environmentId)!
        let pairs = rows.map { DotEnvPair(key: $0.key, value: $0.isSecret ? "••••••••" : $0.value) }
        let text = DotEnvSerializer.serialize(pairs, headerLines: SwitchPlanner.header(project: currentProject, environment: environment))
        return VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "\(currentTarget.relativePath) · \(environment.name)").font(.headline)
            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Close") { showPreview = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }

    // MARK: Actions

    private func switchHere() {
        let outcome = state.requestSwitch(projectId: project.id, scope: .target(target.id), environmentId: environmentId)
        if outcome == .needsDriftReview { openWindow(id: WindowID.drift) }
    }

    private func reload() {
        let project = currentProject
        rows = currentTarget.entries(for: environmentId).map { entry in
            let value = (try? state.entryEditor.readValue(key: entry.key, in: project, targetId: target.id, environmentId: environmentId)) ?? ""
            return EditableRow(key: entry.key, value: value, isSecret: entry.isSecret)
        }
        selectedKeys = []
        readDisk()
    }

    private func readDisk() {
        let data = (try? state.files.read(currentProject.url(for: currentTarget))) ?? nil
        diskPairs = data.map { DotEnvParser.parse(String(decoding: $0, as: UTF8.self)).pairs }
    }

    private func setValue(_ value: String, for key: String) {
        if let i = rows.firstIndex(where: { $0.key == key }) { rows[i].value = value }
        state.apply { try state.entryEditor.setValue(value, key: key, in: currentProject, targetId: target.id, environmentId: environmentId) }
    }

    private func setSecret(_ isSecret: Bool, for key: String) {
        state.apply { try state.entryEditor.setSecret(isSecret, key: key, in: currentProject, targetId: target.id, environmentId: environmentId) }
        reload()
    }

    private func rename(_ oldKey: String, to newKey: String) {
        state.apply { try state.entryEditor.renameKey(oldKey, to: newKey, in: currentProject, targetId: target.id, environmentId: environmentId) }
        reload()
    }

    private func toggleReveal(_ key: String) {
        if let i = rows.firstIndex(where: { $0.key == key }) { rows[i].isRevealed.toggle() }
    }

    private func addRow() {
        let existing = Set(rows.map(\.key))
        var n = 1
        while existing.contains("YENI_ANAHTAR_\(n)") { n += 1 }
        let key = "YENI_ANAHTAR_\(n)"
        state.apply { try state.entryEditor.addEntry(key: key, in: currentProject, targetId: target.id, environmentId: environmentId) }
        reload()
    }

    private func removeSelected() {
        let keys = selectedKeys
        state.apply {
            var project = currentProject
            for key in keys {
                project = try state.entryEditor.removeEntry(key: key, in: project, targetId: target.id, environmentId: environmentId)
            }
            return project
        }
        reload()
    }

    /// Adds the KEY=value lines on the clipboard. Asks only when a key already has a different, non-empty value.
    private func pasteFromClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        let parsed = DotEnvParser.parse(text)
        guard !parsed.pairs.isEmpty else {
            Alerts.showInfo(title: String(localized: "No Values on the Clipboard"), message: String(localized: "Copy lines in the KEY=value format to the clipboard."))
            return
        }
        let project = currentProject
        let plan: EntryEditor.PastePlan
        do {
            plan = try state.entryEditor.planPaste(parsed.pairs, in: project, targetId: target.id, environmentId: environmentId)
        } catch {
            state.report(error)
            return
        }
        guard plan.unchanged.count < parsed.pairs.count else {
            Alerts.showInfo(title: String(localized: "No Changes"), message: String(localized: "The values on the clipboard are already the same in this environment."))
            return
        }
        var mode = EntryEditor.CopyMode.overwrite
        if !plan.conflicts.isEmpty {
            let name = project.environment(id: environmentId)?.name ?? ""
            guard let chosen = Alerts.choosePasteMode(environmentName: name, plan: plan) else { return }
            mode = chosen
        }
        state.apply { try state.entryEditor.pasteEntries(parsed.pairs, mode: mode, in: project, targetId: target.id, environmentId: environmentId) }
        reload()
        Alerts.showImportWarnings(parsed.warnings.isEmpty ? [:] : ["Pano": parsed.warnings])
    }

    private func copy(from source: UUID) {
        guard let mode = Alerts.chooseCopyMode() else { return }
        state.apply { try state.entryEditor.copyEntries(from: source, to: environmentId, targetId: target.id, mode: mode, in: currentProject) }
        reload()
    }
}

/// Renames the key on Return or when the field loses focus, so a half-typed key never reaches the store.
/// An invalid key on focus loss goes back to the stored key without an error.
private struct KeyField: View {
    let key: String
    let onCommit: (String) -> Void
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("KEY", text: $draft)
            .focused($isFocused)
            .onSubmit {
                if draft != key { onCommit(draft) }
                // A successful rename gives the row a new identity and a new KeyField.
                // After a rejected rename this puts the stored key back.
                draft = key
            }
            .onAppear { draft = key }
            .onChange(of: key) { draft = key }
            .onChange(of: isFocused) {
                guard !isFocused else { return }
                if draft != key, DotEnvParser.isValidKey(draft) { onCommit(draft) }
                draft = key
            }
    }
}

/// Saves the value on every change.
private struct ValueField: View {
    let row: EditableRow
    let onChange: (String) -> Void
    let onReveal: () -> Void
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 4) {
            if row.isSecret && !row.isRevealed {
                SecureField(String(), text: $draft)
            } else {
                TextField(String(), text: $draft)
            }
            if row.isSecret {
                Button(action: onReveal) {
                    Image(systemName: row.isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(row.isRevealed ? "Hide the value" : "Show the value")
            }
        }
        .onAppear { draft = row.value }
        .onChange(of: row.value) { draft = row.value }
        .onChange(of: draft) { if draft != row.value { onChange(draft) } }
    }
}
