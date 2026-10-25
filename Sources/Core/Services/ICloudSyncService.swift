import Foundation
import CryptoKit
import Security

// MARK: - Wire types
//
// What crosses the wire between devices. Both the iOS and the macOS app compile this file, so
// these types cannot mention either platform's view models.

/// A folder as it travels between devices (`VaultGroup` on iOS, `TokenGroup` on macOS).
struct SyncGroup: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var icon: String
    var sortOrder: Int
}

/// One token as it travels between devices.
///
/// `value` is the **plaintext** secret. That is deliberate: each device's master key is
/// non-exportable and device-bound, so a value encrypted on the Mac can never be decrypted on the
/// iPhone. The whole payload is sealed with a shared key that lives in the **iCloud keychain**, and
/// every receiving device re-encrypts each value with its own key before it stores it.
struct SyncRecord: Codable, Equatable {
    var id: UUID
    var name: String
    var value: String
    var note: String
    var environment: String
    var provider: String
    var category: String
    var kind: String
    var tags: [String]
    var expiresAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var deletedAt: Date?
    var copyCount: Int
    var isFavorite: Bool
    var groupID: UUID?
    var rotatedAt: Date?
    var rotationDueAt: Date?
    var customFields: [String: String]

    init(token: TokenItem) {
        id = token.id
        name = token.name
        value = token.decryptedValue()
        note = token.note
        environment = token.environment.rawValue
        provider = token.provider.rawValue
        category = token.category.rawValue
        kind = token.kind.rawValue
        tags = token.tags
        expiresAt = token.expiresAt
        createdAt = token.createdAt
        updatedAt = token.updatedAt
        lastUsedAt = token.lastUsedAt
        deletedAt = token.deletedAt
        copyCount = token.copyCount
        isFavorite = token.isFavorite
        groupID = token.groupID
        rotatedAt = token.rotatedAt
        rotationDueAt = token.rotationDueAt
        customFields = token.customFields
    }

    /// Copy the record onto a token that already exists here, re-encrypting the value locally.
    /// `updatedAt` is written verbatim — it is the ordering key for merges, not a local edit stamp.
    func apply(to token: TokenItem) {
        token.name = name
        token.note = note
        token.environment = TokenEnvironment(rawValue: environment) ?? .production
        token.provider = TokenProvider(rawValue: provider) ?? .custom
        token.category = TokenCategory(rawValue: category) ?? .other
        token.kind = TokenKind(rawValue: kind) ?? .apiKey
        token.tags = tags
        token.expiresAt = expiresAt
        token.createdAt = createdAt
        token.lastUsedAt = lastUsedAt
        token.deletedAt = deletedAt
        token.copyCount = copyCount
        token.isFavorite = isFavorite
        token.groupID = groupID
        token.rotatedAt = rotatedAt
        token.rotationDueAt = rotationDueAt
        token.customFields = customFields
        token.encryptedValue = (try? EncryptionService.encrypt(value)) ?? value
        token.updatedAt = updatedAt
    }
}

// MARK: - Service

/// Automatic, bidirectional sync of the whole vault through **iCloud Drive**.
///
/// The vault lives at `iCloud Drive/TokenVault/vault.tvsync` inside the app's ubiquity container,
/// sealed with AES-256-GCM under a key stored in the iCloud keychain. Every device that signs into
/// the same Apple ID shares that key, opens the same file, merges it with its own vault by token id
/// and `updatedAt`, and writes the union back. iCloud delivers the change to the other devices,
/// which pull it the moment they are active.
///
/// Why this shape, and not "sync the local vault file":
///   • the sandbox may only touch its own ubiquity container — that IS the app's iCloud Drive folder;
///   • token values are device-bound, so they must be re-encrypted at each end (see `SyncRecord`);
///   • iCloud Drive exposes conflicting versions instead of resolving them, so every read merges
///     `NSFileVersion.unresolvedConflictVersions` and every write resolves them.
final class ICloudSyncService: ObservableObject {
    static let shared = ICloudSyncService()

