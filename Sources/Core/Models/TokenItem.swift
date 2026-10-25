import Foundation
import SwiftUI
import CryptoKit

// MARK: - Token Environment

enum TokenEnvironment: String, Codable, CaseIterable {
    case development = "開發"
    case staging = "預發"
    case production = "正式"

    /// 品牌色 — 環境 pill 的文字與強調色（明暗模式皆可讀）。
    var brandColor: Color {
        switch self {
        case .development: return Color(red: 0.23, green: 0.51, blue: 0.96)   // #3B82F6
        case .staging: return Color(red: 0.96, green: 0.62, blue: 0.04)       // #F59E0B
        case .production: return Color(red: 0.94, green: 0.27, blue: 0.27)     // #EF4444
        }
    }
    /// Localized label. `rawValue` is both the lookup key and the persisted value, so the
    /// Chinese source string doubles as the key for `Localizable.strings`.
    var displayName: String { String(localized: String.LocalizationValue(rawValue)) }
    var icon: String {
        switch self {
        case .development: return "hammer.fill"
        case .staging: return "testtube.2"
        case .production: return "shield.checkered"
        }
    }
}

// MARK: - Group

final class TokenGroup: ObservableObject, Identifiable, Codable, Hashable {
    let id: UUID
    @Published var name: String
    @Published var icon: String
    @Published var sortOrder: Int
    @Published var tokens: [TokenItem]

    enum CodingKeys: String, CodingKey { case id, name, icon, sortOrder, tokens }

    init(id: UUID = UUID(), name: String, icon: String = "folder", sortOrder: Int = 0, tokens: [TokenItem] = []) {
        self.id = id; self.name = name; self.icon = icon; self.sortOrder = sortOrder; self.tokens = tokens
    }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        icon = try c.decode(String.self, forKey: .icon); sortOrder = try c.decode(Int.self, forKey: .sortOrder)
        tokens = try c.decode([TokenItem].self, forKey: .tokens)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(icon, forKey: .icon); try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(tokens, forKey: .tokens)
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: TokenGroup, rhs: TokenGroup) -> Bool { lhs.id == rhs.id }
}

// MARK: - Token Item

