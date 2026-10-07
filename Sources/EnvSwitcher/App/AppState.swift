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

    let repository: StoreRepository
    let secrets: any SecretStore
    let files: any FileWriter

    init(
        repository: StoreRepository = StoreRepository(directory: StoreRepository.defaultDirectory),
        secrets: any SecretStore = KeychainSecretStore(),
        files: any FileWriter = LocalFileWriter()
    ) {
        self.repository = repository
        self.secrets = secrets
        self.files = files
        load()
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
                DispatchQueue.main.async { Alerts.showInfo(title: "Depo geri yüklendi", message: Self.describe(notice)) }
            }
        } catch {
            report(error)
        }
    }

    func save() {
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
        case .mixed: "karışık"
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
                // Spec 8: the error names the files and offers "Dosyayı projeden çıkar".
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
                Alerts.showInfo(title: "Dosyalar değişti", message: "Pencere açıkken bir veya daha fazla dosya değişti. Değişiklikleri yeniden gözden geçirin.")
                return false
            }
        } catch {
            pendingDrift = nil
            report(error)
            return true
        }
        pendingDrift = nil

        if case .saveToCurrent(let environmentIdByTarget) = choice {
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
            return "Şu dosyaların klasörü yok: \(paths.joined(separator: ", ")). Dosyalar değişmedi."
        case SwitchError.writeFailed(let path, let reason):
            return "\(path) dosyası yazılamadı. Tüm dosyalar eski içeriğe döndü.\n\(reason)"
        case SwitchError.rollbackFailed(let paths, let folder):
            return "Şu dosyalar eski içeriğe dönemedi: \(paths.joined(separator: ", ")). Eski içerikler şu klasörde: \(folder.path)"
        case SwitchError.recoveryFailed(let paths):
            return "Şu dosyalar eski içeriğe dönemedi ve eski içerikleri kaydedilemedi: \(paths.joined(separator: ", ")). Bu dosyaları elle kontrol edin."
        case SwitchError.fileChanged(let paths):
            return "Şu dosyalar ortam değişirken değişti: \(paths.joined(separator: ", ")). Hiçbir dosya yazılmadı. Ortamı yeniden seçin."
        case SwitchError.secretMissing(let path, let key):
            return "\(path) dosyasındaki \(key) gizli değeri Keychain'de bulunamadı. Dosyalar değişmedi. Değeri düzenleme penceresinde yeniden girin."
        case SwitchError.unknownEnvironment, SwitchError.unknownTarget:
            return "Ortam veya dosya bulunamadı. Pencereyi kapatıp yeniden açın."
        case SecretStoreError.keychain(let status):
            return "Keychain erişimi başarısız oldu (kod \(status))."
        case EntryEditor.EditError.duplicateKey(let key):
            return "\(key) anahtarı zaten var."
        case EntryEditor.EditError.invalidKey(let key):
            return "\"\(key)\" geçerli bir anahtar adı değil. Ad bir harf veya _ ile başlamalı."
        case ProjectEditor.EditError.lastEnvironment:
            return "Bir projede en az bir ortam olmalı."
        case ProjectEditor.EditError.duplicateTarget(let path):
            return "\(path) zaten projede var."
        default:
            return error.localizedDescription
        }
    }

    static func describe(_ notice: StoreLoadNotice) -> String {
        switch notice {
        case .restoredFromBackup:
            "store.json okunamadı. Uygulama son yedeği (store.json.bak) yükledi."
        case .resetAfterCorruption(let url):
            "store.json ve yedeği okunamadı. Uygulama boş bir depo ile açıldı. Bozuk dosya: \(url.path)"
        }
    }
}