    static let containerIdentifier = "iCloud.dev.wahsun.tokenvault"
    static let noContainerMessage =
        L("此版本無法使用 iCloud：請在系統設定登入 iCloud 並開啟 iCloud Drive，且此 App 已開通 iCloud 容器")

    enum State: Equatable {
        case off
        case unavailable(String)
        case syncing
        case synced(Date)
        case failed(String)

        var summary: String {
            switch self {
            case .off: return L("未啟用")
            case .unavailable(let why): return why
            case .syncing: return L("同步中…")
            case .synced(let date):
                let f = DateFormatter()
                f.dateFormat = "M月d日 HH:mm"
                return L("上次同步 %@", f.string(from: date))
            case .failed(let why): return L("同步失敗：%@", why)
            }
        }

        var symbol: String {
            switch self {
            case .off: return "icloud.slash"
            case .unavailable: return "exclamationmark.icloud"
            case .syncing: return "arrow.triangle.2.circlepath.icloud"
            case .synced: return "checkmark.icloud"
            case .failed: return "xmark.icloud"
            }
        }
    }

    struct Outcome {
        /// The vault after the merge. Existing tokens are updated in place; new remote tokens are
        /// appended, so the caller can simply adopt this array.
        var tokens: [TokenItem]
        /// Groups after the merge.
        var groups: [SyncGroup]
        /// How many remote records changed the local vault.
        var applied: Int
        /// Whether the merged snapshot was written back to iCloud.
        var written: Bool
    }

    // MARK: Published state

    @Published private(set) var state: State = .off
    @Published private(set) var lastSyncedAt: Date?

    /// What the settings row shows. `state` is neutral before activation, so an enabled switch with
    /// "未啟用" underneath (the shape a reviewer calls a fake toggle) has to be impossible.
    var statusText: String {
        if isEnabled, case .off = state { return L("準備同步…") }
        return state.summary
    }

    /// Set by the app from its settings. Gates every automatic trigger.
    var isEnabled = false
    /// Set by the app: one full round trip against this device's vault. Called on the main thread.
    var performSync: (() -> Void)?

    // MARK: Internals

    private static let keyService = "dev.wahsun.tokenvault.synckey"
    private static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    private let fileName = "vault.tvsync"
    private static let folderName = "TokenVault"
    private var ledgerKey = "tv.sync.knownIDs"
    private let deviceKey = "tv.sync.deviceID"
    private let tombstoneLifetime: TimeInterval = 90 * 24 * 3600

    private var resolvedDirectory: URL?
    private var didResolve = false
    /// A folder the user picked (iCloud Drive › TokenVault). When set, the payload lives there
    /// instead of the app's ubiquity container — the same folder Finder and the Files app show.
    private var scopedFolder: URL?
    private var folderWatcher: DispatchSourceFileSystemObject?
    private let customFolderKey = "tv.sync.folder"
    private let customFolderPathKey = "tv.sync.folderPath"
    private var isTesting = false
    private var isSyncing = false
    private var pendingAfterCurrent = false
    private var suppressRemoteUntil: Date = .distantPast
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?
    /// Size + modification date of the sync file as last read or written; used to ignore metadata
    /// notifications that do not correspond to a new payload.
    private var lastSeen: (size: Int, date: Date)?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        // Millisecond precision, not ISO-8601 seconds: merges are ordered by these stamps, and two
        // edits made in the same second (very normal when typing) must still be distinguishable.
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    // MARK: - Locations

    var directory: URL? { resolvedDirectory }

    var fileURL: URL? { resolvedDirectory?.appendingPathComponent(fileName) }

    var isAvailable: Bool { resolvedDirectory != nil }

