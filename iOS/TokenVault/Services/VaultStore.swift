import Foundation
import SwiftUI

/// A folder. Stored alongside the tokens in the same JSON the macOS app writes, so a vault file
/// moves between the two builds unchanged.
struct VaultGroup: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var icon: String
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, icon: String = "folder", sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
    }
}

/// What the list is currently narrowed to.
enum VaultFilter: Hashable {
    case all
    case favorites
    case expiring
    case category(TokenCategory)

    var label: String {
        switch self {
        case .all: return "全部"
        case .favorites: return "收藏"
        case .expiring: return "即將到期"
        case .category(let c): return c.rawValue
        }
    }

    var symbol: String? {
        switch self {
        case .all: return nil
        case .favorites: return "star.fill"
        case .expiring: return "clock.badge.exclamationmark"
        case .category(let c): return c.icon
        }
    }
}

/// The vault: one JSON file inside the app's Documents directory, one encrypted value per token.
///
/// Writes are immediate (atomic replace). There is no debounce because iOS can suspend the app
/// between any two instructions — a copy the user just made must already be on disk.
final class VaultStore: ObservableObject {
    @Published private(set) var tokens: [TokenItem] = []
    @Published private(set) var groups: [VaultGroup] = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Snapshot (identical shape to the macOS build)

    private struct MacGroup: Codable {
        var id: UUID
        var name: String
        var icon: String
        var sortOrder: Int
        var tokens: [TokenItem]
    }

    private struct Snapshot: Codable {
        var groups: [MacGroup]
        var tokens: [TokenItem]
    }

    init(reset: Bool = false) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("Vault", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("tokens.json")

        if reset {
            try? FileManager.default.removeItem(at: fileURL)
        }
        load()
    }

    var storeURL: URL { fileURL }

    // MARK: - Derived

    var activeTokens: [TokenItem] { tokens.filter { !$0.isDeleted } }
    var trashedTokens: [TokenItem] {
        tokens.filter(\.isDeleted).sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }
    var favorites: [TokenItem] { activeTokens.filter(\.isFavorite) }
    var expiring: [TokenItem] { activeTokens.filter { $0.isExpired || $0.expiresSoon } }

    var categoriesInUse: [TokenCategory] {
        TokenCategory.allCases.filter { c in activeTokens.contains { $0.category == c } }
    }

    func group(for id: UUID?) -> VaultGroup? {
        guard let id else { return nil }
        return groups.first { $0.id == id }
    }

    /// Tokens for a screen, already filtered and ordered: favorites first, then most recently used.
    func visibleTokens(_ filter: VaultFilter, query: String) -> [TokenItem] {
        var result: [TokenItem] = activeTokens

        switch filter {
        case .all: break
        case .favorites: result = result.filter(\.isFavorite)
        case .expiring: result = result.filter { $0.isExpired || $0.expiresSoon }
        case .category(let category): result = result.filter { $0.category == category }
        }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            result = applySearch(trimmed, to: result)
        }

