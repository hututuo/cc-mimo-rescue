import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } detail: {
            ZStack {
                AppBackground()
                VStack(spacing: 0) {
                    TopBarView()
                    Divider()
                    ScrollView {
                        currentScreen
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
        .frame(minWidth: 1180, minHeight: 760)
        .alert(store.t("Backend error"), isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button(store.t("OK"), role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch store.selectedItem {
        case .health:
            HealthView()
        case .sessions:
            SessionsView()
        case .repair:
            SessionsView()
        case .configure:
            ConfigureView()
        case .backups:
            BackupsView()
        case .settings:
            SettingsView()
        case .logs:
            LogsView()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List(SidebarItem.allCases, selection: $store.selectedItem) { item in
            Label(item.title(store.language), systemImage: item.symbol)
                .tag(item)
        }
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 28, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.teal)
                Text("CC MiMo Rescue")
                    .font(.headline)
                Text(store.t("Claude Code session repair"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
    }
}

struct TopBarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmFullBackup = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.selectedItem.title(store.language))
                    .font(.title2.weight(.semibold))
                Text(store.t(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if let message = store.lastActionMessage {
                Label(store.t(message), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }

            BackupTopBarControl(confirmFullBackup: $confirmFullBackup)

            Picker(store.t("Language"), selection: $store.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 142)

            Button {
                Task { await refreshCurrent() }
            } label: {
                Label(store.t("Refresh"), systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
        .confirmationDialog(store.t("Create full chat backup?"), isPresented: $confirmFullBackup) {
            Button(store.t("Create Full Backup"), role: .destructive) {
                Task { await store.createFullSessionBackup() }
            }
            Button(store.t("Cancel"), role: .cancel) {}
        } message: {
            Text(store.t("This copies Claude chat records locally before later repairs or configuration changes. The app has no network upload or telemetry and does not collect private data."))
        }
    }

    private var subtitle: String {
        switch store.selectedItem {
        case .health: "Check local paths, provider state, and route readiness."
        case .sessions: "Pick the transcript that needs repair."
        case .repair: "Preview exactly what will change before writing."
        case .configure: "Apply MiMo route and Claude memory guardrails."
        case .backups: "Restore files created by repair or configure actions."
        case .settings: "Inspect backend discovery and local paths."
        case .logs: "Review current app state and action summaries."
        }
    }

    private func refreshCurrent() async {
        switch store.selectedItem {
        case .health:
            await store.refreshHealth()
        case .sessions:
            await store.refreshSessions()
        case .repair:
            await store.previewRepair()
        case .configure:
            await store.refreshConfigure()
        case .backups:
            await store.refreshBackups()
        case .settings, .logs:
            await store.refreshHealth()
        }
    }
}

struct BackupTopBarControl: View {
    @EnvironmentObject private var store: AppStore
    @Binding var confirmFullBackup: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 1) {
                Label(statusText, systemImage: latestFullBackup == nil ? "archivebox" : "checkmark.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(latestFullBackup == nil ? Color.orange : Color.green)
                    .lineLimit(1)
                Text(store.t("Local only, no data collection"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                confirmFullBackup = true
            } label: {
                Label(store.t(store.isCreatingFullBackup ? "Backing up" : "Full Backup"), systemImage: "externaldrive.badge.plus")
            }
            .disabled(store.isCreatingFullBackup)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder((latestFullBackup == nil ? Color.orange : Color.green).opacity(0.45), lineWidth: 1)
        )
    }

    private var latestFullBackup: BackupSummary? {
        store.backups.first { $0.topic == "sessions-full" }
    }

    private var statusText: String {
        guard let backup = latestFullBackup else {
            return store.t("No full chat backup")
        }
        let count = backup.totalFiles.map(String.init) ?? "0"
        return "\(store.t("Full backup ready")) · \(count) \(store.t("files"))"
    }
}

struct HealthView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingFlowCard()

            VStack(alignment: .leading, spacing: 12) {
                Text(store.t("Overview"))
                    .font(.headline)
                StatusStrip()

                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 18) {
                        RouteSummaryCard()
                        RecentRiskCard()
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(spacing: 18) {
                        DiscoveryCard()
                        MemoryStatusCard()
                    }
                    .frame(width: 360, alignment: .top)
                }
            }
        }
    }
}

struct OnboardingFlowCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmRecommendedSetup = false
    @State private var confirmFullBackup = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.teal, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 5) {
                    Text(store.t("Recommended first-run flow"))
                        .font(.title3.weight(.semibold))
                    Text(store.t("Start with a full local chat backup, then configure routes, memory, and repair only dangerous sessions."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    store.selectedItem = .configure
                } label: {
                    Label(store.t("Open Configure"), systemImage: "slider.horizontal.3")
                }

                Button(role: .destructive) {
                    confirmRecommendedSetup = true
                } label: {
                    Label(store.t("One-click Recommended Setup"), systemImage: "checkmark.seal")
                }
                .buttonStyle(.borderedProminent)
                .confirmationDialog(store.t("Apply recommended setup?"), isPresented: $confirmRecommendedSetup) {
                    Button(store.t("Apply with Backup"), role: .destructive) {
                        Task { await store.applyRecommendedSetup() }
                    }
                    Button(store.t("Cancel"), role: .cancel) {}
                } message: {
                    Text(store.t("This sets Haiku to MiMo 2.5, keeps main work on MiMo Pro, and writes the managed memory block at the end of Claude memory."))
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                SetupStep(
                    number: 1,
                    title: "Full chat backup",
                    status: fullBackupSetupStatus,
                    configuration: "Copies Claude projects and sessions into a local backup folder.",
                    operation: "Local only: no network upload, no telemetry, and no private data collection.",
                    buttonTitle: "Create Backup",
                    buttonSymbol: "externaldrive.badge.plus",
                    tint: .blue
                ) {
                    confirmFullBackup = true
                }

                SetupStep(
                    number: 2,
                    title: "Check paths",
                    status: pathSetupStatus,
                    configuration: "No files are changed.",
                    operation: "Reads local Claude, CC Switch, provider, and memory paths so the app knows what is available.",
                    buttonTitle: "Check Now",
                    buttonSymbol: "arrow.clockwise",
                    tint: .teal
                ) {
                    Task { await store.refreshHealth() }
                }

                SetupStep(
                    number: 3,
                    title: "Configure route and memory",
                    status: routeMemorySetupStatus,
                    configuration: "Writes CC Switch route and Claude memory only after backup/confirmation.",
                    operation: "MiMo 2.5 handles image work through the helper slot; main work stays on MiMo Pro.",
                    buttonTitle: "Open Configure",
                    buttonSymbol: "slider.horizontal.3",
                    tint: .purple
                ) {
                    store.selectedItem = .configure
                }

                SetupStep(
                    number: 4,
                    title: "Review dangerous sessions",
                    status: sessionSetupStatus,
                    configuration: "Preview is read-only; repair writes only after you confirm and a backup is created.",
                    operation: "Danger means embedded media/base64 or huge transcript. Warning often only means image path mentions.",
                    buttonTitle: "Open Sessions",
                    buttonSymbol: "eye",
                    tint: .red
                ) {
                    store.selectedItem = .sessions
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.teal.opacity(0.35), lineWidth: 1)
        )
        .confirmationDialog(store.t("Create full chat backup?"), isPresented: $confirmFullBackup) {
            Button(store.t("Create Full Backup"), role: .destructive) {
                Task { await store.createFullSessionBackup() }
            }
            Button(store.t("Cancel"), role: .cancel) {}
        } message: {
            Text(store.t("This copies Claude chat records locally before later repairs or configuration changes. The app has no network upload or telemetry and does not collect private data."))
        }
    }

    private var fullBackupSetupStatus: SetupStepStatus {
        guard let backup = latestFullBackup else {
            return .warning("Full backup recommended")
        }
        let count = backup.totalFiles ?? 0
        return count > 0 ? .done("Full backup ready") : .done("Full backup created")
    }

    private var latestFullBackup: BackupSummary? {
        store.backups.first { $0.topic == "sessions-full" }
    }

    private var pathSetupStatus: SetupStepStatus {
        guard let discovery = store.doctor?.discovery else {
            return .pending("Not checked yet")
        }
        let required = [
            discovery.claude_bin,
            discovery.claude_home,
            discovery.claude_sessions_dir,
            discovery.claude_global_memory,
            discovery.cc_switch_db
        ]
        if required.allSatisfy({ $0?.isEmpty == false }) {
            return .done("All paths look good")
        }
        return .warning("Some paths need review")
    }

    private var routeMemorySetupStatus: SetupStepStatus {
        guard let preview = store.configurePreview else {
            return .pending("Not checked yet")
        }
        guard let memory = store.memoryPreview else {
            return .pending("Not checked yet")
        }
        let routeReady = !preview.changed
        let memoryReady = memory.hasManagedBlock && !memory.changed && (memory.blockAtEnd ?? false)
        return routeReady && memoryReady ? .done("Route and memory ready") : .warning("Route or memory needs setup")
    }

    private var sessionSetupStatus: SetupStepStatus {
        let sessions = store.doctor?.recentSessions ?? store.sessions
        let dangerousCount = sessions.filter { $0.risk == "danger" }.count
        if sessions.isEmpty {
            return .pending("No sessions checked yet")
        }
        if dangerousCount == 0 {
            return .done("No dangerous sessions")
        }
        return .warning("Dangerous sessions found")
    }
}

enum SetupStepStatus {
    case pending(String)
    case done(String)
    case warning(String)

    var text: String {
        switch self {
        case .pending(let text), .done(let text), .warning(let text): text
        }
    }

    var symbol: String {
        switch self {
        case .pending: "circle"
        case .done: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: .secondary
        case .done: .green
        case .warning: .orange
        }
    }
}

struct SetupStep: View {
    @EnvironmentObject private var store: AppStore

    let number: Int
    let title: String
    let status: SetupStepStatus
    let configuration: String
    let operation: String
    let buttonTitle: String
    let buttonSymbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Text(String(number))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(tint, in: Circle())
                Text(store.t(title))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Label(store.t(status.text), systemImage: status.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(status.color)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 5) {
                Label(store.t(configuration), systemImage: "gearshape")
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Label(store.t(operation), systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(action: action) {
                Label(store.t(buttonTitle), systemImage: buttonSymbol)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: 130, alignment: .topLeading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StatusStrip: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 12) {
            MetricTile(
                title: "Setup",
                value: healthLabel,
                symbol: healthSymbol,
                tint: healthTint
            )
            MetricTile(
                title: "Claude",
                value: store.doctor?.discovery?.claude_version ?? "Not found",
                symbol: "terminal",
                tint: .blue
            )
            MetricTile(
                title: "Provider",
                value: currentProviderName,
                symbol: "point.3.connected.trianglepath.dotted",
                tint: .teal
            )
            MetricTile(
                title: "Dangerous sessions",
                value: String(dangerousSessionCount),
                symbol: "exclamationmark.octagon",
                tint: .red,
                borderTint: .red
            )
        }
    }

    private var healthLabel: String {
        let status = store.doctor?.status?.lowercased()
        if status == "ok" { return "Ready" }
        if status == "warning" { return "Needs review" }
        if status == "error" { return "Blocked" }
        return "Unknown"
    }

    private var healthSymbol: String {
        switch healthLabel {
        case "Ready": "checkmark.circle"
        case "Blocked": "xmark.octagon"
        default: "exclamationmark.triangle"
        }
    }

    private var healthTint: Color {
        switch healthLabel {
        case "Ready": .green
        case "Blocked": .red
        default: .orange
        }
    }

    private var currentProviderName: String {
        let provider = store.doctor?.ccSwitch?.currentProviders?.first ?? store.configurePreview?.provider
        return provider?.name ?? "Unknown"
    }

    private var dangerousSessionCount: Int {
        let sessions = store.doctor?.recentSessions ?? store.sessions
        return sessions.filter { $0.risk == "danger" }.count
    }
}

struct RouteSummaryCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        GlassCard {
            CardHeader(
                title: "MiMo route",
                subtitle: "Main work stays on Pro; image helper requests route to 2.5.",
                symbol: "slider.horizontal.3"
            )

            if let preview = store.configurePreview {
                HStack(spacing: 12) {
                    StatusBadge(text: preview.changed ? "Changes pending" : "Already configured", style: preview.changed ? .warning : .ok)
                    Spacer()
                    Button {
                        store.selectedItem = .configure
                    } label: {
                        Label(store.t("Configure"), systemImage: "arrow.right.circle")
                    }
                }
                .padding(.top, 4)

                KeyValueGrid(rows: routeRows(from: preview))
                    .padding(.top, 12)
            } else {
                EmptyState(text: "Run health check to load route details.", symbol: "magnifyingglass")
            }
        }
    }

    private func routeRows(from preview: ConfigurePreview) -> [KeyValueRow] {
        [
            KeyValueRow(label: "Main", value: preview.after["ANTHROPIC_MODEL"] ?? nil),
            KeyValueRow(label: "Sonnet", value: preview.after["ANTHROPIC_DEFAULT_SONNET_MODEL"] ?? nil),
            KeyValueRow(label: "Opus", value: preview.after["ANTHROPIC_DEFAULT_OPUS_MODEL"] ?? nil),
            KeyValueRow(label: "Haiku", value: preview.after["ANTHROPIC_DEFAULT_HAIKU_MODEL"] ?? nil)
        ]
    }
}

struct RecentRiskCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        GlassCard {
            CardHeader(
                title: "Recent sessions",
                subtitle: "Sessions with media blocks, base64 risk, or image path mentions.",
                symbol: "list.bullet.rectangle"
            )

            let source = store.doctor?.recentSessions ?? store.sessions
            if source.isEmpty {
                EmptyState(text: "No sessions loaded yet.", symbol: "tray")
            } else {
                VStack(spacing: 8) {
                    ForEach(source.prefix(5)) { session in
                        SessionRow(session: session, compact: true)
                            .onTapGesture {
                                store.selectedSession = session
                                store.selectedItem = .sessions
                            }
                    }
                }
                .padding(.top, 8)

                Button {
                    store.selectedItem = .sessions
                } label: {
                    Label(store.t("Open Sessions"), systemImage: "arrow.right.circle")
                }
                .padding(.top, 8)
            }
        }
    }
}

