import EnvCore
import SwiftUI

enum CompareFilter: Hashable {
    case all
    case missing
    case different
}

/// Shows every key of one file with its value in each environment, side by side.
/// A missing value can be typed in place or copied from another environment.
struct CompareView: View {
    @Environment(AppState.self) private var state
    let projectId: UUID
    let targetId: UUID
    @Binding var filter: CompareFilter

    @State private var rows: [ComparisonRow] = []
    @State private var revealedKeys = Set<String>()

    private static let valueWidth: CGFloat = 220

    private var project: Project? { state.project(id: projectId) }

    private var visibleRows: [ComparisonRow] {
        switch filter {
        case .all: rows
        case .missing: rows.filter { $0.status == .missing }
        case .different: rows.filter { $0.status == .different }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if let project {
                if visibleRows.isEmpty {
                    emptyState
                } else {
                    ScrollView([.vertical, .horizontal]) {
                        grid(project)
                            .padding(12)
                    }
                }
            }
        }
        // Every saved edit changes the project, so the rows always show the stored values.
        .task(id: project) { reload() }
    }

    // MARK: Parts

    private var filterBar: some View {
        let missing = rows.filter { $0.status == .missing }.count
        let different = rows.filter { $0.status == .different }.count
        return HStack {
            Picker("Göster", selection: $filter) {
                Text("Tümü (\(rows.count))").tag(CompareFilter.all)
                Text("Eksik (\(missing))").tag(CompareFilter.missing)
                Text("Farklı (\(different))").tag(CompareFilter.different)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if missing > 0, let project {
                Menu("Tüm eksiklere kopyala") {
                    Button("Her anahtar için ilk dolu ortamdan") { fillAllMissing(from: .firstAvailable, in: project) }
                    Divider()
                    ForEach(project.environments) { source in
                        Button("\(source.name) değerlerini kopyala") { fillAllMissing(from: .environment(source.id), in: project) }
                    }
                }
                .fixedSize()
                .help("Eksik anahtarların hepsini, olmadıkları ortamlara ekler. Var olan değerler değişmez.")
            }
            Spacer()
            Text("Bir değeri değiştirip Return tuşuna basın. Eksik bir hücreye yazınca anahtar o ortama eklenir.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var emptyState: some View {
        switch filter {
        case .missing:
            ContentUnavailableView("Eksik anahtar yok", systemImage: "checkmark.circle", description: Text("Her anahtar tüm ortamlarda var."))
        case .different:
            ContentUnavailableView("Farklı değer yok", systemImage: "equal.circle", description: Text("Tüm ortamlarda değerler aynı."))
        case .all:
            ContentUnavailableView("Anahtar yok", systemImage: "doc.text", description: Text("Bu dosyada hiçbir ortamda anahtar yok."))
        }
    }

    private func grid(_ project: Project) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("")
                Text("Anahtar")
                ForEach(project.environments) { environment in
                    HStack(spacing: 4) {
                        Circle().fill(environment.color.color).frame(width: 8, height: 8)
                        Text(environment.isProtected ? "\(environment.name) 🔒" : environment.name)
                    }
                    .frame(width: Self.valueWidth, alignment: .leading)
                }
                Text("")
            }
            .font(.headline)
            Divider()
            ForEach(visibleRows) { row in
                GridRow {
                    StatusIcon(status: row.status)
                    HStack(spacing: 4) {
                        Text(row.key).font(.system(.body, design: .monospaced))
                        if row.isSecret {
                            Image(systemName: "lock.fill").foregroundStyle(.secondary).help("Gizli değer, Keychain'de durur")
                        }
                    }
                    .frame(minWidth: 180, alignment: .leading)
                    ForEach(project.environments) { environment in
                        CompareCell(
                            value: row.values[environment.id],
                            isDifferent: row.status == .different,
                            isSecret: row.isSecret,
                            isRevealed: revealedKeys.contains(row.key)
                        ) { save($0, key: row.key, isSecret: row.isSecret, environmentId: environment.id) }
                        .frame(width: Self.valueWidth)
                    }
                    actions(for: row, in: project)
                }
            }
        }
    }

