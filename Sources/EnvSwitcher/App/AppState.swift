import AppKit
import EnvCore
import SwiftUI

enum WindowID {
    static let manager = "manager"
    static let drift = "drift"
}

enum SidebarSelection: Hashable {
    case project(UUID)
    case target(project: UUID, target: UUID)
}

enum SwitchOutcome {
    case completed
    /// The caller must open the drift window.
    case needsDriftReview
    case stopped
}

enum DriftChoice {
    case saveToCurrent(environmentIdByTarget: [UUID: UUID])
    case discard
    case cancel
}

struct PendingDrift {
    let id = UUID()
    let projectId: UUID
    let scope: SwitchScope
    let environmentId: UUID
    let drifted: [DriftedTarget]
    /// The file bytes preflight read. A commit goes ahead only when the files still match.
    let observed: [UUID: Data?]
}

@MainActor
@Observable
final class AppState {
    var store = Store()
    var driftByTarget: [UUID: DriftStatus] = [:]
    var pendingDrift: PendingDrift?
    var selection: SidebarSelection?
    var showAddProject = false
    var pendingAddURL: URL?
    /// True when store.json could not be read. Saving then would overwrite the user's data.
    @ObservationIgnored private var loadFailed = false
    @ObservationIgnored private var reportedSaveBlocked = false

    let repository: StoreRepository
    let secrets: any SecretStore
    let files: any FileWriter
    let updates = UpdateMonitor()