struct DiscoveryCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        GlassCard {
            CardHeader(
                title: "Discovered paths",
                subtitle: "Used by the backend to find Claude Code and CC Switch.",
                symbol: "folder.badge.gearshape"
            )

            if let discovery = store.doctor?.discovery {
                VStack(spacing: 10) {
                    PathRow(title: "Claude home", path: discovery.claude_home)
                    PathRow(title: "Sessions", path: discovery.claude_sessions_dir)
                    PathRow(title: "Memory", path: discovery.claude_global_memory)
                    PathRow(title: "CC Switch DB", path: discovery.cc_switch_db)
                    PathRow(title: "Tool config", path: discovery.config_path)
                }
                .padding(.top, 8)
            } else {
                EmptyState(text: "No discovery report loaded.", symbol: "folder")
            }
        }
    }
}

struct MemoryStatusCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        GlassCard {
            CardHeader(
                title: "Memory rule",
                subtitle: "A managed instruction that tells Claude Code how to delegate image work.",
                symbol: "brain.head.profile"
            )

            if let preview = store.memoryPreview {
                HStack {
                    StatusBadge(text: preview.changed ? "Missing or stale" : "Installed", style: preview.changed ? .warning : .ok)
                    Spacer()
                    Button {
                        store.selectedItem = .configure
                    } label: {
                        Label(store.t("Review"), systemImage: "doc.text.magnifyingglass")
                    }
                }
                .padding(.top, 4)

                PathRow(title: "Target", path: preview.path)
                    .padding(.top, 8)
            } else {
                EmptyState(text: "No memory preview loaded.", symbol: "brain")
            }
        }
    }
}

