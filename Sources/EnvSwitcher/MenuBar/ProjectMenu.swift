import EnvCore
import SwiftUI

struct EnvironmentLabel: View {
    let environment: EnvEnvironment

    var body: some View {
        Image(nsImage: DotImage.make(environment.color.nsColor))
        Text(environment.isProtected ? "\(environment.name) 🔒" : environment.name)
    }
}

struct ProjectMenu: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    let project: Project

    var body: some View {
        if state.rootExists(project) {
            Menu {
                Section("All Files") {
                    ForEach(project.environments) { environment in
                        Toggle(isOn: binding(environment, scope: .project)) {
                            EnvironmentLabel(environment: environment)
                        }
                    }
                }
                Section("Files") {
                    ForEach(project.targets) { target in
                        Menu {
                            ForEach(project.environments) { environment in
                                Toggle(isOn: binding(environment, scope: .target(target.id))) {
                                    EnvironmentLabel(environment: environment)
                                }
                            }
                        } label: {
                            Text(verbatim: "\(target.relativePath) — \(state.environmentName(target.activeEnvironmentId, in: project))")
                        }
                    }
                }
                Divider()
                Button("Open in Finder") { FolderOpener.finder(project.rootURL) }
                Button("Open in Terminal") { FolderOpener.terminal(project.rootURL, settings: state.store.settings) }
                Button("Open in Editor") {
                    FolderOpener.editor(project.rootURL, settings: state.store.settings, sampleFile: project.targets.first.map { project.url(for: $0) })
                }
            } label: {
                Image(nsImage: DotImage.make(state.stateColor(project)))
                Text(verbatim: "\(project.name)\(state.hasDrift(project) ? " ⚠︎" : "") — \(state.stateText(project))")
            }
        } else {
            Menu {
                Button("Choose the Folder Again…") {
                    guard let url = Panels.chooseFolder() else { return }
                    state.apply { state.projectEditor.relocate(project, to: url) }
                }
            } label: {
                Text("\(project.name) — Folder Not Found")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(_ environment: EnvEnvironment, scope: SwitchScope) -> Binding<Bool> {
        Binding(
            get: { isActive(environment.id, scope: scope) },
            set: { _ in
                let outcome = state.requestSwitch(projectId: project.id, scope: scope, environmentId: environment.id)
                if outcome == .needsDriftReview {
                    openWindow(id: WindowID.drift)
                    NSApp.activate()
                }
            }
        )
    }

    private func isActive(_ environmentId: UUID, scope: SwitchScope) -> Bool {
        switch scope {
        case .project:
            return project.displayState == .single(environmentId)
        case .target(let targetId):
            return project.targets.first { $0.id == targetId }?.activeEnvironmentId == environmentId
        }
    }
}