    init(
        repository: StoreRepository = StoreRepository(directory: StoreRepository.defaultDirectory),
        secrets: any SecretStore = VaultSecretStore(),
        files: any FileWriter = LocalFileWriter()
    ) {
        self.repository = repository
        self.secrets = secrets
        self.files = files
        load()
        openVault()
        updates.start()
        // Spec 6.1: check drift when the user opens the menu.
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDrift() }
        }
    }

    // MARK: Services

    var planner: SwitchPlanner { SwitchPlanner(secrets: secrets, files: files) }

    var switchService: SwitchService {
        SwitchService(
            planner: planner,
            executor: SwitchExecutor(files: files, recoveryDirectory: repository.directory.appendingPathComponent("recovery", isDirectory: true))
        )
    }

    var entryEditor: EntryEditor { EntryEditor(secrets: secrets) }
    var projectEditor: ProjectEditor { ProjectEditor(secrets: secrets) }

    // MARK: Store

    private func load() {
        do {
            let result = try repository.load()
            store = result.store
            if let notice = result.notice {
                DispatchQueue.main.async { Alerts.showInfo(title: String(localized: "Data Restored"), message: Self.describe(notice)) }
            }
        } catch {
            loadFailed = true
            let text = message(for: error)
            DispatchQueue.main.async { Alerts.showError(text) }
        }
    }

    /// Spec 2026-10-08, 3.4: opens the vault at launch, so a failed migration shows its alert at once.
    private func openVault() {
        guard let vault = secrets as? VaultSecretStore else { return }
        do {
            try vault.open()
        } catch {
            let text = message(for: error)
            DispatchQueue.main.async { Alerts.showError(text) }
        }
    }

    func save() {
        guard !loadFailed else {
            if !reportedSaveBlocked {
                reportedSaveBlocked = true
                Alerts.showError(String(localized: "The app cannot read its data, so it does not save changes. Quit the app and open it again."))
            }
            return
        }
        do {
            try repository.save(store)
        } catch {
            report(error)
        }
    }

    func project(id: UUID) -> Project? {
        store.projects.first { $0.id == id }
    }

    func replace(_ project: Project) {
        if let i = store.projectIndex(id: project.id) {
            store.projects[i] = project
        } else {
            store.projects.append(project)
        }
        save()
    }

    func apply(_ change: () throws -> Project) {
        do {
            replace(try change())
        } catch {
            report(error)
        }
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        change(&store.settings)
        save()
    }

    func deleteProject(_ project: Project) {
        do {
            try projectEditor.deleteAllSecrets(of: project)
        } catch {
            report(error)
            return
        }
        store.projects.removeAll { $0.id == project.id }
        if store.lastSwitchedProjectId == project.id { store.lastSwitchedProjectId = nil }
        selection = nil
        save()
    }

    // MARK: Display

    func environmentName(_ id: UUID?, in project: Project) -> String {
        id.flatMap { project.environment(id: $0) }?.name ?? "—"
    }

    func stateText(_ project: Project) -> String {
        switch project.displayState {
        case .none: "—"
        case .mixed: String(localized: "mixed")
        case .single(let id): environmentName(id, in: project)
        }
    }

    func stateColor(_ project: Project) -> NSColor {
        if case .single(let id) = project.displayState, let environment = project.environment(id: id) {
            return environment.color.nsColor
        }
        return .systemGray
    }

    func hasDrift(_ project: Project) -> Bool {
        project.targets.contains { driftByTarget[$0.id] == .modified }
    }

    func rootExists(_ project: Project) -> Bool {
        files.directoryExists(project.rootURL)
    }

    private var labelProject: Project? {
        store.lastSwitchedProjectId.flatMap { project(id: $0) } ?? store.projects.first
    }

    var menuBarTitle: String {
        guard let project = labelProject else { return "EnvSwitcher" }
        return "\(project.name) · \(stateText(project))"
    }

    var menuBarDot: NSImage {
        DotImage.make(labelProject.map { stateColor($0) } ?? .systemGray)
    }

    func refreshDrift() {
        var result: [UUID: DriftStatus] = [:]
        for project in store.projects {
            for target in project.targets {
                let data = try? files.read(project.url(for: target))
                result[target.id] = DriftDetector.status(fileData: data, lastWrittenHash: target.lastWrittenHash)
            }
        }
        if result != driftByTarget { driftByTarget = result }
    }

    // MARK: Switching (spec section 6)

    @discardableResult
    func requestSwitch(projectId: UUID, scope: SwitchScope, environmentId: UUID) -> SwitchOutcome {
        guard let project = project(id: projectId) else { return .stopped }
        do {
            let preflight = try planner.preflight(project: project, scope: scope, environmentId: environmentId)
            if !preflight.missingDirectories.isEmpty {
                // Spec 8: the error names the files and offers "Remove from Project".
                if Alerts.offerRemoveMissing(message(for: SwitchError.directoryMissing(preflight.missingDirectories))) {
                    let missing = Set(preflight.missingDirectories)
                    apply {
                        var updated = project
                        for target in project.targets where missing.contains(target.relativePath) {
                            updated = try projectEditor.removeTarget(id: target.id, from: updated)
                        }
                        return updated
                    }
                }
                return .stopped
            }
            if preflight.needsProtectedConfirmation,
               !Alerts.confirmProtected(projectName: project.name, environmentName: preflight.environment.name, fileCount: preflight.targetIds.count) {
                return .stopped
            }
            if !preflight.emptyTargets.isEmpty,
               !Alerts.confirmEmpty(environmentName: preflight.environment.name, paths: preflight.emptyTargets) {
                return .stopped
            }
            if !preflight.drifted.isEmpty {
                pendingDrift = PendingDrift(projectId: projectId, scope: scope, environmentId: environmentId, drifted: preflight.drifted, observed: preflight.observed)
                return .needsDriftReview
            }
            return commitSwitch(projectId: projectId, scope: scope, environmentId: environmentId, expectedContents: preflight.observed)
        } catch {
            report(error)
            return .stopped
        }
    }

    /// Returns true when the drift review is finished. Returns false when the files changed while
    /// the window was open: `pendingDrift` then holds the fresh drift and the window must stay open.
    @discardableResult
    func resolveDrift(_ choice: DriftChoice) -> Bool {
        guard let pending = pendingDrift else { return true }
        if case .cancel = choice {
            pendingDrift = nil
            return true
        }
        guard var project = project(id: pending.projectId) else {
            pendingDrift = nil
            return true
        }

        // The window can stay open for a long time. Read the files again before anything is saved or written.
        do {
            let fresh = try planner.preflight(project: project, scope: pending.scope, environmentId: pending.environmentId)
            guard fresh.missingDirectories.isEmpty else { throw SwitchError.directoryMissing(fresh.missingDirectories) }
            if fresh.observed != pending.observed {
                pendingDrift = PendingDrift(
                    projectId: pending.projectId,
                    scope: pending.scope,
                    environmentId: pending.environmentId,
                    drifted: fresh.drifted,
                    observed: fresh.observed
                )
                Alerts.showInfo(
                    title: String(localized: "Files Changed"),
                    message: String(localized: "One or more files changed while the window was open. Review the changes again.")
                )
                return false
            }
        } catch {
            pendingDrift = nil
            report(error)
            return true
        }
        pendingDrift = nil

        if case .saveToCurrent(let environmentIdByTarget) = choice {
            if let unchosen = pending.drifted.first(where: { environmentIdByTarget[$0.targetId] == nil }) {
                Alerts.showError(String(localized: "No environment is selected for \(unchosen.relativePath). The app wrote no files."))
                return true
            }
            do {
                let resolver = DriftResolver(secrets: secrets)
                for drifted in pending.drifted {
                    guard let environmentId = environmentIdByTarget[drifted.targetId] else { continue }
                    project = try resolver.saveFile(drifted.fileContents, into: environmentId, targetId: drifted.targetId, project: project)
                }
                replace(project)
            } catch {
                report(error)
                return true
            }
        }
        commitSwitch(projectId: pending.projectId, scope: pending.scope, environmentId: pending.environmentId, expectedContents: pending.observed)
        return true
    }

    @discardableResult
    private func commitSwitch(projectId: UUID, scope: SwitchScope, environmentId: UUID, expectedContents: [UUID: Data?]) -> SwitchOutcome {
        guard let project = project(id: projectId) else { return .stopped }
        do {
            let updated = try switchService.commit(project: project, scope: scope, environmentId: environmentId, expectedContents: expectedContents)
            store.lastSwitchedProjectId = projectId
            replace(updated)
            refreshDrift()
            return .completed
        } catch {
            report(error)
            return .stopped
        }
    }

    // MARK: Errors

    func report(_ error: Error) {
        Alerts.showError(message(for: error))
    }

    func message(for error: Error) -> String {
        switch error {
        case SwitchError.directoryMissing(let paths):
            return String(localized: "These files have no folder: \(paths.joined(separator: ", ")). The files did not change.")
        case SwitchError.writeFailed(let path, let reason):
            return String(localized: "The app could not write \(path). All files went back to their old contents.\n\(reason)")
        case SwitchError.rollbackFailed(let paths, let folder):
            return String(localized: "These files could not go back to their old contents: \(paths.joined(separator: ", ")). The old contents are in this folder: \(folder.path)")
        case SwitchError.recoveryFailed(let paths):
            return String(localized: "These files could not go back to their old contents, and the app could not save the old contents: \(paths.joined(separator: ", ")). Check these files by hand.")
        case SwitchError.fileChanged(let paths):
            return String(localized: "These files changed during the switch: \(paths.joined(separator: ", ")). The app wrote no files. Choose the environment again.")
        case SwitchError.secretMissing(let path, let key):
            return String(localized: "\(path): the Keychain has no secret value for \(key). The files did not change. Enter the value again in the edit window.")
        case SwitchError.unknownEnvironment, SwitchError.unknownTarget:
            return String(localized: "The app cannot find the environment or the file. Close the window and open it again.")
        case SecretStoreError.keychain(let status):
            return String(localized: "The app cannot use the Keychain (code \(status)).")
        case SecretStoreError.vaultCorrupt:
            return String(localized: "The EnvSwitcher item in the Keychain is damaged. The app cannot read the secret values. The app did not change this item.")
        case SecretStoreError.migrationFailed:
            return String(localized: "The app could not move the secret values in the Keychain. Open the app again and give permission.")
        case EntryEditor.EditError.duplicateKey(let key):
            return String(localized: "The key \(key) already exists.")
        case EntryEditor.EditError.invalidKey(let key):
            return String(localized: "\"\(key)\" is not a valid key name. The name must start with a letter or _.")
        case ProjectEditor.EditError.lastEnvironment:
            return String(localized: "A project must have at least one environment.")
        case ProjectEditor.EditError.duplicateTarget(let path):
            return String(localized: "\(path) is already in the project.")
        default:
            return error.localizedDescription
        }
    }

    static func describe(_ notice: StoreLoadNotice) -> String {
        switch notice {
        case .restoredFromBackup:
            String(localized: "The app cannot read store.json. The app loaded the last backup (store.json.bak).")
        case .resetAfterCorruption(let url):
            String(localized: "The app cannot read store.json or its backup. The app opened with empty data. Damaged file: \(url.path)")
        }
    }
}
