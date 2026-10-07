import EnvCore
import SwiftUI

struct DriftView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var environmentByTarget: [UUID: UUID] = [:]

    var body: some View {
        Group {
            if let pending = state.pendingDrift, let project = state.project(id: pending.projectId) {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Elle değiştirilmiş dosyalar var", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .symbolRenderingMode(.multicolor)
                    Text("Ortam değişmeden önce bu değişiklikler için bir seçim yapın. Değerler gösterilmez, yalnızca anahtarlar gösterilir.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(pending.drifted, id: \.targetId) { drifted in
                                DriftCard(drifted: drifted, project: project, environmentId: selection(for: drifted.targetId))
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button("İptal", role: .cancel) { finish(.cancel) }
                            .keyboardShortcut(.cancelAction)
                        Button("At ve geç", role: .destructive) { finish(.discard) }
                        Button("Mevcut ortama kaydet") { finish(.saveToCurrent(environmentIdByTarget: environmentByTarget)) }
                            .keyboardShortcut(.defaultAction)
                            .disabled(!pending.drifted.allSatisfy { environmentByTarget[$0.targetId] != nil })
                    }
                }
                .padding(20)
                .frame(width: 560, height: 480)
                // Keyed by the review id: a fresh review in an open window starts with fresh choices.
                .task(id: pending.id) { seed(pending, project: project) }
            } else {
                ContentUnavailableView("Bekleyen değişiklik yok", systemImage: "checkmark.circle")
                    .frame(width: 400, height: 240)
            }
        }
        .onDisappear {
            // Closing the window with the red button means cancel.
            if state.pendingDrift != nil { state.resolveDrift(.cancel) }
        }
    }

    /// A modified file saves into its active environment by default. An unmanaged file has no default.
    private func seed(_ pending: PendingDrift, project: Project) {
        environmentByTarget = [:]
        for drifted in pending.drifted where drifted.status == .modified {
            if let active = project.targets.first(where: { $0.id == drifted.targetId })?.activeEnvironmentId {
                environmentByTarget[drifted.targetId] = active
            }
        }
    }

    private func selection(for targetId: UUID) -> Binding<UUID?> {
        Binding(
            get: { environmentByTarget[targetId] },
            set: { environmentByTarget[targetId] = $0 }
        )
    }

    /// The window stays open when the files changed while it was open. The view then shows the fresh drift.
    private func finish(_ choice: DriftChoice) {
        if state.resolveDrift(choice) {
            dismissWindow(id: WindowID.drift)
        }
    }
}

private struct DriftCard: View {
    let drifted: DriftedTarget
    let project: Project
    @Binding var environmentId: UUID?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(drifted.diff.added, id: \.key) { Text("+ \($0.key)").foregroundStyle(.green) }
                ForEach(drifted.diff.changed, id: \.key) { Text("~ \($0.key)").foregroundStyle(.orange) }
                ForEach(drifted.diff.removed, id: \.self) { Text("− \($0)").foregroundStyle(.red) }
                if drifted.diff.isEmpty {
                    Text("Yalnızca biçim veya yorum satırları değişti.").foregroundStyle(.secondary)
                }
                Picker("Kaydedilecek ortam", selection: $environmentId) {
                    Text("Seçin").tag(UUID?.none)
                    ForEach(project.environments) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .font(.body)
                .padding(.top, 6)
            }
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(drifted.relativePath).font(.headline)
        }
    }
}