    /// Resolve the ubiquity container off the main thread (the first call can be slow), then start
    /// watching for remote changes and run one sync.
    func activate() {
        guard isEnabled else { state = .off; return }
        guard didResolve else {
            didResolve = true
            let service = self
            DispatchQueue.global(qos: .userInitiated).async {
                let dir = service.resolveDirectory()
                DispatchQueue.main.async {
                    self.resolvedDirectory = dir
                    guard let dir else {
                        self.state = .unavailable(Self.noContainerMessage)
                        return
                    }
                    print("[sync] container \(dir.path)")
                    self.startWatching()
                    self.requestSync(after: 0.5)
                }
            }
            return
        }

        guard resolvedDirectory != nil else {
            state = .unavailable(Self.noContainerMessage)
            return
        }
        startWatching()
        requestSync(after: 0.2)
    }

    func deactivate() {
        isEnabled = false
        pending?.cancel()
        stopWatching()
        state = .off
    }

    private func stopWatching() {
        query?.stop()
        if let query { NotificationCenter.default.removeObserver(query) }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        query = nil
        folderWatcher?.cancel()
        folderWatcher = nil
    }

    // MARK: - User-chosen folder

    /// True when the payload sits in a folder the user picked instead of the app container.
    var isUsingCustomFolder: Bool { UserDefaults.standard.data(forKey: customFolderKey) != nil }

    var customFolderDisplayPath: String? { UserDefaults.standard.string(forKey: customFolderPathKey) }

