import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case health = "Health"
    case sessions = "Sessions"
    case repair = "Repair"
    case configure = "Configure"
    case backups = "Backups"
    case settings = "Settings"
    case logs = "Logs"

    static var allCases: [SidebarItem] {
        [.health, .sessions, .configure, .backups, .settings, .logs]
    }

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        L10n.text(rawValue, language)
    }

    var symbol: String {
        switch self {
        case .health: "waveform.path.ecg"
        case .sessions: "list.bullet.rectangle"
        case .repair: "wrench.and.screwdriver"
        case .configure: "slider.horizontal.3"
        case .backups: "archivebox"
        case .settings: "gearshape"
        case .logs: "doc.text.magnifyingglass"
        }
    }
}

struct DoctorReport: Codable {
    var status: String?
    var discovery: DiscoveryInfo?
    var checks: [String: JSONValue]?
    var ccSwitch: CCSwitchInfo?
    var recentSessions: [SessionSummary]?
}

struct DiscoveryInfo: Codable {
    var claude_bin: String?
    var claude_version: String?
    var claude_home: String?
    var claude_projects_dir: String?
    var claude_sessions_dir: String?
    var claude_global_memory: String?
    var cc_switch_home: String?
    var cc_switch_db: String?
    var cc_switch_settings: String?
    var config_path: String?
}

struct CCSwitchInfo: Codable {
    var exists: Bool?
    var path: String?
    var integrity: String?
    var currentProviders: [ProviderInfo]?
    var providers: [ProviderInfo]?
}

struct ProviderInfo: Codable, Identifiable {
    var id: String
    var app_type: String?
    var name: String?
    var is_current: Int?
    var baseUrl: String?
    var hasAuthToken: Bool?
    var modelEnv: [String: String?]?
}

struct SessionsListResponse: Codable {
    var sessions: [SessionSummary]
    var count: Int
    var total: Int
}

struct SessionSummary: Codable, Identifiable {
    var id: String { sessionId }
    var sessionId: String
    var projectKey: String?
    var projectPath: String?
    var transcriptPath: String
    var activeSessionPath: String?
    var startedAt: String?
    var updatedAt: String?
    var messageCount: Int?
    var modelCounts: [String: Int]?
    var toolUseCounts: [String: Int]?
    var mediaBlockCount: Int?
    var base64RiskCount: Int?
    var imagePathMentionCount: Int?
    var estimatedBytes: Int?
    var risk: String?
    var riskReasons: [String]?
}

struct CleanPreview: Codable {
    var transcriptPath: String
    var mode: String
    var changes: [CleanChange]
    var changeCount: Int
    var backupRequired: Bool?
    var applied: Bool?
    var message: String?
    var backup: String?
}

struct CleanChange: Codable, Identifiable {
    var id: String { "\(line)-\(kind)-\(uuid ?? "")-\(beforeBytes)" }
    var line: Int
    var uuid: String?
    var kind: String
    var beforeBytes: Int
    var afterBytes: Int
    var previewBefore: String
    var previewAfter: String
}

struct ConfigurePreview: Codable {
    var provider: ProviderInfo?
    var before: [String: String?]
    var after: [String: String?]
    var changed: Bool
    var applied: Bool?
    var message: String?
    var backup: String?
}

struct MemoryPreview: Codable {
    var path: String
    var exists: Bool
    var hasManagedBlock: Bool
    var changed: Bool
    var block: String?
    var applied: Bool?
    var message: String?
    var backup: String?
    var helperModel: String?
    var imageModel: String?
    var blockAtEnd: Bool?
}

struct BackupsResponse: Codable {
    var backups: [BackupSummary]
}

struct BackupSummary: Codable, Identifiable {
    var id: String { backup_id }
    var backup_id: String
    var path: String?
    var topic: String?
    var original_path: String?
    var original_copy: String?
    var original_paths: [String]?
    var mode: String?
    var scope: String?
    var totalFiles: Int?
    var totalBytes: Int?
    var restorable: Bool?
    var privacy: String?
}

enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case object([String: JSONValue])
    case array([JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        }
    }

    var display: String {
        switch self {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .bool(let value): value ? "Yes" : "No"
        case .null: "Not found"
        case .object: "Object"
        case .array: "List"
        }
    }
}