    @ViewBuilder
    private func actions(for row: ComparisonRow, in project: Project) -> some View {
        HStack(spacing: 6) {
            if row.isSecret {
                Button {
                    if !revealedKeys.insert(row.key).inserted { revealedKeys.remove(row.key) }
                } label: {
                    Image(systemName: revealedKeys.contains(row.key) ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(revealedKeys.contains(row.key) ? "Değerleri gizle" : "Değerleri göster")
            }
            if row.status == .missing {
                Menu("Eksiklere kopyala") {
                    ForEach(project.environments.filter { row.values[$0.id] != nil }) { source in
                        Button("\(source.name) değerini kopyala") { fillMissing(row, from: source.id, in: project) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Bu anahtarı, olmadığı ortamlara seçilen ortamın değeriyle ekler")
            }
        }
    }

    // MARK: Actions

    private func reload() {
        guard let project else { return }
        do {
            rows = try EnvComparer(secrets: state.secrets).compare(project: project, targetId: targetId)
        } catch {
            rows = []
            state.report(error)
        }
    }

    private func save(_ value: String, key: String, isSecret: Bool, environmentId: UUID) {
        guard let project else { return }
        state.apply {
            try state.entryEditor.upsertValue(value, key: key, isSecret: isSecret, in: project, targetId: targetId, environmentId: environmentId)
        }
    }

    private func fillMissing(_ row: ComparisonRow, from source: UUID, in project: Project) {
        state.apply {
            try state.entryEditor.fillMissing([row], from: .environment(source), in: project, targetId: targetId).project
        }
    }

    private func fillAllMissing(from source: EntryEditor.FillSource, in project: Project) {
        let missingRows = rows.filter { $0.status == .missing }
        let sourceName: String? = switch source {
        case .firstAvailable: nil
        case .environment(let id): project.environment(id: id)?.name
        }
        guard Alerts.confirmFillAll(keyCount: missingRows.count, sourceName: sourceName) else { return }
        do {
            let result = try state.entryEditor.fillMissing(missingRows, from: source, in: project, targetId: targetId)
            state.replace(result.project)
            if !result.skipped.isEmpty {
                Alerts.showInfo(
                    title: "\(result.filled.count) anahtar eklendi, \(result.skipped.count) anahtar atlandı",
                    message: "\(sourceName ?? "") ortamında bu anahtarlar yok: \(result.skipped.joined(separator: ", "))"
                )
            }
        } catch {
            state.report(error)
        }
    }
}

private struct StatusIcon: View {
    let status: ComparisonRow.Status

    var body: some View {
        switch status {
        case .same:
            Image(systemName: "equal.circle").foregroundStyle(.secondary).help("Tüm ortamlarda aynı")
        case .different:
            Image(systemName: "arrow.left.arrow.right.circle.fill").foregroundStyle(.orange).help("Ortamlarda farklı değerler var")
        case .missing:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).help("Bir veya daha fazla ortamda eksik")
        }
    }
}

/// Saves on Return or when the field loses focus. A missing cell saves only when the user types a value.
private struct CompareCell: View {
    let value: String?
    let isDifferent: Bool
    let isSecret: Bool
    let isRevealed: Bool
    let onCommit: (String) -> Void

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private var isMissing: Bool { value == nil }

    var body: some View {
        Group {
            if isSecret && !isRevealed {
                SecureField(isMissing ? "eksik" : "", text: $draft)
            } else {
                TextField(isMissing ? "eksik" : "boş", text: $draft)
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.system(.body, design: .monospaced))
        .focused($isFocused)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(borderColor, lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .onAppear { draft = value ?? "" }
        .onChange(of: value) { draft = value ?? "" }
        .onSubmit(commit)
        .onChange(of: isFocused) { if !isFocused { commit() } }
    }

    private var borderColor: Color {
        if isMissing { return .red.opacity(0.7) }
        if isDifferent { return .orange.opacity(0.5) }
        return .clear
    }

    private func commit() {
        if isMissing, draft.isEmpty { return }
        guard draft != (value ?? "") else { return }
        onCommit(draft)
    }
}