    /// Persist a security-scoped bookmark for `url` and switch to it. The caller must have been given
    /// the URL by a picker (NSOpenPanel / UIDocumentPicker); that grant is the only way a sandboxed
    /// app may write into iCloud Drive itself rather than its own container.
    func setCustomFolder(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let data = try url.bookmarkData(options: [.withSecurityScope],
                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        let data = try url.bookmarkData(options: [],
                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
        UserDefaults.standard.set(data, forKey: customFolderKey)
        UserDefaults.standard.set(url.path, forKey: customFolderPathKey)
        print("[sync] folder set to \(url.path)")
        reloadLocation()
    }

    func clearCustomFolder() {
        UserDefaults.standard.removeObject(forKey: customFolderKey)
        UserDefaults.standard.removeObject(forKey: customFolderPathKey)
        print("[sync] folder cleared, back to the app container")
        reloadLocation()
    }

    /// Drop the resolved directory and the watchers, then resolve again. Used after the location
    /// changes; the payload is re-read from the new place and merged, exactly like a cold launch.
    func reloadLocation() {
        stopWatching()
        if let scopedFolder { scopedFolder.stopAccessingSecurityScopedResource() }
        scopedFolder = nil
        resolvedDirectory = nil
        didResolve = false
        lastSeen = nil
        state = .off
        activate()
    }

    private func resolveCustomFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: customFolderKey) else { return nil }
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        #else
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
        #endif
        guard let url = try? URL(resolvingBookmarkData: data, options: options,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else {
            print("[sync] the chosen folder bookmark no longer resolves")
            return nil
        }
        // Returns false for URLs that are not security-scoped (e.g. the app's own container).
        _ = url.startAccessingSecurityScopedResource()
        scopedFolder = url
        return url
    }

    /// `Documents/TokenVault` inside the ubiquity container, or nil when iCloud is not usable.
    private func resolveDirectory() -> URL? {
        // Test hook: a plain folder stands in for the container so the whole round trip can run
        // without iCloud (the self-test does exactly this).
        if let path = ProcessInfo.processInfo.environment["TV_SYNC_DIR"] {
            let dir = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        // A user-picked folder wins: it is an ordinary iCloud Drive folder, visible everywhere.
        if let folder = resolveCustomFolder() {
            let dir = folder.appendingPathComponent(Self.folderName, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                return dir
            } catch {
                print("[sync] cannot use the chosen folder: \(error.localizedDescription)")
            }
        }
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerIdentifier) else {
            return nil
        }
        let dir = root.appendingPathComponent("Documents/\(Self.folderName)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }

    /// Self-test hook: skip iCloud and use `dir` as the shared folder.
    func useLocalDirectoryForTesting(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        resolvedDirectory = dir
        didResolve = true
        isTesting = true
    }

    /// Self-test hook: each simulated device keeps its own change ledger, exactly as two real
    /// devices keep their own `UserDefaults`.
    func useLedgerKeyForTesting(_ key: String) {
        ledgerKey = key
    }

    // MARK: - Triggers

    /// Coalesces bursts of edits (renames, tag changes, copies) into one round trip.
    func requestSync(after delay: TimeInterval = 3) {
        guard isEnabled else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isEnabled else { return }
            self.performSync?()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Foreground / user pressed the button: run now, no debounce.
    func requestSyncNow() {
        guard isEnabled else { return }
        pending?.cancel()
        performSync?()
    }

    private func startWatching() {
        guard query == nil, folderWatcher == nil else { return }
        // A plain folder (self-test) never delivers change notifications; only a real location does.
        guard !isTesting, ProcessInfo.processInfo.environment["TV_SYNC_DIR"] == nil else { return }
        guard let dir = resolvedDirectory else { return }

        if isUsingCustomFolder {
            // A picked folder has no NSMetadataQuery; vnode events on the directory fire when iCloud
            // (or the other device) replaces the payload.
            let fd = Darwin.open(dir.path, O_EVTONLY)  // `open` is shadowed by the decode helper above
            guard fd >= 0 else { return }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .extend],
                queue: .main
            )
            source.setEventHandler { [weak self] in self?.remoteChanged() }
            source.setCancelHandler { close(fd) }
            source.resume()
            folderWatcher = source
            return
        }

        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, fileName)
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: q, queue: .main
        ) { [weak self] _ in
            self?.remoteChanged()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main
        ) { [weak self] _ in
            self?.remoteChanged()
        })
        q.start()
        query = q
    }

    private func remoteChanged() {
        guard isEnabled, Date() >= suppressRemoteUntil else { return }
        // The query fires for every change in the scope (including our own backup snapshots), so
        // check the file itself: same size and modification date means nothing to pull.
        guard let url = fileURL,
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        else { return }
        let stamp = (values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        if let last = lastSeen, last == stamp { return }
        lastSeen = stamp
        print("[sync] iCloud reported a change")
        requestSync(after: 0.4)
    }

    // MARK: - Round trip

    /// Read iCloud, merge with `localTokens`/`localGroups`, apply what came from elsewhere, and
    /// write the union back when this device knows something iCloud does not.
    ///
    /// Returns nil when the round trip could not run (no container, unreadable file, re-entrant
    /// call). The local vault is never modified in that case — in particular an undecryptable file
    /// is never overwritten, because that would destroy another device's vault.
    func synchronize(tokens localTokens: [TokenItem], groups localGroups: [SyncGroup]) -> Outcome? {
        guard let url = fileURL else {
            // The container is resolved asynchronously at activation; a call before that is not an
            // error, it just has nothing to do yet.
            if didResolve { state = .unavailable(Self.noContainerMessage) }
            return nil
        }
        guard !isSyncing else {
            // An edit landed while a round trip was running; run once more when it finishes.
            pendingAfterCurrent = true
            return nil
        }
        isSyncing = true
        defer {
            isSyncing = false
            if pendingAfterCurrent {
                pendingAfterCurrent = false
                requestSync(after: 0.5)
            }
        }
        state = .syncing

        // A value this device cannot decrypt (master key replaced, or a row imported from another
        // device before sync existed) must not enter the payload: `decryptedValue()` would hand back
        // the ciphertext and overwrite the other devices' plaintext with garbage. Leave those rows
        // alone locally and let iCloud's copy win the merge.
        var localRecords: [SyncRecord] = []
        var unreadable = 0
        for token in localTokens {
            if (try? EncryptionService.decrypt(token.encryptedValue)) != nil {
                localRecords.append(SyncRecord(token: token))
            } else {
                unreadable += 1
            }
        }
        if unreadable > 0 { print("[sync] \(unreadable) token(s) unreadable with this device key — left as is") }

        var local = Snapshot(records: localRecords, groups: localGroups)
        // Vanished = in the ledger but gone locally. Use every local id (including rows that could
        // not be decrypted) so an unreadable row is never mistaken for a deletion.
        local.tombstones = tombstonesForVanishedTokens(localIDs: Set(localTokens.map(\.id)))

        let remote: Snapshot?
        do {
            remote = try readSnapshot(at: url)
        } catch {
            // Never write over a file this device cannot read: it may be the other device's vault,
            // sealed with a key this device has not received yet (iCloud Keychain off).
            state = .unavailable(Self.explain(error))
            print("[sync] read failed: \(error.localizedDescription)")
            return nil
        }

        let merged = remote.map { merge(base: $0, local: local) } ?? local

        // Apply the merged view to the live vault.
        var byID: [UUID: TokenItem] = [:]
        for token in localTokens { byID[token.id] = token }
        var tokens = localTokens
        var applied = 0
        for record in merged.records {
            if let token = byID[record.id] {
                // Compare content, not just the stamp: the merge already decided which side wins,
                // and re-applying an identical row would only re-encrypt it and fire a redraw.
                if SyncRecord(token: token) != record {
                    record.apply(to: token)
                    applied += 1
                }
            } else {
                let token = Self.makeToken(record)
                tokens.append(token)
                byID[record.id] = token
                applied += 1
            }
        }
        // A row another device deleted for good has to disappear here too — otherwise the tombstone
        // only stops new copies while the local one lingers forever.
        let removed = tokens.filter { token in
            guard let dead = merged.tombstones[token.id.uuidString] else { return false }
            return dead >= token.updatedAt
        }
        if !removed.isEmpty {
            let ids = Set(removed.map(\.id))
            tokens.removeAll { ids.contains($0.id) }
            applied += removed.count
        }

        // Write only when the merged snapshot actually differs from what is in iCloud. Without this
        // test every pull would trigger a write, whose change notification triggers another pull.
        let changed = remote.map { Self.fingerprint($0) != Self.fingerprint(merged) } ?? true
        if changed {
            var payload = merged
            payload.revision = (remote?.revision ?? 0) + 1
            payload.writtenAt = Date()
            payload.writer = Self.deviceID(defaults: .standard, key: deviceKey)
            do {
                try writeSnapshot(payload, to: url)
            } catch {
                state = .failed(Self.explain(error))
                print("[sync] write failed: \(error.localizedDescription)")
                // The local merge is still valid; report it so the caller can keep it.
                return Outcome(tokens: tokens, groups: merged.groups, applied: applied, written: false)
            }
        }

        let syncedAt = Date()
        rememberKnownIDs(merged.records.map(\.id))
        lastSyncedAt = syncedAt
        state = .synced(syncedAt)
        print("[sync] applied=\(applied) wrote=\(changed) tokens=\(merged.records.count) revision=\(merged.revision)")

        return Outcome(tokens: tokens, groups: merged.groups, applied: applied, written: changed)
    }

    // MARK: - Payload

    struct Snapshot: Codable {
        var version: Int = 1
        var revision: Int = 0
        var writtenAt: Date = Date()
        var writer: String = ""
        var records: [SyncRecord] = []
        var groups: [SyncGroup] = []
        /// id → the moment it was permanently deleted. Keeps a delete from resurrecting; an edit
        /// newer than the tombstone wins and revives the token.
        var tombstones: [String: Date] = [:]
    }

    /// Per-token newest-wins; tombstones beat records that predate them; groups union by id.
    private func merge(base: Snapshot, local: Snapshot) -> Snapshot {
        var records: [UUID: SyncRecord] = [:]
        for record in base.records { records[record.id] = record }
        for record in local.records {
            if let existing = records[record.id] {
                if record.updatedAt > existing.updatedAt { records[record.id] = record }
            } else {
                records[record.id] = record
            }
        }

        var tombstones = base.tombstones
        for (id, date) in local.tombstones {
            tombstones[id] = max(tombstones[id] ?? .distantPast, date)
        }
        let cutoff = Date().addingTimeInterval(-tombstoneLifetime)
        tombstones = tombstones.filter { $0.value >= cutoff }

        var live: [SyncRecord] = []
        for record in records.values {
            if let dead = tombstones[record.id.uuidString], dead >= record.updatedAt {
                continue
            }
            live.append(record)
        }

        var groups: [UUID: SyncGroup] = [:]
        for group in base.groups { groups[group.id] = group }
        for group in local.groups where groups[group.id] == nil { groups[group.id] = group }

        var merged = base
        merged.records = live.sorted { $0.id.uuidString < $1.id.uuidString }
        merged.groups = groups.values.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        merged.tombstones = tombstones
        merged.revision = max(base.revision, local.revision)
        return merged
    }

    private static func makeToken(_ record: SyncRecord) -> TokenItem {
        let token = TokenItem(name: record.name, plainValue: record.value,
                              note: record.note,
                              environment: TokenEnvironment(rawValue: record.environment) ?? .production,
                              provider: TokenProvider(rawValue: record.provider) ?? .custom,
                              category: TokenCategory(rawValue: record.category) ?? .other,
                              kind: TokenKind(rawValue: record.kind) ?? .apiKey,
                              tags: record.tags, expiresAt: record.expiresAt,
                              groupID: record.groupID, customFields: record.customFields,
                              id: record.id)
        token.createdAt = record.createdAt
        token.updatedAt = record.updatedAt
        token.lastUsedAt = record.lastUsedAt
        token.deletedAt = record.deletedAt
        token.copyCount = record.copyCount
        token.isFavorite = record.isFavorite
        token.rotatedAt = record.rotatedAt
        token.rotationDueAt = record.rotationDueAt
        return token
    }

    private static func fingerprint(_ snapshot: Snapshot) -> Data {
        var head = snapshot
        head.revision = 0
        head.writtenAt = .distantPast
        head.writer = ""
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(head)) ?? Data()
    }

    // MARK: - File I/O

    private func readSnapshot(at url: URL) throws -> Snapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        // A file that exists only as an iCloud placeholder must be downloaded before it can be read.
        if let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
           let status = values.ubiquitousItemDownloadingStatus, status != .current {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        let data = try coordinatedRead(url)
        guard !data.isEmpty else { throw SyncError.truncated }
        var snapshot = try open(data)
        resolveConflicts(into: &snapshot, at: url)
        return snapshot
    }

    private func open(_ data: Data) throws -> Snapshot {
        // Never mint a key here: a file that already exists was written by another device with the
        // key from the iCloud keychain. Creating a second key would make this device unable to read
        // the vault and, worse, would let it write a payload nobody else can open. Wait for iCloud
        // to deliver the key; the status says so and the next round trip retries.
        guard let key = existingKey() else { throw SyncError.keyNotSynced }
        guard let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key) else {
            throw SyncError.unreadable
        }
        return try decoder.decode(Snapshot.self, from: plain)
    }

    private func writeSnapshot(_ snapshot: Snapshot, to url: URL) throws {
        let plain = try encoder.encode(snapshot)
        // Here a key may be created: this is the only write path, and a brand-new vault has no key
        // yet. An existing file always has one (see `open`).
        let key = try existingKey() ?? createKey()
        guard let sealed = try AES.GCM.seal(plain, using: key).combined else {
            throw SyncError.unreadable
        }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var thrown: Error?
        let options: NSFileCoordinator.WritingOptions =
            FileManager.default.fileExists(atPath: url.path) ? .forReplacing : []
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { target in
            do { try sealed.write(to: target, options: .atomic) } catch { thrown = error }
        }
        if let coordinationError { throw coordinationError }
        if let thrown { throw thrown }

        suppressRemoteUntil = Date().addingTimeInterval(3)
        // Our write IS the merge result: the older versions are already folded in.
        #if os(macOS)
        try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        #endif
    }

    private func coordinatedRead(_ url: URL) throws -> Data {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Data?
        var thrown: Error?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { source in
            do { result = try Data(contentsOf: source) } catch { thrown = error }
        }
        if let coordinationError { throw coordinationError }
        if let thrown { throw thrown }
        return result ?? Data()
    }

    /// iCloud Drive hands out conflicting versions rather than resolving them. Fold every version
    /// into this snapshot (same newest-wins merge, so nothing is lost) and mark them resolved —
    /// they are cleared for good once the merged file is written.
    private func resolveConflicts(into snapshot: inout Snapshot, at url: URL) {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !versions.isEmpty
        else { return }
        for version in versions {
            guard let data = try? Data(contentsOf: version.url), let other = try? open(data) else { continue }
            snapshot = merge(base: other, local: snapshot)
            version.isResolved = true
            print("[sync] merged conflict version \(version.url.lastPathComponent)")
        }
    }

    // MARK: - Key (iCloud keychain)

    /// Test hook: an explicit key lets the two-device self-test run without the keychain.
    static var keyOverride: Data?

    private func existingKey() -> SymmetricKey? {
        if let data = Self.keyOverride { return SymmetricKey(data: data) }
        if let hex = ProcessInfo.processInfo.environment["TV_SYNC_KEY"], let data = Self.hexKey(hex) {
            return SymmetricKey(data: data)
        }
        return readKey()
    }

    /// Only called when this device is writing a vault that does not exist yet.
    private func createKey() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keyService,
            kSecAttrAccount as String: "vault-sync",
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecValueData as String: raw,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrLabel as String: "TokenVault iCloud sync key",
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw SyncError.keychain(status)
        }
        print("[sync] created the shared sync key in the iCloud keychain")
        return readKey() ?? key
    }

    private func readKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keyService,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

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

    // MARK: - Change ledger
    //
    // A permanent delete removes the row entirely, so "absent locally" cannot be told apart from
    // "never seen here". The ledger remembers what this device has synchronised at least once;
    // anything in it that is now gone was deleted on purpose and becomes a tombstone.

    private func tombstonesForVanishedTokens(localIDs: Set<UUID>) -> [String: Date] {
        let known = Set((UserDefaults.standard.array(forKey: ledgerKey) as? [String] ?? []).compactMap(UUID.init(uuidString:)))
        let vanished = known.subtracting(localIDs)
        guard !vanished.isEmpty else { return [:] }
        let now = Date()
        var tombstones: [String: Date] = [:]
        for id in vanished { tombstones[id.uuidString] = now }
        print("[sync] \(vanished.count) token(s) deleted on this device")
        return tombstones
    }

    private func rememberKnownIDs(_ ids: [UUID]) {
        UserDefaults.standard.set(ids.map(\.uuidString).sorted(), forKey: ledgerKey)
    }

    private static func deviceID(defaults: UserDefaults, key: String) -> String {
        if let existing = defaults.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: key)
        return fresh
    }

    // MARK: - Errors

    enum SyncError: LocalizedError {
        case unreadable
        case truncated
        case keyNotSynced
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unreadable: return L("iCloud 上的資料無法用此裝置的金鑰解開")
            case .truncated: return L("iCloud 上的檔案尚未下載完成")
            case .keyNotSynced: return L("iCloud 鑰匙圈還沒把同步金鑰送到這台裝置")
            case .keychain(let status): return L("iCloud 鑰匙圈無法寫入同步金鑰（%@）", "\(status)")
            }
        }
    }

    private static func explain(_ error: Error) -> String {
        if let sync = error as? SyncError {
            switch sync {
            case .keychain:
                return L("需要開啟 iCloud 鑰匙圈：同步金鑰存在那裡，同一 Apple ID 的裝置才有辦法解密同一個檔案")
            case .keyNotSynced:
                return L("等待 iCloud 把同步金鑰送到這台裝置（請確認已開啟 iCloud 鑰匙圈），稍後會自動重試；在收到金鑰前不會覆寫雲端資料")
            case .unreadable:
                return L("iCloud 上的資料無法用此裝置的金鑰解開，已停止同步以免覆蓋（請確認已開啟 iCloud 鑰匙圈，稍後會自動重試）")
            case .truncated:
                return L("iCloud 檔案尚未下載完成，稍後會自動重試")
            }
        }
        return error.localizedDescription
    }
}
