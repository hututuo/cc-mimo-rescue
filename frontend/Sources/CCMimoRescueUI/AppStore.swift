import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    private static let languageKey = "cc-mimo-rescue.language"

    @Published var selectedItem: SidebarItem = .health
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
        }
    }
    @Published var doctor: DoctorReport?
    @Published var sessions: [SessionSummary] = []
    @Published var selectedSession: SessionSummary?
    @Published var cleanPreview: CleanPreview?
    @Published var configurePreview: ConfigurePreview?
    @Published var memoryPreview: MemoryPreview?
    @Published var backups: [BackupSummary] = []
    @Published var isLoading = false
    @Published var isRefreshingSessions = false
    @Published var isCreatingFullBackup = false
    @Published var errorMessage: String?
    @Published var lastActionMessage: String?

    private let backend = BackendClient()

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.languageKey)
        language = AppLanguage(rawValue: saved ?? "") ?? .chinese
    }

    func t(_ key: String) -> String {
        L10n.text(key, language)
    }

    func display(_ value: String?) -> String {
        t(value?.isEmpty == false ? value! : "Not found")
    }

    func refreshHealth() async {
        await run { [self] in
            self.doctor = try await self.backend.run(["doctor"], as: DoctorReport.self)
            self.configurePreview = try? await self.backend.run(["configure", "preview"], as: ConfigurePreview.self)
            self.memoryPreview = try? await self.backend.run(["configure", "memory-preview"], as: MemoryPreview.self)
        }
    }

    func refreshSessions(limit: Int = 100) async {
        guard !isRefreshingSessions else { return }
        isRefreshingSessions = true
        isLoading = true
        errorMessage = nil
        defer {
            isRefreshingSessions = false
            isLoading = false
        }
        do {
            let response = try await self.backend.run(["sessions", "list", "--limit", "\(limit)"], as: SessionsListResponse.self)
            self.sessions = response.sessions
            if self.selectedSession == nil {
                self.selectedSession = response.sessions.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func previewRepair(mode: String = "replace-media-with-placeholder") async {
        guard let selectedSession else { return }
        await run { [self] in
            self.cleanPreview = try await self.backend.run([
                "sessions", "preview-clean",
                "--session", selectedSession.sessionId,
                "--mode", mode
            ], as: CleanPreview.self)
            self.selectedItem = .sessions
        }
    }

    func applyRepair(mode: String = "replace-media-with-placeholder") async {
        guard let selectedSession else { return }
        await run { [self] in
            self.cleanPreview = try await self.backend.run([
                "sessions", "clean",
                "--session", selectedSession.sessionId,
                "--mode", mode,
                "--yes"
            ], as: CleanPreview.self)
            self.lastActionMessage = "Repair applied. Backup created."
            await self.refreshBackups()
            await self.previewRepair(mode: mode)
        }
    }

    func refreshConfigure() async {
        await run { [self] in
            self.configurePreview = try await self.backend.run(["configure", "preview"], as: ConfigurePreview.self)
            self.memoryPreview = try await self.backend.run(["configure", "memory-preview"], as: MemoryPreview.self)
        }
    }

    func previewRoute(haiku: String?, sonnet: String?, opus: String?, main: String?) async {
        await run { [self] in
            self.configurePreview = try await self.backend.run(routeArguments(command: "preview", haiku: haiku, sonnet: sonnet, opus: opus, main: main), as: ConfigurePreview.self)
        }
    }

    func previewMemory(imageModel: String, helperModel: String) async {
        await run { [self] in
            self.memoryPreview = try await self.backend.run([
                "configure", "memory-preview",
                "--image-model", imageModel,
                "--helper-model", helperModel
            ], as: MemoryPreview.self)
        }
    }

    func applyRoute(haiku: String? = nil, sonnet: String? = nil, opus: String? = nil, main: String? = nil) async {
        await run { [self] in
            self.configurePreview = try await self.backend.run(routeArguments(command: "apply", haiku: haiku, sonnet: sonnet, opus: opus, main: main) + ["--yes"], as: ConfigurePreview.self)
            self.lastActionMessage = self.configurePreview?.message ?? "Route updated."
        }
    }

    func applyMemory(imageModel: String = "mimo-v2.5", helperModel: String = "haiku") async {
        await run { [self] in
            self.memoryPreview = try await self.backend.run([
                "configure", "memory-apply",
                "--image-model", imageModel,
                "--helper-model", helperModel,
                "--yes"
            ], as: MemoryPreview.self)
            self.lastActionMessage = self.memoryPreview?.message ?? "Memory rule updated."
        }
    }

    func resetMemory() async {
        await run { [self] in
            self.memoryPreview = try await self.backend.run(["configure", "memory-reset", "--yes"], as: MemoryPreview.self)
            self.lastActionMessage = self.memoryPreview?.message ?? "Memory rule reset."
        }
    }

    func applyRecommendedSetup() async {
        await run { [self] in
            self.configurePreview = try await self.backend.run([
                "configure", "apply",
                "--haiku-model", "mimo-v2.5",
                "--sonnet-model", "mimo-v2.5-pro[1m]",
                "--opus-model", "mimo-v2.5-pro[1m]",
                "--default-model", "mimo-v2.5-pro[1m]",
                "--yes"
            ], as: ConfigurePreview.self)
            self.memoryPreview = try await self.backend.run([
                "configure", "memory-apply",
                "--image-model", "mimo-v2.5",
                "--helper-model", "haiku",
                "--yes"
            ], as: MemoryPreview.self)
            self.lastActionMessage = "Recommended setup applied."
        }
    }

    func refreshBackups() async {
        await run { [self] in
            let response = try await self.backend.run(["backups", "list"], as: BackupsResponse.self)
            self.backups = response.backups
        }
    }

    func createFullSessionBackup() async {
        guard !isCreatingFullBackup else { return }
        isCreatingFullBackup = true
        isLoading = true
        errorMessage = nil
        defer {
            isCreatingFullBackup = false
            isLoading = false
        }
        do {
            _ = try await self.backend.runRaw(["backups", "create-sessions", "--yes"])
            self.lastActionMessage = "Full session backup created."
            await self.refreshBackups()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreBackup(_ backup: BackupSummary) async {
        await run { [self] in
            _ = try await self.backend.runRaw(["backups", "restore", "--backup", backup.backup_id, "--yes"])
            self.lastActionMessage = "Backup restored."
            await self.refreshBackups()
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func routeArguments(command: String, haiku: String?, sonnet: String?, opus: String?, main: String?) -> [String] {
        var args = ["configure", command]
        appendModelArg("--haiku-model", haiku, to: &args)
        appendModelArg("--sonnet-model", sonnet, to: &args)
        appendModelArg("--opus-model", opus, to: &args)
        appendModelArg("--default-model", main, to: &args)
        return args
    }

    private func appendModelArg(_ name: String, _ value: String?, to args: inout [String]) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            args += [name, trimmed]
        }
    }
}
