import Foundation

// MARK: - Security Audit Log

/// Local-only audit trail for all token access operations.
struct SecurityLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let action: Action
    let tokenID: UUID
    let tokenName: String
    let provider: String

    enum CodingKeys: String, CodingKey {
        case id, timestamp, action, provider
        case tokenID = "secretID"
        case tokenName = "secretName"
    }

    enum Action: String, Codable, CaseIterable {
        /// Localized verb; `rawValue` is the persisted value.
        var displayName: String { L(rawValue) }

        case copied = "複製"
        case viewed = "檢視"
        case exported = "匯出"
        case imported = "匯入"
        case created = "建立"
        case edited = "編輯"
        case deleted = "刪除"
        case restored = "恢復"
        case locked = "鎖定"
        case unlocked = "解鎖"
        case rotation = "輪換"

        var icon: String {
            switch self {
            case .copied: return "doc.on.doc"
            case .viewed: return "eye"
            case .exported: return "square.and.arrow.up"
            case .imported: return "square.and.arrow.down"
            case .created: return "plus.circle"
            case .edited: return "pencil"
            case .deleted: return "trash"
            case .restored: return "arrow.uturn.backward"
            case .locked: return "lock"
            case .unlocked: return "lock.open"
            case .rotation: return "arrow.triangle.2.circlepath"
            }
        }
    }

    var relativeTime: String {
        guard Date().timeIntervalSince(timestamp) < 86400 else {
            return timestamp.formatted(date: .abbreviated, time: .shortened)
        }
        // Locale-aware: "6 hours ago" in English, "6 小時前" in Chinese, no hand-written cases.
        return Self.relativeFormatter.localizedString(for: timestamp, relativeTo: Date())
    }

    /// Rebuilt per call so the timestamps follow the app's language, not the device's.
    private static var relativeFormatter: RelativeDateTimeFormatter {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.locale = LanguageStore.shared.locale
        return f
    }
}

// MARK: - Security Log Store

final class SecurityLogService: ObservableObject {
    static let shared = SecurityLogService()

    @Published var entries: [SecurityLogEntry] = []
    private let maxEntries = 500

    private var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TokenVault/security_log.json")
    }

    init() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        load()
    }

    func log(_ action: SecurityLogEntry.Action, tokenID: UUID, name: String, provider: String) {
        let entry = SecurityLogEntry(
            id: UUID(), timestamp: Date(), action: action,
            tokenID: tokenID, tokenName: name, provider: provider
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        save()
    }

    func entriesForToday() -> [SecurityLogEntry] {
        let cal = Calendar.current
        return entries.filter { cal.isDateInToday($0.timestamp) }
    }

    func entries(for tokenID: UUID) -> [SecurityLogEntry] {
        entries.filter { $0.tokenID == tokenID }
    }

    /// Wipe the local audit trail. The macOS build has no clear button; the phone does, because a
    /// 500-entry log is a screen you scroll rather than a list you read.
    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([SecurityLogEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
