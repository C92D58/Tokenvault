import Foundation
import CryptoKit
import Security

/// Automatic encrypted backup into the app's iCloud Drive container.
///
/// Why a container and not a plain `~/Library/Mobile Documents` path: the App Store build is
/// sandboxed, so the only iCloud location it may touch is its own ubiquity container. That needs
/// the iCloud Documents capability (see the entitlements file); when it is missing or the user is
/// signed out, `status` says so instead of pretending to sync.
///
/// The backup key lives in the **iCloud keychain** (synchronizable item), so a replacement device
/// signed into the same Apple ID can restore without the user copying anything by hand.
final class ICloudBackupService: ObservableObject {
    static let shared = ICloudBackupService()

    enum Status: Equatable {
        case disabled
        case unavailable(String)
        case idle(Date?)
        case working
        case failed(String)

        var summary: String {
            switch self {
            case .disabled: return L("未啟用")
            case .unavailable(let why): return why
            case .idle(let date):
                guard let date else { return L("已啟用，等待第一次備份") }
                let f = DateFormatter()
                f.locale = LanguageStore.shared.locale
                f.setLocalizedDateFormatFromTemplate("MMMd HH:mm")
                return L("上次備份 %@", f.string(from: date))
            case .working: return L("備份中…")
            case .failed(let why): return L("失敗：%@", why)
            }
        }
    }

    static let containerIdentifier = "iCloud.dev.wahsun.tokenvault"
    private static let backupKeyTag = "dev.wahsun.tokenvault.backupkey"
    private let folderName = "Backups"
    private let keepCount = 7
    private let minimumInterval: TimeInterval = 60

    @Published private(set) var status: Status = .disabled
    @Published private(set) var lastBackup: Date?

    private var scheduled: DispatchWorkItem?
    private var lastWrite: Date?

    private init() {}

    // MARK: - Locations

    /// `…/Documents/TokenVault/Backups` inside the ubiquity container, or nil when iCloud is not
    /// available to this build (no entitlement, not signed in, or iCloud Drive disabled).
    var backupDirectory: URL? {
        // Test hook: `TV_BACKUP_DIR` points the service at a local folder (the sandbox container)
        // so the encrypt → write → decrypt round trip can be verified without an iCloud container.
        if let path = ProcessInfo.processInfo.environment["TV_BACKUP_DIR"] {
            let dir = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerIdentifier) else {
            return nil
        }
        let dir = root.appendingPathComponent("Documents/TokenVault/\(folderName)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }

    var isAvailable: Bool { backupDirectory != nil }

    func refreshStatus(enabled: Bool) {
        guard enabled else { status = .disabled; return }
        if backupDirectory == nil {
            status = .unavailable(L("已啟用，但目前無法備份：請在系統設定登入 iCloud，並確認此版本已開通 iCloud 容器"))
        } else {
            status = .idle(lastBackup ?? newestBackupDate())
        }
    }

    // MARK: - Backup

    struct Payload: Codable {
        var version: Int = 1
        var createdAt: Date
        var tokens: [TokenItem]
    }

    /// Writes one encrypted snapshot. Cheap enough to call on every change; throttled internally.
    func backup(tokens: [TokenItem], force: Bool = false) {
        guard let dir = backupDirectory else {
            status = .unavailable(L("已啟用，但目前無法備份：請在系統設定登入 iCloud，並確認此版本已開通 iCloud 容器"))
            return
        }
        if !force, let lastWrite, Date().timeIntervalSince(lastWrite) < minimumInterval { return }
        guard !tokens.isEmpty else { return }

        status = .working
        do {
            let payload = Payload(createdAt: Date(), tokens: tokens)
            let json = try JSONEncoder().encode(payload)
            let sealed = try AES.GCM.seal(json, using: try backupKey())
            guard let combined = sealed.combined else {
                throw BackupError.encryptionFailed
            }
            let stamp = Self.fileStamp.string(from: Date())
            let url = dir.appendingPathComponent("vault-\(stamp).tvbackup")
            try combined.write(to: url, options: [.atomic])
            lastWrite = Date()
            lastBackup = Date()
            status = .idle(lastBackup)
            prune(in: dir)
            print("[backup] wrote \(url.path) tokens=\(tokens.count) bytes=\(combined.count)")
        } catch {
            status = .failed(error.localizedDescription)
            print("[backup] failed: \(error.localizedDescription)")
        }
    }

    /// Coalesces bursts of edits (renames, tag changes) into one write.
    func scheduleBackup(tokens: @escaping () -> [TokenItem]) {
        scheduled?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.backup(tokens: tokens())
        }
        scheduled = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: work)
    }

    // MARK: - Restore

    struct Snapshot {
        let url: URL
        let createdAt: Date
        let tokens: [TokenItem]
    }

    func snapshots() -> [Snapshot] {
        guard let dir = backupDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter { $0.pathExtension == "tvbackup" }
            .compactMap { url -> Snapshot? in
                guard let data = try? Data(contentsOf: url),
                      let key = try? backupKey(),
                      let box = try? AES.GCM.SealedBox(combined: data),
                      let plain = try? AES.GCM.open(box, using: key),
                      let payload = try? JSONDecoder().decode(Payload.self, from: plain)
                else { return nil }
                return Snapshot(url: url, createdAt: payload.createdAt, tokens: payload.tokens)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func newestBackupDate() -> Date? { snapshots().first?.createdAt }

    // MARK: - Key (iCloud keychain)

    private func backupKey() throws -> SymmetricKey {
        // Test hook: an explicit key lets the crypto path be verified on an unsigned build, where
        // the keychain is unavailable (errSecMissingEntitlement -34018).
        if let hex = ProcessInfo.processInfo.environment["TV_BACKUP_KEY"], let data = Self.hexKey(hex) {
            return SymmetricKey(data: data)
        }
        if let existing = readKey() { return existing }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.backupKeyTag,
            kSecAttrAccount as String: "vault-backup",
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecValueData as String: raw,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrLabel as String: "TokenVault iCloud backup key",
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw BackupError.keychain(status)
        }
        return readKey() ?? key
    }

    private func readKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.backupKeyTag,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    // MARK: - Housekeeping

    private func prune(in dir: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        let backups = files.filter { $0.pathExtension == "tvbackup" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(keepCount) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    /// 64 hex characters → 32 bytes.
    private static func hexKey(_ hex: String) -> Data? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count == 64 else { return nil }
        var data = Data(capacity: 32)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    private static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    enum BackupError: LocalizedError {
        case encryptionFailed
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .encryptionFailed: return L("備份加密失敗")
            case .keychain(let status):
                return "鑰匙圈寫入失敗（\(status)）"
            }
        }
    }
}