        return result.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            let l = lhs.lastUsedAt ?? lhs.createdAt
            let r = rhs.lastUsedAt ?? rhs.createdAt
            return l > r
        }
    }

    // MARK: - Search
    //
    // Same grammar as the macOS build: tag: / cat: / provider: / expired:true / fav:true.

    private func applySearch(_ query: String, to source: [TokenItem]) -> [TokenItem] {
        var result = source
        var freeText = query

        for word in query.components(separatedBy: .whitespaces) where !word.isEmpty {
            func drop() { freeText = freeText.replacingOccurrences(of: word, with: "") }
            if word.hasPrefix("tag:") {
                let tag = String(word.dropFirst(4)).lowercased()
                result = result.filter { $0.tags.contains { $0.lowercased() == tag } }
                drop()
            } else if word.hasPrefix("cat:") {
                let text = String(word.dropFirst(4))
                result = result.filter { $0.category.rawValue.localizedCaseInsensitiveContains(text) }
                drop()
            } else if word.hasPrefix("provider:") {
                let text = String(word.dropFirst(9))
                result = result.filter { $0.provider.rawValue.localizedCaseInsensitiveContains(text) }
                drop()
            } else if word == "expired:true" {
                result = result.filter(\.isExpired)
                drop()
            } else if word == "fav:true" || word == "favorite:true" {
                result = result.filter(\.isFavorite)
                drop()
            }
        }

        let needle = freeText.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return result }

        return result.filter { token in
            token.name.localizedCaseInsensitiveContains(needle)
            || token.note.localizedCaseInsensitiveContains(needle)
            || token.environment.rawValue.localizedCaseInsensitiveContains(needle)
            || token.provider.rawValue.localizedCaseInsensitiveContains(needle)
            || token.category.rawValue.localizedCaseInsensitiveContains(needle)
            || token.kind.rawValue.localizedCaseInsensitiveContains(needle)
            || token.tags.contains { $0.localizedCaseInsensitiveContains(needle) }
            || (needle.count >= 3 && token.decryptedValue().localizedCaseInsensitiveContains(needle))
        }
    }

    // MARK: - Load / save

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(Snapshot.self, from: data) else { return }

        var byID: [UUID: TokenItem] = [:]
        for token in snapshot.tokens { byID[token.id] = token }
        // The macOS build mirrors each token inside its group; recover anything that only
        // exists there so an older file cannot lose rows.
        for group in snapshot.groups {
            for token in group.tokens where byID[token.id] == nil {
                byID[token.id] = token
            }
        }
        tokens = Array(byID.values)
        groups = snapshot.groups
            .map { VaultGroup(id: $0.id, name: $0.name, icon: $0.icon, sortOrder: $0.sortOrder) }
            .sorted { $0.sortOrder < $1.sortOrder }

        purgeTrash(olderThan: 30)
    }

    func save() {
        let macGroups = groups.map { group in
            MacGroup(id: group.id, name: group.name, icon: group.icon, sortOrder: group.sortOrder,
                     tokens: tokens.filter { $0.groupID == group.id })
        }
        let snapshot = Snapshot(groups: macGroups, tokens: tokens)
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func commit(touching token: TokenItem? = nil, _ log: (() -> Void)? = nil) {
        token?.touch()
        log?()
        save()
        objectWillChange.send()
        ICloudSyncService.shared.requestSync()
    }

    // MARK: - Mutations

    func add(_ token: TokenItem, note: String = "已加密儲存") {
        tokens.append(token)
        commit(touching: token) {
            SecurityLogService.shared.log(.created, tokenID: token.id, name: token.name,
                                          provider: token.provider.rawValue)
        }
    }

    /// Call after mutating a token in place (the editor writes straight to the model).
    func commitEdits(to token: TokenItem) {
        commit(touching: token) {
            SecurityLogService.shared.log(.edited, tokenID: token.id, name: token.name,
                                          provider: token.provider.rawValue)
        }
    }

    func toggleFavorite(_ token: TokenItem) {
        token.isFavorite.toggle()
        commit(touching: token)
    }

    func recordUse(_ token: TokenItem) {
        token.lastUsedAt = Date()
        token.copyCount += 1
        commit(touching: token) {
            SecurityLogService.shared.log(.copied, tokenID: token.id, name: token.name,
                                          provider: token.provider.rawValue)
        }
    }

    func trash(_ token: TokenItem) {
        token.deletedAt = Date()
        commit(touching: token) {
            SecurityLogService.shared.log(.deleted, tokenID: token.id, name: token.name,
                                          provider: token.provider.rawValue)
        }
    }

    func restore(_ token: TokenItem) {
        token.deletedAt = nil
        commit(touching: token) {
            SecurityLogService.shared.log(.restored, tokenID: token.id, name: token.name,
                                          provider: token.provider.rawValue)
        }
    }

    func deleteForever(_ token: TokenItem) {
        tokens.removeAll { $0.id == token.id }
        commit(touching: token)
    }

    func emptyTrash() {
        tokens.removeAll(where: \.isDeleted)
        commit()
    }

    private func purgeTrash(olderThan days: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let stale = tokens.filter { ($0.deletedAt ?? .distantFuture) < cutoff }
        guard !stale.isEmpty else { return }
        tokens.removeAll { token in stale.contains { $0.id == token.id } }
        save()
    }

    @discardableResult
    func createGroup(named name: String) -> VaultGroup {
        let group = VaultGroup(name: name, icon: "folder", sortOrder: groups.count)
        groups.append(group)
        save()
        return group
    }

    func deleteGroup(_ group: VaultGroup) {
        tokens.forEach { if $0.groupID == group.id { $0.groupID = nil } }
        groups.removeAll { $0.id == group.id }
        save()
    }

    // MARK: - iCloud sync

    var syncGroups: [SyncGroup] {
        groups.map { SyncGroup(id: $0.id, name: $0.name, icon: $0.icon, sortOrder: $0.sortOrder) }
    }

    /// One full round trip against iCloud Drive: pull what other devices wrote, merge it in, push
    /// whatever this iPhone knows that iCloud does not. Called on the main thread by AppState.
    func synchronizeWithICloud() {
        guard let outcome = ICloudSyncService.shared.synchronize(tokens: tokens, groups: syncGroups)
        else { return }
        if outcome.tokens.map(\.id) != tokens.map(\.id) {
            tokens = outcome.tokens
        }
        groups = outcome.groups.map {
            VaultGroup(id: $0.id, name: $0.name, icon: $0.icon, sortOrder: $0.sortOrder)
        }
        if outcome.applied > 0 || outcome.written {
            save()
            objectWillChange.send()
        }
    }

    // MARK: - Import / export

    struct ImportReport {
        var added = 0
        var updated = 0
        var skippedUnreadable = 0
        var failure: String?

        var summary: String {
            if let failure { return failure }
            var parts: [String] = []
            if added > 0 { parts.append(L("新增 %lld", added)) }
            if updated > 0 { parts.append(L("更新 %lld", updated)) }
            if skippedUnreadable > 0 { parts.append(L("略過 %lld（其他裝置加密）", skippedUnreadable)) }
            return parts.isEmpty ? L("沒有可匯入的項目") : L("匯入完成：") + parts.joined(separator: " · ")
        }
    }

    /// Import a file chosen in the document picker (.json / .env / .csv / .txt).
    @discardableResult
    func importFile(at url: URL) -> ImportReport {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            return ImportReport(failure: "無法讀取檔案")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return ImportReport(failure: "檔案不是 UTF-8 文字")
        }
        return importText(text, filename: url.lastPathComponent)
    }

    @discardableResult
    func importText(_ text: String, filename: String) -> ImportReport {
        let ext = (filename as NSString).pathExtension.lowercased()
        var report = ImportReport()

        if ext == "json" || text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            guard let data = text.data(using: .utf8),
                  let snapshot = try? decoder.decode(Snapshot.self, from: data) else {
                return ImportReport(failure: "JSON 備份格式無法辨識")
            }

            for incoming in snapshot.tokens {
                guard (try? EncryptionService.decrypt(incoming.encryptedValue)) != nil else {
                    // Encrypted with another device's key. Importing the row without its secret
                    // would be a lie, so it is counted and skipped instead.
                    report.skippedUnreadable += 1
                    continue
                }
                merge(incoming, into: &report)
            }
            for group in snapshot.groups where !groups.contains(where: { $0.id == group.id }) {
                groups.append(VaultGroup(id: group.id, name: group.name, icon: group.icon,
                                         sortOrder: group.sortOrder))
            }
        } else if ext == "csv" {
            // CSV exported by either build: 名稱,值,備註,環境,類型,到期日
            let rows = ImportExportHelper.parseCSV(text)
            for row in rows {
                let token = TokenItem(name: row.name, plainValue: row.value, note: row.note,
                                      environment: row.env)
                merge(token, into: &report)
            }
        } else {
            // .env and plain text: KEY=VALUE per line.
            let pairs = BackupEnvParser.parse(text)
            guard !pairs.isEmpty else { return ImportReport(failure: "找不到 KEY=VALUE 形式的密鑰") }
            for pair in pairs {
                let token = TokenItem(name: pair.name, plainValue: pair.value, note: pair.note)
                merge(token, into: &report)
            }
        }

        if report.added > 0 || report.updated > 0 {
            SecurityLogService.shared.log(.imported, tokenID: UUID(),
                                          name: filename, provider: "檔案")
            save()
            objectWillChange.send()
            ICloudSyncService.shared.requestSync()
        }
        return report
    }

    private func merge(_ incoming: TokenItem, into report: inout ImportReport) {
        if let index = tokens.firstIndex(where: { $0.id == incoming.id }) {
            tokens[index] = incoming
            report.updated += 1
        } else if let index = tokens.firstIndex(where: {
            $0.name == incoming.name && $0.environment == incoming.environment
        }) {
            tokens[index] = incoming
            report.updated += 1
        } else {
            tokens.append(incoming)
            report.added += 1
        }
    }

    enum ExportFormat: String, CaseIterable, Identifiable {
        case encryptedJSON, env, csv
        var id: String { rawValue }
        var label: String {
            switch self {
            case .encryptedJSON: return "加密 JSON"
            case .env: return ".env"
            case .csv: return "CSV"
            }
        }
        var filename: String {
            switch self {
            case .encryptedJSON: return "TokenVault-備份.json"
            case .env: return "tokens.env"
            case .csv: return "tokens.csv"
            }
        }
        var isPlaintext: Bool { self != .encryptedJSON }
    }

    func exportData(_ format: ExportFormat) -> Data {
        let live = activeTokens
        switch format {
        case .encryptedJSON:
            let macGroups = groups.map { group in
                MacGroup(id: group.id, name: group.name, icon: group.icon, sortOrder: group.sortOrder,
                         tokens: tokens.filter { $0.groupID == group.id })
            }
            let snapshot = Snapshot(groups: macGroups, tokens: tokens)
            return (try? encoder.encode(snapshot)) ?? Data()
        case .env:
            return Data(ImportExportHelper.exportEnv(live).utf8)
        case .csv:
            return Data(ImportExportHelper.exportCSV(live).utf8)
        }
    }

    // MARK: - Demo data (UI tests and screenshots only)

    func seedDemoIfEmpty() {
        guard tokens.isEmpty else { return }

        let work = VaultGroup(name: L("工作"), icon: "briefcase.fill", sortOrder: 0)
        let personal = VaultGroup(name: L("個人"), icon: "person.fill", sortOrder: 1)
        groups = [work, personal]

        let samples: [(String, String, TokenProvider, TokenCategory, TokenKind, TokenEnvironment, String, [String], UUID?)] = [
            (L("OpenAI 專案金鑰"), "sk-proj-8fJ2kLmQ7vRtY3nPqXwZaB4cDeGhI1jK", .openai, .ai, .apiKey, .production, "計費帳號 · 團隊共用", ["llm", "prod"], work.id),
            (L("GitHub 個人存取權杖"), "ghp_9dK2mPq7RtY4nXwZbA1cEfGhIjKlMnOpQrSt", .github, .other, .oauth, .development, "repo + workflow scope", ["ci"], work.id),
            ("Cloudflare API Token", "cf_3xY7bN2mLpQ9vRtK4wZaB6cDeH1jF8gI5kSn", .cloudflare, .cloud, .apiKey, .production, "Zone.DNS 編輯權限", ["dns"], work.id),
            (L("Stripe 測試密鑰"), "sk_test_51QmZkLpQ7vRtY3nPqXwZaB4cDeGhI1jK", .stripe, .payment, .apiKey, .staging, "訂閱流程測試", ["pay"], personal.id),
            ("Claude API", "sk-ant-api03-Kq7RtY3nPqXwZaB4cDeGhI1jKlMnOpQrStUvWx", .claude, .ai, .apiKey, .production, "長文本摘要服務", ["llm"], personal.id),
            (L("伺服器 SSH 私鑰"), "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA\n-----END OPENSSH PRIVATE KEY-----", .custom, .ssh, .sshKey, .production, "srv.wahsun.org · port 28898", ["infra"], personal.id),
            (L("Tailscale 驗證金鑰"), "tskey-auth-kQ7RtY3nPqXwZaB4cDeGhI1jK", .tailscale, .server, .apiKey, .development, "可重複使用 · 90 天", ["vpn"], work.id),
            (L("JWT 範例（除錯用）"), "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ3YWhzdW4iLCJyb2xlIjoiZGV2IiwiaWF0IjoxNzYwMDAwMDAwLCJleHAiOjE3OTAwMDAwMDB9.c2lnbmF0dXJlLXBsYWNlaG9sZGVy", .custom, .jwt, .jwt, .development, "可在工具頁解碼", ["debug"], nil)
        ]

        for sample in samples {
            let token = TokenItem(name: sample.0, plainValue: sample.1, note: sample.6,
                                  environment: sample.5, provider: sample.2, category: sample.3,
                                  kind: sample.4, tags: sample.7, groupID: sample.8)
            token.isFavorite = sample.0.hasPrefix("OpenAI") || sample.0.hasPrefix("GitHub")
            tokens.append(token)
        }
        tokens[2].expiresAt = Calendar.current.date(byAdding: .day, value: 4, to: Date())
        tokens[4].lastUsedAt = Date().addingTimeInterval(-3600)
        tokens[1].lastUsedAt = Date().addingTimeInterval(-7200)
        save()
    }
}

/// `.env` reader used by the import path — comments, quotes, and `export` prefixes are all
/// things people's real dotfiles contain.
enum BackupEnvParser {
    struct Pair { let name: String; let value: String; let note: String }

    static func parse(_ content: String) -> [Pair] {
        content.components(separatedBy: .newlines).compactMap { rawLine in
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else {
                return nil
            }
            let name = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)

            // An inline comment is only a comment when it is not inside the value itself.
            if let hash = value.range(of: " #") {
                value = String(value[value.startIndex..<hash.lowerBound])
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !value.isEmpty else { return nil }
            return Pair(name: name, value: value, note: "從 .env 匯入")
        }
    }
}