struct SessionsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var riskFilter = "danger"
    @State private var mode = "replace-media-with-placeholder"
    @State private var confirmRepair = false

    private let filters = ["danger", "warning", "All", "ok"]

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            sessionPicker
                .frame(width: 360, alignment: .top)

            VStack(alignment: .leading, spacing: 18) {
                SessionRepairPanel(mode: $mode, confirmRepair: $confirmRepair)
                ChangeListView()
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task {
            if store.sessions.isEmpty {
                await store.refreshSessions(limit: 30)
            }
        }
    }

    private var sessionPicker: some View {
        GlassCard {
            CardHeader(
                title: "Sessions",
                subtitle: "Filter dangerous sessions first, select one, then repair on the right.",
                symbol: "list.bullet.rectangle"
            )

            VStack(spacing: 10) {
                Picker(store.t("Risk"), selection: $riskFilter) {
                    ForEach(filters, id: \.self) { filter in
                        Text(riskFilterLabel(filter)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                TextField(store.t("Search project or session ID"), text: $searchText)
                    .textFieldStyle(.roundedBorder)

                    Button {
                        Task { await store.refreshSessions(limit: 60) }
                    } label: {
                        Label(store.t(store.isRefreshingSessions ? "Loading sessions" : "Reload"), systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(store.isRefreshingSessions)
                }
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 6) {
                RiskHelpLine(style: .warning, title: "Warning", text: "Usually image path mentions or moderate transcript size. It may need no transcript repair.")
                RiskHelpLine(style: .danger, title: "Danger", text: "Embedded media/base64 or a very large transcript. Preview before repair.")
            }
            .padding(.top, 10)

            if filteredSessions.isEmpty {
                EmptyState(text: emptySessionsMessage, symbol: "line.3.horizontal.decrease.circle")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredSessions) { session in
                        SessionRow(session: session, compact: true)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                store.selectedSession = session
                                Task { await store.previewRepair(mode: mode) }
                            }
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private var filteredSessions: [SessionSummary] {
        store.sessions.filter { session in
            let riskMatches = riskFilter == "All" || session.risk == riskFilter
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let textMatches = query.isEmpty
                || session.sessionId.lowercased().contains(query)
                || (session.projectPath ?? "").lowercased().contains(query)
                || (session.projectKey ?? "").lowercased().contains(query)
            return riskMatches && textMatches
        }
    }

    private var emptySessionsMessage: String {
        if store.sessions.isEmpty {
            return "No sessions loaded yet. Click Reload or wait for refresh."
        }
        return "No matching sessions. Clear search or choose another risk filter."
    }

    private func riskFilterLabel(_ filter: String) -> String {
        if filter == "All" { return store.t("All") }
        return store.t(filter.capitalized)
    }
}

struct SessionRepairPanel: View {
    @EnvironmentObject private var store: AppStore
    @Binding var mode: String
    @Binding var confirmRepair: Bool

    var body: some View {
        GlassCard {
            CardHeader(
                title: "Repair workspace",
                subtitle: "Select a session on the left, preview changes, then apply with backup.",
                symbol: "wrench.and.screwdriver"
            )

            if let session = store.selectedSession {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        StatusBadge(text: riskLabel(session.risk), style: BadgeStyle(risk: session.risk))
                        if isPathOnlyWarning(session) {
                            StatusBadge(text: "Path warning only", style: .neutral)
                        }
                        Spacer()
                    }

                    if isPathOnlyWarning(session) {
                        NoticeLine(
                            text: "This warning came from image path mentions. There are no embedded media/base64 blocks to clean.",
                            symbol: "info.circle"
                        )
                    }

                    KeyValueGrid(rows: [
                        KeyValueRow(label: "Project", value: session.projectPath ?? session.projectKey),
                        KeyValueRow(label: "Session", value: session.sessionId),
                        KeyValueRow(label: "Image paths", value: optionalInt(session.imagePathMentionCount)),
                        KeyValueRow(label: "Media/base64", value: String((session.mediaBlockCount ?? 0) + (session.base64RiskCount ?? 0))),
                        KeyValueRow(label: "Updated", value: session.updatedAt)
                    ])

                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.t("Mode"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Picker(store.t("Mode"), selection: $mode) {
                                Text(store.t("Placeholder")).tag("replace-media-with-placeholder")
                                Text(store.t("Strip media")).tag("strip-media-blocks")
                                Text(store.t("Quarantine turn")).tag("quarantine-turn")
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 360)
                        }

                        Spacer(minLength: 0)

                        HStack(spacing: 8) {
                            Button {
                                Task { await store.previewRepair(mode: mode) }
                            } label: {
                                Label(store.t("Preview"), systemImage: "eye")
                            }

                            Button(role: .destructive) {
                                confirmRepair = true
                            } label: {
                                Label(store.t("Apply Repair"), systemImage: "checkmark.seal")
                            }
                            .disabled((store.cleanPreview?.changeCount ?? 0) == 0)
                        }
                    }
                    .confirmationDialog(store.t("Apply session repair?"), isPresented: $confirmRepair) {
                        Button(store.t("Apply with Backup"), role: .destructive) {
                            Task { await store.applyRepair(mode: mode) }
                        }
                        Button(store.t("Cancel"), role: .cancel) {}
                    } message: {
                        Text(store.t("The backend will create a backup before writing the cleaned transcript."))
                    }
                }
                .padding(.top, 8)
            } else {
                EmptyState(text: "Select a session to inspect.", symbol: "cursorarrow.click")
            }
        }
    }
}

struct SessionDetailPanel: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        GlassCard {
            CardHeader(
                title: "Session detail",
                subtitle: "Preview repair before any file is changed.",
                symbol: "sidebar.right"
            )

            if let session = store.selectedSession {
                VStack(alignment: .leading, spacing: 12) {
                    StatusBadge(text: riskLabel(session.risk), style: BadgeStyle(risk: session.risk))

                    KeyValueGrid(rows: [
                        KeyValueRow(label: "Session", value: session.sessionId),
                        KeyValueRow(label: "Project", value: session.projectPath ?? session.projectKey),
                        KeyValueRow(label: "Updated", value: session.updatedAt),
                        KeyValueRow(label: "Messages", value: optionalInt(session.messageCount)),
                        KeyValueRow(label: "Image paths", value: optionalInt(session.imagePathMentionCount)),
                        KeyValueRow(label: "Media/base64", value: String((session.mediaBlockCount ?? 0) + (session.base64RiskCount ?? 0)))
                    ])

                    if let reasons = session.riskReasons, !reasons.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.t("Reasons"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(reasons, id: \.self) { reason in
                                Label(localizedReason(reason, store: store), systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button {
                        Task { await store.previewRepair() }
                    } label: {
                        Label(store.t("Preview Repair"), systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        copy(session.sessionId)
                    } label: {
                        Label(store.t("Copy Session ID"), systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        reveal(path: session.transcriptPath)
                    } label: {
                        Label(store.t("Reveal Transcript"), systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 8)
            } else {
                EmptyState(text: "Select a session to inspect.", symbol: "cursorarrow.click")
            }
        }
    }
}

struct RepairView: View {
    @EnvironmentObject private var store: AppStore
    @State private var mode = "replace-media-with-placeholder"
    @State private var confirmRepair = false

    private let modes = [
        "replace-media-with-placeholder",
        "strip-media-blocks",
        "quarantine-turn"
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            GlassCard {
                CardHeader(
                    title: "Repair target",
                    subtitle: "Choose a cleanup mode, preview changes, then apply with backup.",
                    symbol: "wrench.and.screwdriver"
                )

                HStack(spacing: 12) {
                    Picker(store.t("Mode"), selection: $mode) {
                        Text(store.t("Placeholder")).tag("replace-media-with-placeholder")
                        Text(store.t("Strip media")).tag("strip-media-blocks")
                        Text(store.t("Quarantine turn")).tag("quarantine-turn")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 420)

                    Spacer()

                    Button {
                        Task { await store.previewRepair(mode: mode) }
                    } label: {
                        Label(store.t("Preview"), systemImage: "eye")
                    }
                    .disabled(store.selectedSession == nil)

                    Button(role: .destructive) {
                        confirmRepair = true
                    } label: {
                        Label(store.t("Apply Repair"), systemImage: "checkmark.seal")
                    }
                    .disabled((store.cleanPreview?.changeCount ?? 0) == 0)
                    .confirmationDialog(store.t("Apply session repair?"), isPresented: $confirmRepair) {
                        Button(store.t("Apply with Backup"), role: .destructive) {
                            Task { await store.applyRepair(mode: mode) }
                        }
                        Button(store.t("Cancel"), role: .cancel) {}
                    } message: {
                        Text(store.t("The backend will create a backup before writing the cleaned transcript."))
                    }
                }
                .padding(.top, 8)

                if let session = store.selectedSession {
                    KeyValueGrid(rows: [
                        KeyValueRow(label: "Session", value: session.sessionId),
                        KeyValueRow(label: "Transcript", value: session.transcriptPath),
                        KeyValueRow(label: "Risk", value: riskLabel(session.risk)),
                        KeyValueRow(label: "Image paths", value: optionalInt(session.imagePathMentionCount)),
                        KeyValueRow(label: "Media/base64", value: String((session.mediaBlockCount ?? 0) + (session.base64RiskCount ?? 0)))
                    ])
                    .padding(.top, 12)
                } else {
                    EmptyState(text: "Select a session from Sessions first.", symbol: "list.bullet.rectangle")
                        .padding(.top, 8)
                }
            }

            HStack(alignment: .top, spacing: 18) {
                ChangeListView()
                    .frame(maxWidth: .infinity, alignment: .top)

                RepairSafetyPanel()
                    .frame(width: 360)
            }
        }
    }
}

struct ChangeListView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        GlassCard {
            CardHeader(
                title: "Preview changes",
                subtitle: "Line-level changes detected by the backend.",
                symbol: "doc.text.magnifyingglass"
            )

            if let preview = store.cleanPreview {
                if preview.changes.isEmpty {
                    EmptyState(text: preview.message ?? emptyPreviewMessage, symbol: "checkmark.circle")
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(preview.changes) { change in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    StatusBadge(text: change.kind, style: .warning)
                                    Text("\(store.t("Line")) \(change.line)")
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                    Text("\(change.beforeBytes) -> \(change.afterBytes) \(store.t("bytes"))")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Text(change.previewBefore)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                Text(change.previewAfter)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.top, 8)
                }
            } else {
                EmptyState(text: "No preview yet.", symbol: "eye")
            }
        }
    }

    private var emptyPreviewMessage: String {
        guard let session = store.selectedSession else {
            return "No media blocks need cleanup."
        }
        let mediaBlocks = (session.mediaBlockCount ?? 0) + (session.base64RiskCount ?? 0)
        if mediaBlocks == 0 && (session.imagePathMentionCount ?? 0) > 0 {
            return "This warning came from image path mentions. There are no embedded media/base64 blocks to clean."
        }
        return "No media blocks need cleanup."
    }
}

struct RepairSafetyPanel: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        GlassCard {
            CardHeader(
                title: "Safety",
                subtitle: "Repair writes only after a preview and creates a restorable backup.",
                symbol: "shield"
            )

            if let preview = store.cleanPreview {
                KeyValueGrid(rows: [
                    KeyValueRow(label: "Changes", value: String(preview.changeCount)),
                    KeyValueRow(label: "Backup required", value: (preview.backupRequired ?? true) ? "Yes" : "No"),
                    KeyValueRow(label: "Applied", value: (preview.applied ?? false) ? "Yes" : "No"),
                    KeyValueRow(label: "Backup", value: preview.backup)
                ])
                .padding(.top, 8)
            }

            VStack(alignment: .leading, spacing: 8) {
                SafetyLine(text: "Preview is read-only.")
                SafetyLine(text: "Apply requires explicit confirmation.")
                SafetyLine(text: "Restore is available from Backups.")
            }
            .padding(.top, 12)
        }
    }
}

struct ConfigureView: View {
    @EnvironmentObject private var store: AppStore
    @State private var pendingRoute = ""
    @State private var confirmRoute = false
    @State private var confirmMemory = false
    @State private var confirmMemoryReset = false
    @State private var imageModel = "mimo-v2.5"
    @State private var helperSlot = "haiku"
    @State private var mainModel = ""
    @State private var sonnetModel = ""
    @State private var opusModel = ""
    @State private var haikuModel = ""

    private let helperSlots = ["haiku", "sonnet", "opus", "main"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                recommendedRouteCard
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .top)
                memoryCard
                    .frame(width: 430, alignment: .top)
            }

            customRouteCard
        }
        .confirmationDialog(store.t("Apply model route?"), isPresented: $confirmRoute) {
            Button(store.t("Apply with Backup"), role: .destructive) {
                Task { await applyPendingRoute() }
            }
            Button(store.t("Cancel"), role: .cancel) {}
        } message: {
            Text(store.t("This writes the selected CC Switch route and syncs memory when the image helper route is changed."))
        }
        .confirmationDialog(store.t("Apply Claude memory rule?"), isPresented: $confirmMemory) {
            Button(store.t("Apply with Backup"), role: .destructive) {
                Task { await store.applyMemory(imageModel: imageModel, helperModel: helperSlot) }
            }
            Button(store.t("Cancel"), role: .cancel) {}
        } message: {
            Text(store.t("This writes the managed block at the end of the Claude memory file after creating a backup."))
        }
        .confirmationDialog(store.t("Reset Claude memory rule?"), isPresented: $confirmMemoryReset) {
            Button(store.t("Reset with Backup"), role: .destructive) {
                Task { await store.resetMemory() }
            }
            Button(store.t("Cancel"), role: .cancel) {}
        } message: {
            Text(store.t("This removes only the cc-mimo-rescue managed block after creating a backup."))
        }
        .task {
            if store.configurePreview == nil || store.memoryPreview == nil {
                await store.refreshConfigure()
            }
            syncRouteFieldsIfNeeded()
            setImageModelForHelper()
            await store.previewMemory(imageModel: imageModel, helperModel: helperSlot)
        }
        .onChange(of: helperSlot) { _, _ in
            setImageModelForHelper()
            Task {
                await previewRoute()
                await store.previewMemory(imageModel: imageModel, helperModel: helperSlot)
            }
        }
    }

    private var recommendedRouteCard: some View {
        GlassCard {
            CardHeader(
                title: "Recommended route",
                subtitle: "Normal use: put image and drawing requests on Haiku with MiMo 2.5.",
                symbol: "wand.and.stars"
            )

            if let preview = store.configurePreview {
                HStack {
                    StatusBadge(text: preview.changed ? "Changes pending" : "Already configured", style: preview.changed ? .warning : .ok)
                    Spacer()
                    Button {
                        setRecommendedRoute()
                        Task {
                            await previewRoute()
                            await store.previewMemory(imageModel: imageModel, helperModel: helperSlot)
                        }
                    } label: {
                        Label(store.t("Preview"), systemImage: "eye")
                    }
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.teal, in: RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 5) {
                            Text(store.t("Put MiMo 2.5 into Haiku"))
                                .font(.headline)
                            Text(store.t("This is the recommended setup for most users. Main work stays on MiMo Pro; image and drawing work uses the lighter Haiku helper slot."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.t("Image model"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("mimo-v2.5", text: $imageModel)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: .infinity)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.t("Helper slot"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Picker(store.t("Helper slot"), selection: $helperSlot) {
                                ForEach(helperSlots, id: \.self) { slot in
                                    Text(store.t(slot.capitalized)).tag(slot)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Button(role: .destructive) {
                        setRecommendedRoute()
                        pendingRoute = "all"
                        confirmRoute = true
                    } label: {
                        Label(store.t("Apply 2.5 to Helper"), systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(14)
                .background(Color.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.teal.opacity(0.35), lineWidth: 1)
                )
                .padding(.top, 12)
            } else {
                EmptyState(text: "Route preview is not loaded.", symbol: "slider.horizontal.3")
            }
        }
    }

    private var memoryCard: some View {
        GlassCard {
            CardHeader(
                title: "Claude memory",
                subtitle: "Keeps Claude aware of the selected image helper model.",
                symbol: "brain.head.profile"
            )

            if let preview = store.memoryPreview {
                HStack {
                    StatusBadge(text: preview.changed ? "Changes pending" : "Installed", style: preview.changed ? .warning : .ok)
                    Spacer()
                    if preview.hasManagedBlock {
                        Button(role: .destructive) {
                            confirmMemoryReset = true
                        } label: {
                            Label(store.t("Reset"), systemImage: "arrow.counterclockwise")
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.top, 8)

                KeyValueGrid(rows: [
                    KeyValueRow(label: "Memory file", value: preview.path),
                    KeyValueRow(label: "Image helper slot", value: helperSlot.capitalized),
                    KeyValueRow(label: "Image model", value: imageModel),
                    KeyValueRow(label: "Block at end", value: (preview.blockAtEnd ?? false) ? "Yes" : "No")
                ])
                .padding(.top, 12)

                NoticeLine(
                    text: "Claude should not read image or binary files directly because that can freeze the conversation. The helper reads or OCRs them first, then returns text.",
                    symbol: "exclamationmark.triangle"
                )
                .padding(.top, 10)

                if let block = preview.block {
                    Text(block.isEmpty ? store.t("Managed block will be removed.") : block)
                        .font(.caption.monospaced())
                        .lineLimit(7)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 8)
                }

                HStack {
                    Button {
                        Task { await store.previewMemory(imageModel: imageModel, helperModel: helperSlot) }
                    } label: {
                        Label(store.t("Preview Memory"), systemImage: "eye")
                    }

                    Spacer()

                    Button(role: .destructive) {
                        confirmMemory = true
                    } label: {
                        Label(store.t("Apply Memory Rule"), systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
                .padding(.top, 12)
            } else {
                EmptyState(text: "Memory preview is not loaded.", symbol: "brain")
            }
        }
    }

    private var customRouteCard: some View {
        GlassCard {
            CardHeader(
                title: "Custom",
                subtitle: "Advanced model slots. Use this only if you want to route each Claude model separately.",
                symbol: "slider.horizontal.3"
            )

            if let preview = store.configurePreview {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.t("Image helper slot"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker(store.t("Image helper slot"), selection: $helperSlot) {
                            ForEach(helperSlots, id: \.self) { slot in
                                Text(store.t(slot.capitalized)).tag(slot)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .frame(width: 180)

                    Button {
                        setImageModelForHelper()
                        Task {
                            await previewRoute()
                            await store.previewMemory(imageModel: imageModel, helperModel: helperSlot)
                        }
                    } label: {
                        Label(store.t("Set 2.5 to helper"), systemImage: "wand.and.stars")
                    }

                    Spacer()
                }
                .padding(.top, 12)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    RouteModelRow(title: "Main", key: "ANTHROPIC_MODEL", value: $mainModel, isHelper: helperSlot == "main") {
                        mainModel = imageModel
                    } onApply: {
                        pendingRoute = "main"
                        confirmRoute = true
                    }
                    RouteModelRow(title: "Sonnet", key: "ANTHROPIC_DEFAULT_SONNET_MODEL", value: $sonnetModel, isHelper: helperSlot == "sonnet") {
                        sonnetModel = imageModel
                    } onApply: {
                        pendingRoute = "sonnet"
                        confirmRoute = true
                    }
                    RouteModelRow(title: "Opus", key: "ANTHROPIC_DEFAULT_OPUS_MODEL", value: $opusModel, isHelper: helperSlot == "opus") {
                        opusModel = imageModel
                    } onApply: {
                        pendingRoute = "opus"
                        confirmRoute = true
                    }
                    RouteModelRow(title: "Haiku", key: "ANTHROPIC_DEFAULT_HAIKU_MODEL", value: $haikuModel, isHelper: helperSlot == "haiku") {
                        haikuModel = imageModel
                    } onApply: {
                        pendingRoute = "haiku"
                        confirmRoute = true
                    }
                }
                .padding(.top, 12)

                ConfigDiffView(before: preview.before, after: preview.after)
                    .padding(.top, 12)

                HStack {
                    Button {
                        Task {
                            await previewRoute()
                            await store.previewMemory(imageModel: imageModel, helperModel: helperSlot)
                        }
                    } label: {
                        Label(store.t("Preview"), systemImage: "eye")
                    }

                    Spacer()

                    Button(role: .destructive) {
                        pendingRoute = "all"
                        confirmRoute = true
                    } label: {
                        Label(store.t("Apply Custom Routes + Memory"), systemImage: "checkmark.seal")
                    }
                }
                .padding(.top, 12)
            } else {
                EmptyState(text: "Route preview is not loaded.", symbol: "slider.horizontal.3")
            }
        }
    }

    private func syncRouteFieldsIfNeeded() {
        guard let after = store.configurePreview?.after else { return }
        if mainModel.isEmpty {
            mainModel = routeValue(after, "ANTHROPIC_MODEL", fallback: "mimo-v2.5-pro[1m]")
        }
        if sonnetModel.isEmpty {
            sonnetModel = routeValue(after, "ANTHROPIC_DEFAULT_SONNET_MODEL", fallback: "mimo-v2.5-pro[1m]")
        }
        if opusModel.isEmpty {
            opusModel = routeValue(after, "ANTHROPIC_DEFAULT_OPUS_MODEL", fallback: "mimo-v2.5-pro[1m]")
        }
        if haikuModel.isEmpty {
            haikuModel = routeValue(after, "ANTHROPIC_DEFAULT_HAIKU_MODEL", fallback: "mimo-v2.5")
            imageModel = haikuModel
        }
    }

    private func routeValue(_ values: [String: String?], _ key: String, fallback: String) -> String {
        if let value = values[key] ?? nil, !value.isEmpty {
            return value
        }
        return fallback
    }

    private func setImageModelForHelper() {
        switch helperSlot {
        case "main": mainModel = imageModel
        case "sonnet": sonnetModel = imageModel
        case "opus": opusModel = imageModel
        default: haikuModel = imageModel
        }
    }

    private func setRecommendedRoute() {
        imageModel = "mimo-v2.5"
        setImageModelForHelper()
    }

    private func previewRoute() async {
        await store.previewRoute(haiku: haikuModel, sonnet: sonnetModel, opus: opusModel, main: mainModel)
    }

    private func applyPendingRoute() async {
        switch pendingRoute {
        case "main":
            await store.applyRoute(main: mainModel)
        case "sonnet":
            await store.applyRoute(sonnet: sonnetModel)
        case "opus":
            await store.applyRoute(opus: opusModel)
        case "haiku":
            await store.applyRoute(haiku: haikuModel)
        default:
            await store.applyRoute(haiku: haikuModel, sonnet: sonnetModel, opus: opusModel, main: mainModel)
        }
        if pendingRoute == "all" || pendingRoute == helperSlot {
            await store.applyMemory(imageModel: imageModel, helperModel: helperSlot)
        } else {
            await store.previewMemory(imageModel: imageModel, helperModel: helperSlot)
        }
    }
}

struct RouteModelRow: View {
    @EnvironmentObject private var store: AppStore

    let title: String
    let key: String
    @Binding var value: String
    let isHelper: Bool
    let onUseImage: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(store.t(title))
                    .font(.caption.weight(.semibold))
                if isHelper {
                    StatusBadge(text: "Image helper", style: .warning)
                }
                Spacer()
            }

            Text(shortModelKey(key))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)

            TextField(store.t("Model name"), text: $value)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button {
                    onUseImage()
                } label: {
                    Label(store.t("Use 2.5"), systemImage: "photo")
                }
                .fixedSize()

                Spacer()

                Button(role: .destructive) {
                    onApply()
                } label: {
                    Label(store.t("Apply This"), systemImage: "checkmark")
                }
                .fixedSize()
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ConfigDiffView: View {
    let before: [String: String?]
    let after: [String: String?]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                HStack(spacing: 8) {
                    Text(shortKey(key))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    Text(display(before[key] ?? nil))
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    Text(display(after[key] ?? nil))
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var keys: [String] {
        Array(Set(before.keys).union(after.keys)).sorted()
    }

    private func shortKey(_ key: String) -> String {
        key.replacingOccurrences(of: "ANTHROPIC_DEFAULT_", with: "")
            .replacingOccurrences(of: "ANTHROPIC_", with: "")
    }

    private func display(_ value: String?) -> String {
        value?.isEmpty == false ? value! : "Not set"
    }
}

struct DiffValue: View {
    @EnvironmentObject private var store: AppStore

    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(store.t(label))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(store.t(value ?? "Not set"))
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BackupsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var pendingRestore: BackupSummary?
    @State private var showRestoreDialog = false

    var body: some View {
        GlassCard {
            CardHeader(
                title: "Backups",
                subtitle: "Files created before repair, configuration, or memory writes.",
                symbol: "archivebox"
            )

            if store.backups.isEmpty {
                EmptyState(text: "No backups found.", symbol: "archivebox")
            } else {
                VStack(spacing: 8) {
                    ForEach(store.backups) { backup in
                        HStack(spacing: 12) {
                            Image(systemName: "archivebox")
                                .foregroundStyle(.teal)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(backup.backup_id)
                                    .font(.callout.weight(.semibold))
                                Text(backup.original_path ?? backup.path ?? store.t("Unknown path"))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            StatusBadge(text: backup.topic ?? backup.mode ?? "backup", style: .neutral)
                            if backup.original_path != nil {
                                Button(role: .destructive) {
                                    pendingRestore = backup
                                    showRestoreDialog = true
                                } label: {
                                    Label(store.t("Restore"), systemImage: "arrow.counterclockwise")
                                }
                            } else {
                                Label(store.t("Full backup"), systemImage: "checkmark.shield")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.top, 8)
            }
        }
        .task { await store.refreshBackups() }
        .confirmationDialog(store.t("Restore backup?"), isPresented: $showRestoreDialog) {
            if let backup = pendingRestore {
                Button("\(store.t("Restore")) \(backup.backup_id)", role: .destructive) {
                    Task { await store.restoreBackup(backup) }
                }
            }
            Button(store.t("Cancel"), role: .cancel) {}
        } message: {
            Text("\(store.t("This restores the original file recorded for")) \(pendingRestore?.backup_id ?? store.t("the selected backup")).")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        GlassCard {
            CardHeader(
                title: "Settings",
                subtitle: "Read-only in this MVP. The backend auto-discovers local paths.",
                symbol: "gearshape"
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(store.t("Language"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker(store.t("Language"), selection: $store.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(.top, 14)
            .padding(.bottom, 12)

            if let discovery = store.doctor?.discovery {
                KeyValueGrid(rows: [
                    KeyValueRow(label: "Claude binary", value: discovery.claude_bin),
                    KeyValueRow(label: "Claude home", value: discovery.claude_home),
                    KeyValueRow(label: "Projects", value: discovery.claude_projects_dir),
                    KeyValueRow(label: "Sessions", value: discovery.claude_sessions_dir),
                    KeyValueRow(label: "CC Switch home", value: discovery.cc_switch_home),
                    KeyValueRow(label: "CC Switch DB", value: discovery.cc_switch_db),
                    KeyValueRow(label: "Config", value: discovery.config_path)
                ])
            } else {
                EmptyState(text: "Run Health refresh to load settings.", symbol: "gearshape")
            }
        }
    }
}

struct LogsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        GlassCard {
            CardHeader(
                title: "Logs",
                subtitle: "A compact app-side view of recent state.",
                symbol: "doc.text.magnifyingglass"
            )

            VStack(alignment: .leading, spacing: 10) {
                LogLine(title: "Last action", value: store.lastActionMessage ?? "None")
                LogLine(title: "Backend error", value: store.errorMessage ?? "None")
                LogLine(title: "Loaded sessions", value: String(store.sessions.count))
                LogLine(title: "Loaded backups", value: String(store.backups.count))
                LogLine(title: "Selected session", value: store.selectedSession?.sessionId ?? "None")
            }
            .padding(.top, 8)
        }
    }
}

struct SessionRow: View {
    let session: SessionSummary
    let compact: Bool
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 12) {
            StatusBadge(text: riskLabel(session.risk), style: BadgeStyle(risk: session.risk))
                .frame(width: compact ? 82 : 96, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.projectPath ?? session.projectKey ?? store.t("Unknown project"))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(session.sessionId)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if !compact {
                SessionMetric(symbol: "photo", value: session.imagePathMentionCount ?? 0, help: "Image path mentions")
                SessionMetric(symbol: "doc.badge.ellipsis", value: (session.mediaBlockCount ?? 0) + (session.base64RiskCount ?? 0), help: "Media/base64 risk")
                SessionMetric(symbol: "text.bubble", value: session.messageCount ?? 0, help: "Messages")
            }

            Button {
                store.selectedSession = session
                Task { await store.previewRepair() }
            } label: {
                Image(systemName: "eye")
            }
            .buttonStyle(.borderless)
            .help(store.t("Preview repair"))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(store.selectedSession?.sessionId == session.sessionId ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.16))
        )
    }
}

struct CardHeader: View {
    @EnvironmentObject private var store: AppStore

    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.teal)
                .frame(width: 28, height: 28)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(store.t(title))
                    .font(.headline)
                Text(store.t(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct MetricTile: View {
    @EnvironmentObject private var store: AppStore

    let title: String
    let value: String
    let symbol: String
    let tint: Color
    var borderTint: Color? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(store.t(title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.t(value))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 74)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderTint?.opacity(0.75) ?? Color.white.opacity(0.16), lineWidth: borderTint == nil ? 1 : 1.4)
        )
    }
}

enum BadgeStyle {
    case ok
    case warning
    case danger
    case neutral

    init(risk: String?) {
        switch risk?.lowercased() {
        case "ok": self = .ok
        case "danger", "error": self = .danger
        case "warning": self = .warning
        default: self = .neutral
        }
    }

    var color: Color {
        switch self {
        case .ok: .green
        case .warning: .orange
        case .danger: .red
        case .neutral: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        case .neutral: "circle.fill"
        }
    }
}

struct StatusBadge: View {
    @EnvironmentObject private var store: AppStore

    let text: String
    let style: BadgeStyle

    var body: some View {
        Label(store.t(text), systemImage: style.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(style.color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(style.color.opacity(0.12), in: Capsule())
    }
}

struct KeyValueRow: Identifiable {
    var id: String { label }
    let label: String
    let value: String?
}

struct KeyValueGrid: View {
    @EnvironmentObject private var store: AppStore

    let rows: [KeyValueRow]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 12) {
                    Text(store.t(row.label))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 94, alignment: .leading)
                    Text(store.t(row.value?.isEmpty == false ? row.value! : "Not found"))
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct PathRow: View {
    @EnvironmentObject private var store: AppStore

    let title: String
    let path: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: path == nil ? "questionmark.folder" : "folder")
                .foregroundStyle(path == nil ? Color.secondary : Color.teal)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.t(title))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(path ?? store.t("Not found"))
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if let path {
                Button {
                    reveal(path: path)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help(store.t("Reveal in Finder"))
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SessionMetric: View {
    @EnvironmentObject private var store: AppStore

    let symbol: String
    let value: Int
    let help: String

    var body: some View {
        Label(String(value), systemImage: symbol)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 66, alignment: .leading)
            .help(store.t(help))
    }
}

struct SafetyLine: View {
    @EnvironmentObject private var store: AppStore

    let text: String

    var body: some View {
        Label(store.t(text), systemImage: "checkmark.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct NoticeLine: View {
    @EnvironmentObject private var store: AppStore

    let text: String
    let symbol: String

    var body: some View {
        Label(store.t(text), systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.teal)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct RiskHelpLine: View {
    @EnvironmentObject private var store: AppStore

    let style: BadgeStyle
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: style.symbol)
                .foregroundStyle(style.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.t(title))
                    .font(.caption.weight(.semibold))
                Text(store.t(text))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct LogLine: View {
    @EnvironmentObject private var store: AppStore

    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(store.t(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(store.t(value))
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Spacer()
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct EmptyState: View {
    @EnvironmentObject private var store: AppStore

    let text: String
    let symbol: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(store.t(text))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.teal.opacity(0.08),
                Color.indigo.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private func optionalInt(_ value: Int?) -> String? {
    value.map(String.init)
}

private func riskLabel(_ risk: String?) -> String {
    switch risk?.lowercased() {
    case "ok": "Ok"
    case "warning": "Warning"
    case "danger", "error": "Danger"
    default: "Unknown"
    }
}

private func isPathOnlyWarning(_ session: SessionSummary) -> Bool {
    let mediaBlocks = (session.mediaBlockCount ?? 0) + (session.base64RiskCount ?? 0)
    return mediaBlocks == 0 && (session.imagePathMentionCount ?? 0) > 0
}

private func shortModelKey(_ key: String) -> String {
    key.replacingOccurrences(of: "ANTHROPIC_DEFAULT_", with: "")
        .replacingOccurrences(of: "ANTHROPIC_", with: "")
}

@MainActor
private func localizedReason(_ reason: String, store: AppStore) -> String {
    let parts = reason.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else { return store.t(reason) }
    let label = store.t(String(parts[0]))
    return "\(label):\(parts[1])"
}

private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

private func reveal(path: String) {
    let url = URL(fileURLWithPath: path)
    NSWorkspace.shared.activateFileViewerSelecting([url])
}