final class TokenItem: ObservableObject, Identifiable, Codable, Equatable {
    let id: UUID
    @Published var name: String
    var encryptedValue: String
    @Published var note: String
    @Published var environment: TokenEnvironment
    @Published var provider: TokenProvider
    @Published var category: TokenCategory
    @Published var kind: TokenKind
    @Published var tags: [String]
    @Published var expiresAt: Date?
    @Published var createdAt: Date
    @Published var lastUsedAt: Date?
    @Published var deletedAt: Date?
    @Published var copyCount: Int
    @Published var isFavorite: Bool
    @Published var groupID: UUID?
    @Published var rotatedAt: Date?
    @Published var rotationDueAt: Date?
    @Published var customFields: [String: String]
    /// Last time this row changed **in a way worth syncing**. iCloud sync merges per token on this
    /// value, so every mutation funnel has to stamp it (`touch()`); decoding writes the sender's
    /// stamp verbatim, which is what makes the merge order the same on every device.
    ///
    /// Deliberately **not** `@Published`: nothing renders it, and publishing it makes
    /// `touch()` re-enter the objectWillChange subscription that called it (infinite recursion —
    /// it crashed the app with a stack overflow).
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, encryptedValue, note, environment
        case provider, category, kind, tags, expiresAt, createdAt
        case lastUsedAt, deletedAt, copyCount, isFavorite, groupID
        case rotatedAt, rotationDueAt, customFields, updatedAt
        // 舊版欄位，僅供讀取遷移
        case tokenType, secretType
    }

    init(name: String, plainValue: String, note: String = "",
         environment: TokenEnvironment = .production, provider: TokenProvider? = nil,
         category: TokenCategory? = nil, kind: TokenKind = .apiKey, tags: [String] = [],
         expiresAt: Date? = nil, groupID: UUID? = nil,
         customFields: [String: String] = [:], id: UUID = UUID()) {
        let detectedProvider = provider ?? TokenProvider.detect(from: name, value: plainValue)
        let now = Date()
        self.id = id; self.name = name; self.note = note
        self.environment = environment; self.expiresAt = expiresAt; self.createdAt = now
        self.lastUsedAt = nil; self.deletedAt = nil
        self.copyCount = 0; self.isFavorite = false; self.groupID = groupID
        self.kind = kind
        self.tags = tags
        self.customFields = customFields
        self.rotatedAt = nil; self.rotationDueAt = nil
        self.updatedAt = now
        self.provider = detectedProvider
        self.category = category ?? detectedProvider.category
        self.encryptedValue = (try? EncryptionService.encrypt(plainValue)) ?? plainValue
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        encryptedValue = try c.decode(String.self, forKey: .encryptedValue)
        note = try c.decode(String.self, forKey: .note)
        environment = (try? c.decode(TokenEnvironment.self, forKey: .environment)) ?? .production
        provider = (try? c.decode(TokenProvider.self, forKey: .provider))
            ?? TokenProvider.fromLegacyTokenType((try? c.decode(String.self, forKey: .tokenType)) ?? "")
        category = (try? c.decode(TokenCategory.self, forKey: .category)) ?? .other
        kind = (try? c.decode(TokenKind.self, forKey: .kind))
            ?? (try? c.decode(TokenKind.self, forKey: .secretType))
            ?? .apiKey
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        let created = try c.decode(Date.self, forKey: .createdAt)
        createdAt = created
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        copyCount = try c.decode(Int.self, forKey: .copyCount)
        isFavorite = try c.decode(Bool.self, forKey: .isFavorite)
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
        rotatedAt = try c.decodeIfPresent(Date.self, forKey: .rotatedAt)
        rotationDueAt = try c.decodeIfPresent(Date.self, forKey: .rotationDueAt)
        customFields = (try? c.decode([String: String].self, forKey: .customFields)) ?? [:]
        // Vault files written before sync existed have no stamp; createdAt is the honest fallback
        // and keeps the row from looking "newer" than everything else on the first merge.
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? created
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(encryptedValue, forKey: .encryptedValue); try c.encode(note, forKey: .note)
        try c.encode(environment, forKey: .environment); try c.encode(provider, forKey: .provider)
        try c.encode(category, forKey: .category); try c.encode(kind, forKey: .kind)
        try c.encode(tags, forKey: .tags)
        try c.encodeIfPresent(expiresAt, forKey: .expiresAt); try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt); try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try c.encode(copyCount, forKey: .copyCount); try c.encode(isFavorite, forKey: .isFavorite)
        try c.encodeIfPresent(groupID, forKey: .groupID)
        try c.encodeIfPresent(rotatedAt, forKey: .rotatedAt); try c.encodeIfPresent(rotationDueAt, forKey: .rotationDueAt)
        try c.encode(customFields, forKey: .customFields)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    /// Stamp a change so iCloud sync can order this row against the same row on other devices.
    func touch() { updatedAt = Date() }

    static func == (lhs: TokenItem, rhs: TokenItem) -> Bool { lhs.id == rhs.id }

    func decryptedValue() -> String { (try? EncryptionService.decrypt(encryptedValue)) ?? encryptedValue }
    var maskedValue: String {
        let v = encryptedValue
        guard v.count > 8 else { return String(repeating: "•", count: 8) }
        return "\(v.prefix(4))\(String(repeating: "•", count: 8))\(v.suffix(4))"
    }
    var isDeleted: Bool { deletedAt != nil }
    var isExpired: Bool { expiresAt.map { $0 < Date() } ?? false }
    var expiresSoon: Bool {
        guard let e = expiresAt else { return false }
        return e < Calendar.current.date(byAdding: .day, value: 7, to: Date())! && !isExpired
    }
    var needsRotation: Bool {
        guard let due = rotationDueAt else { return false }
        return due < Date()
    }

    /// Duplicate detection: check if plain value matches another token
    func hasDuplicate(in tokens: [TokenItem]) -> Bool {
        let myVal = decryptedValue()
        return tokens.contains { $0.id != self.id && $0.decryptedValue() == myVal }
    }
}
