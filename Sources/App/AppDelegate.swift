import SwiftUI
#if os(macOS)
import AppKit
import Carbon
#endif

/// AppDelegate shared across platforms.
/// - macOS: NSApplicationDelegate with menu bar, global hotkey, lock screen
/// - iOS: will use UIApplicationDelegate / SwiftUI App protocol
final class AppDelegate: NSObject, ObservableObject {
    let store = DataStore()
    let auth = AuthService()
    let settings = SettingsService.shared

#if os(macOS)
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var mainWindow: NSWindow?
    private var lockWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var helpWindow: NSWindow?
    private var lastUnlockTime = Date.distantPast
    private var idleTimer: Timer?
#endif
}

// MARK: - Shared Actions

extension AppDelegate {
    @objc func undoAction() { store.undoManager.undo() }
    @objc func redoAction() { store.undoManager.redo() }

    @objc func newToken() {
        showMainContent()
        NotificationCenter.default.post(name: .showAddToken, object: nil)
    }
    @objc func newGroup() {
        showMainContent()
        NotificationCenter.default.post(name: .showAddGroup, object: nil)
    }
    @objc func lockApp() {
        idleTimer?.invalidate(); idleTimer = nil; auth.lock(); showLockScreen()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
    func toggleFav(_ token: TokenItem) { store.toggleFav(token); store.save() }
    func deleteToken(_ token: TokenItem) { store.deleteToken(token) }
    func copyToken(_ token: TokenItem) {
        let value = token.decryptedValue()
        ClipboardService.shared.copy(value, clearAfter: TimeInterval(settings.clipboardClearSeconds))
        store.useToken(token)
        ToastService.shared.show("已複製「\(token.name)」", icon: "doc.on.clipboard")
#if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
#endif
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let showAddToken = Notification.Name("showAddToken")
    /// Opens Settings on the sync tab (iCloud backup lives there).
    static let showSettingsSyncTab = Notification.Name("showSettingsSyncTab")
    static let showAddGroup = Notification.Name("showAddGroup")
    static let showImportWizard = Notification.Name("showImportWizard")
}

// MARK: - macOS: NSApplicationDelegate

#if os(macOS)
extension AppDelegate: NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.applyAppearance()
        setupMenuBar()
        setupMainWindow()
        setupGlobalHotkey()
        buildMenu()

        // The settings toggle flips `isEnabled` at any time; the round trip always lands here.
        ICloudSyncService.shared.performSync = { [weak self] in self?.store.synchronizeWithICloud() }

        // Verification hooks: exercise the real paths and exit before any window work.
        if runBackupSelfTestIfRequested() { return }
        if runSyncSelfTestIfRequested() { return }
        if runSyncWriteProbeIfRequested() { return }
        if MainActor.assumeIsolated({ runRenderLockIfRequested() }) { return }
        if MainActor.assumeIsolated({ runSyncFolderSelfTestIfRequested() }) { return }

        if let dir = Self.storeShotDirectory {
            // Store screenshot run: same windows, real pixels, no prompts, no lock screen.
            settings.appearanceMode = .dark
            settings.applyAppearance()
            auth.isLocked = false
            seedStoreShotData()
            showMainContent()
            captureStoreShots(into: dir)
        } else {
            showLockScreen()
            // Notifications
            NotificationService.requestPermission()
            NotificationService.scheduleExpiryReminders(for: store.allTokens)

            // iCloud: refresh the reported state, then run one real round trip (pull + push).
            if settings.iCloudSyncEnabled {
                ICloudBackupService.shared.refreshStatus(enabled: true)
                ICloudSyncService.shared.isEnabled = true
                ICloudSyncService.shared.activate()
            }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        // Last chance to capture edits made in the final seconds before quit.
        guard settings.iCloudSyncEnabled else { return }
        store.synchronizeWithICloud()
        ICloudBackupService.shared.backup(tokens: store.allTokens, force: true)
    }

    // ── Menu ──

    private func buildMenu() {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(NSMenuItem(title: L("關於 TokenVault"), action: #selector(showAbout), keyEquivalent: ""))
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: L("設定..."), action: #selector(showSettings), keyEquivalent: ","))
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: L("鎖定"), action: #selector(lockApp), keyEquivalent: "l"))
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: L("隱藏"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        app.addItem(NSMenuItem(title: L("退出"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        main.addItem({ let i = NSMenuItem(); i.submenu = app; return i }())

        let file = NSMenu(title: "檔案")
        file.addItem(NSMenuItem(title: L("新增 Token"), action: #selector(newToken), keyEquivalent: "n"))
        file.addItem(NSMenuItem(title: L("新增分組"), action: #selector(newGroup), keyEquivalent: "N"))
        file.addItem(.separator())
        file.addItem(NSMenuItem(title: L("匯入..."), action: #selector(showImport), keyEquivalent: "i"))
        file.addItem(NSMenuItem(title: L("匯出備份..."), action: #selector(exportBackup), keyEquivalent: "e"))
        main.addItem({ let i = NSMenuItem(); i.submenu = file; return i }())

        let edit = NSMenu(title: "編輯")
        edit.addItem(NSMenuItem(title: L("還原"), action: #selector(undoAction), keyEquivalent: "z"))
        edit.addItem(NSMenuItem(title: L("重做"), action: #selector(redoAction), keyEquivalent: "Z"))
        main.addItem({ let i = NSMenuItem(); i.submenu = edit; return i }())

        let help = NSMenu(title: "輔助說明")
        help.addItem(NSMenuItem(title: L("TokenVault 說明"), action: #selector(showHelp), keyEquivalent: "?"))
        main.addItem({ let i = NSMenuItem(); i.submenu = help; return i }())
        NSApplication.shared.mainMenu = main
    }

    // ── Menu Bar ──

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "key.horizontal.fill", accessibilityDescription: "TokenVault")
            btn.toolTip = "TokenVault"
            btn.action = #selector(togglePopover)
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L("顯示主視窗"), action: #selector(showMainContent), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L("鎖定"), action: #selector(lockApp), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: L("設定..."), action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("退出"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); popover.contentViewController?.view.window?.makeKey() }
    }

    // ── Windows ──

    /// Standard window configuration with solid background.
    private func applyGlassStyle(_ window: NSWindow?, title: String, size: NSSize,
                                  minSize: NSSize? = nil, movable: Bool = false,
                                  floating: Bool = false, fullSize: Bool = true) {
        guard let w = window else { return }
        w.title = title
        w.setContentSize(size)
        if let m = minSize { w.minSize = m }
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.isMovableByWindowBackground = movable
        w.backgroundColor = .windowBackgroundColor
        // macOS 26+ Liquid Glass: allow translucency through the window.
        // On older systems, keep opaque for compatibility.
        if #available(macOS 26, *) {
            w.isOpaque = false
        } else {
            w.isOpaque = true
        }
        w.hasShadow = true
        if floating { w.level = .floating }
        if fullSize {
            w.styleMask.insert(.fullSizeContentView)
        } else {
            w.styleMask.remove(.fullSizeContentView)
        }
        w.center()
    }

    private func setupMainWindow() {
        // One place to kill the blue Tab focus rings for the whole window.
        let hosting = NSHostingController(rootView: MainView(store: store).focusEffectDisabled())
        mainWindow = NSWindow(contentViewController: hosting)
        mainWindow?.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        applyGlassStyle(mainWindow, title: "TokenVault",
                        size: NSSize(width: 900, height: 680),
                        minSize: NSSize(width: 640, height: 500))
        mainWindow?.setFrameAutosaveName("TokenVaultMain")
    }

    @objc func showMainContent() {
        guard !auth.isLocked else { showLockScreen(); return }
        NSApp.activate(ignoringOtherApps: true); mainWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().focusEffectDisabled()))
            settingsWindow?.styleMask = [.titled, .closable, .fullSizeContentView]
            applyGlassStyle(settingsWindow, title: L("設定"),
                            size: NSSize(width: 480, height: 520),
                            minSize: NSSize(width: 440, height: 440))
            settingsWindow?.setFrameAutosaveName("TokenVaultSettings")
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showHelp() {
        if helpWindow == nil {
            helpWindow = NSWindow(contentViewController: NSHostingController(rootView: HelpView()))
            helpWindow?.styleMask = [.titled, .closable, .fullSizeContentView]
            applyGlassStyle(helpWindow, title: L("TokenVault 說明"),
                            size: NSSize(width: 520, height: 500),
                            minSize: NSSize(width: 480, height: 420))
            helpWindow?.setFrameAutosaveName("TokenVaultHelp")
        }
        NSApp.activate(ignoringOtherApps: true); helpWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showAbout() {
        if aboutWindow == nil {
            let win = NSWindow(contentViewController: NSHostingController(rootView: AboutView().focusEffectDisabled()))
            win.styleMask = [.titled, .closable, .fullSizeContentView]
            aboutWindow = win
            applyGlassStyle(aboutWindow, title: L("關於 TokenVault"),
                            size: NSSize(width: 420, height: 476))
            aboutWindow?.setFrameAutosaveName("TokenVaultAbout")
        }
        NSApp.activate(ignoringOtherApps: true); aboutWindow?.makeKeyAndOrderFront(nil)
    }

    // ── Lock Screen ──

    private func showLockScreen() {
        let lockView = LockView(auth: auth) { [weak self] in
            self?.lastUnlockTime = Date()
            self?.lockWindow?.close(); self?.lockWindow = nil; self?.showMainContent()
        }
        lockWindow?.close()
        lockWindow = NSWindow(contentViewController: NSHostingController(rootView: lockView))
        lockWindow?.styleMask = [.titled, .closable, .fullSizeContentView]
        applyGlassStyle(lockWindow, title: "TokenVault",
                        size: NSSize(width: 420, height: 520),
                        movable: true, floating: true)
        lockWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func appDidResignActive() {
        guard settings.autoLockEnabled, lockWindow == nil else { return }
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.autoLockSeconds), repeats: false) { [weak self] _ in
            self?.performLock()
        }
    }

    @objc private func appDidBecomeActive() {
        idleTimer?.invalidate()
        idleTimer = nil
        // Another device may have written while this app was in the background.
        ICloudSyncService.shared.requestSyncNow()
    }

    private func performLock() {
        guard lockWindow == nil else { return }
        auth.lock()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        DispatchQueue.main.async { [weak self] in
            if self?.auth.isLocked == true {
                self?.showLockScreen()
                // Auto-auth on idle-lock resume for seamless return
                Task { await self?.auth.authenticate() }
            }
        }
    }

    // ── Backup ──

    @objc func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tokenvault-backup-\(Date().formatted(date: .abbreviated, time: .omitted)).json"
        panel.allowedContentTypes = [.json, .plainText, .commaSeparatedText]
        panel.begin { [weak self] r in
            guard let self, r == .OK, let url = panel.url else { return }
            let tokens = store.activeTokens
            let ext = url.pathExtension.lowercased()
            let content: String
            if ext == "csv" {
                content = ImportExportHelper.exportCSV(tokens)
            } else if ext == "env" || ext == "txt" {
                content = ImportExportHelper.exportEnv(tokens)
            } else {
                // JSON backup (default)
                let snap = DataStore.BackupSnapshot(groups: store.groups, tokens: store.allTokens)
                if let d = try? JSONEncoder().encode(snap) { try? d.write(to: url); return }
                return
            }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @objc func showImport() {
        showMainContent()
        NotificationCenter.default.post(name: .showImportWizard, object: nil)
    }

    // Legacy: JSON-only backup import
    @objc func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { [weak self] r in
            guard let self, r == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
            DispatchQueue.main.async {
                if let snap = try? JSONDecoder().decode(DataStore.BackupSnapshot.self, from: data) {
                    self.store.groups = snap.groups; self.store.allTokens = snap.tokens; self.store.save()
                }
            }
        }
    }

    // ── ⌘⇧T ──

    private func setupGlobalHotkey() {
        var ref: EventHotKeyRef?
        let gid = EventHotKeyID(signature: 0x544B5654, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(cmdKey | shiftKey), gid, GetApplicationEventTarget(), 0, &ref)
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hid = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hid)
            if hid.id == 1 {
                DispatchQueue.main.async {
                    guard let d = NSApp.delegate as? AppDelegate, !d.auth.isLocked else { return }
                    let token = d.store.activeTokens
                        .filter { $0.isFavorite }
                        .sorted(by: { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }).first
                        ?? d.store.activeTokens
                        .sorted(by: { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }).first
                    guard let t = token else { return }
                    d.copyToken(t)
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

// MARK: - App Store screenshots (`--capture-shots <dir>`)

extension AppDelegate {
    /// Destination for store images, or nil on a normal launch. Everything below is dead code
    /// unless the app is started by `scripts/make-macos-shots.sh`.
    static var storeShotDirectory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--capture-shots"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    /// Demo vault so the windows have something to show. Writes only to whatever store directory
    /// this process is pointed at (the shot script runs with a throwaway HOME).
    func seedStoreShotData() {
        guard store.allTokens.isEmpty else { return }

        store.addGroup("客戶端 App")
        store.addGroup("伺服器")
        let groups = store.groups

        func add(_ name: String, _ value: String, _ env: TokenEnvironment, _ group: TokenGroup?,
                 tags: [String] = [], note: String = "", fav: Bool = false, copies: Int = 0) {
            let t = TokenItem(name: name, plainValue: value, note: note, environment: env,
                              tags: tags, groupID: group?.id)
            t.isFavorite = fav
            t.copyCount = copies
            if copies > 0 { t.lastUsedAt = Date().addingTimeInterval(-Double(copies) * 3600) }
            store.addToken(t, to: group)
        }

        add(L("OpenAI 生產密鑰"), "sk-proj-A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7", .production, groups.first,
            tags: ["chat", "ai"], note: "GPT-4o 與圖像生成共用", fav: true, copies: 42)
        add(L("GitHub Actions Token"), "ghp_9xY2mK4pQ7rT1vW3nB6cD8eF0gH5jL2sT4u", .production, groups.first,
            tags: ["ci"], note: "release workflow 專用，90 天輪換", fav: true, copies: 17)
        add(L("Stripe 測試密鑰"), "sk_test_51Nc8ZkL2mQ9rT4vW7xY1bN3cD6eF8gH2jK5", .staging, groups.first,
            tags: ["payment"], note: "只在 staging 使用", copies: 9)
        add(L("Anthropic Claude"), "sk-ant-api03-Q7rT2vW9xY4bN1cD8eF5gH3jL6sP0mK2v", .production, nil,
            tags: ["ai"], copies: 23)
        add(L("Cloudflare API Token"), "cf-9xY2mK4pQ7rT1vW3nB6cD8eF0gH5jL2sT3b", .production, groups.last,
            tags: ["dns", "cdn"], note: "wrangler deploy 使用", copies: 31)
        add(L("AWS 部署角色"), "AKIA3XQ7RT2VW9XY4BN1", .production, groups.last,
            tags: ["iam"], note: "ci-deploy role，只允許 ECR push")
        add(L("Vercel 預覽部署"), "vercel_tok_4vW9xY2bN6cD1eF8gH3jL7sP0mK5rT", .development, groups.last,
            tags: ["preview"], copies: 6)
        add(L("Supabase Service Role"), "sbp_7rT2vW9xY4bN1cD8eF5gH3jL6sP0mK9x", .development, nil,
            tags: ["db"], note: "只給後台服務使用")

        store.save()
    }

    func captureStoreShots(into requested: URL) {
        // The build is sandboxed, so an arbitrary path like /tmp is not writable. Fall back to the
        // container and print where the files actually went.
        let dir = FileManager.default.isWritableFile(atPath: requested.path)
            ? requested
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("store-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        print("[shot] writing to \(dir.path)")
        mainWindow?.setContentSize(NSSize(width: 1180, height: 780))
        mainWindow?.center()

        func shot(_ name: String, _ window: NSWindow?) {
            write(window: window, to: dir.appendingPathComponent(name))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            shot("01-main.png", self.mainWindow)

            // Add-token sheet: capture the sheet itself, then close it deterministically.
            NotificationCenter.default.post(name: .showAddToken, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                shot("02-editor.png", self.mainWindow?.attachedSheet)
                if let sheet = self.mainWindow?.attachedSheet {
                    self.mainWindow?.endSheet(sheet)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self.showLockScreen()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        shot("03-lock.png", self.lockWindow)
                        self.lockWindow?.orderOut(nil)
                        self.auth.isLocked = false
                        self.showAbout()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            self.aboutWindow?.makeFirstResponder(nil)
                            shot("04-about.png", self.aboutWindow)
                            self.showSettings()
                            NotificationCenter.default.post(name: .showSettingsSyncTab, object: nil)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                shot("05-settings.png", self.settingsWindow)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func write(window: NSWindow?, to url: URL) {
        guard let window, let view = window.contentView?.superview else { return }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 0, let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        print("[shot] \(url.lastPathComponent) \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }
}

// MARK: - Backup self-test (`--backup-selftest`)

extension AppDelegate {
    /// Exercises the real backup path (encrypt → write → read → decrypt) and prints the result.
    /// Used to verify the feature on machines where no iCloud container is provisioned yet.
    func runBackupSelfTestIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--backup-selftest") else { return false }
        settings.iCloudSyncEnabled = true
        seedStoreShotData()
        ICloudBackupService.shared.refreshStatus(enabled: true)

        let expected = store.allTokens.count
        ICloudBackupService.shared.backup(tokens: store.allTokens, force: true)
        let status = ICloudBackupService.shared.status.summary
        let snapshots = ICloudBackupService.shared.snapshots()
        let restored = snapshots.first?.tokens ?? []
        let sameIDs = Set(restored.map(\.id)) == Set(store.allTokens.map(\.id))

        print("SELFTEST status=\(status)")
        print("SELFTEST written=\(expected) snapshots=\(snapshots.count) restored=\(restored.count) idsMatch=\(sameIDs)")
        if let first = restored.first {
            print("SELFTEST firstToken=\(first.name) valueReadable=\(!first.decryptedValue().isEmpty)")
        }
        exit(snapshots.isEmpty || !sameIDs ? 1 : 0)
    }
}

// MARK: - iCloud sync self-test (`--sync-selftest`)

extension AppDelegate {
    /// Plays both devices in one process: two different vault master keys, one shared folder, and
    /// the real service code in between — encrypt, seal, write, read, merge, re-encrypt, tombstone.
    /// Nothing here touches iCloud, so it runs on a Mac without a container.
    func runSyncSelfTestIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--sync-selftest") else { return false }

        let shared = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tv-sync-selftest-\(UUID().uuidString)/TokenVault", isDirectory: true)
        try? FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)

        let sync = ICloudSyncService.shared
        sync.useLocalDirectoryForTesting(shared)
        ICloudSyncService.keyOverride = Data(repeating: 0x5C, count: 32)

        let keyA = Data(repeating: 0xA1, count: 32)
        let keyB = Data(repeating: 0xB2, count: 32)
        // One process, two devices: each has its own master key and its own change ledger, exactly
        // like two installs with their own UserDefaults.
        UserDefaults.standard.removeObject(forKey: "tv.sync.selftest.A")
        UserDefaults.standard.removeObject(forKey: "tv.sync.selftest.B")
        func becomeDevice(_ name: String, key: Data) {
            EncryptionService.keyOverride = key
            sync.useLedgerKeyForTesting("tv.sync.selftest.\(name)")
        }

        var failures = 0
        func check(_ ok: Bool, _ label: String) {
            if !ok { failures += 1 }
            print("SELFTEST \(ok ? "ok  " : "FAIL") \(label)")
        }

        // ── Device A writes three tokens and one folder ──
        becomeDevice("A", key: keyA)
        let group = SyncGroup(id: UUID(), name: "工作", icon: "briefcase.fill", sortOrder: 0)
        var a = [
            TokenItem(name: "OpenAI", plainValue: "sk-a-openai", groupID: group.id),
            TokenItem(name: "GitHub", plainValue: "ghp-a-github"),
            TokenItem(name: "Cloudflare", plainValue: "cf-a-cloudflare")
        ]
        let a1 = sync.synchronize(tokens: a, groups: [group])
        a = a1?.tokens ?? a
        check(a1?.written == true, "A writes the first snapshot")
        check(a.count == 3, "A keeps its three tokens")

        let file = shared.appendingPathComponent("vault.tvsync")
        check(FileManager.default.fileExists(atPath: file.path), "vault.tvsync is created in the shared folder")
        let raw = (try? Data(contentsOf: file)) ?? Data()
        print("SELFTEST payload=\(raw.count) bytes at \(file.path)")
        check(!raw.isEmpty && !String(decoding: raw, as: UTF8.self).contains("sk-a-openai"),
              "the payload is sealed, not plaintext")

        // ── Device B: different master key, one token of its own ──
        becomeDevice("B", key: keyB)
        var b = [TokenItem(name: "Stripe", plainValue: "sk_test-b-stripe")]
        let b1 = sync.synchronize(tokens: b, groups: [])
        b = b1?.tokens ?? b
        check(b.count == 4, "B pulls A's three tokens and keeps its own")
        check(b.first { $0.name == "OpenAI" }?.decryptedValue() == "sk-a-openai", "B decrypts A's secret")
        check(b1?.written == true, "B pushes its own token")
        check(b1?.groups.count == 1, "B receives A's folder")

        // ── A pulls B's token, and a quiet round trip writes nothing ──
        becomeDevice("A", key: keyA)
        let a2 = sync.synchronize(tokens: a, groups: [group])
        a = a2?.tokens ?? a
        check(a.count == 4, "A pulls B's token")
        check(a.first { $0.name == "Stripe" }?.decryptedValue() == "sk_test-b-stripe", "A decrypts B's secret")
        check(a2?.written == false, "an unchanged vault does not rewrite the file")

        // ── An edit on A reaches B ──
        if let gh = a.first(where: { $0.name == "GitHub" }) { gh.note = "edited on A"; gh.touch() }
        let a3 = sync.synchronize(tokens: a, groups: [group])
        a = a3?.tokens ?? a
        check(a3?.written == true, "an edit on A is pushed")
        becomeDevice("B", key: keyB)
        let b2 = sync.synchronize(tokens: b, groups: [])
        b = b2?.tokens ?? b
        check(b.first { $0.name == "GitHub" }?.note == "edited on A", "the edit arrives on B")

        // ── A permanent delete on B removes the row on A, and it stays gone ──
        b.removeAll { $0.name == "Cloudflare" }
        _ = sync.synchronize(tokens: b, groups: [])
        becomeDevice("A", key: keyA)
        let a4 = sync.synchronize(tokens: a, groups: [group])
        a = a4?.tokens ?? a
        check(a.count == 3 && !a.contains { $0.name == "Cloudflare" },
              "the delete propagates instead of resurrecting")
        let a5 = sync.synchronize(tokens: a, groups: [group])
        check(a5?.tokens.count == 3, "the row stays gone on the next round trip")

        print("SELFTEST failures=\(failures) tokensA=\(a.count) tokensB=\(b.count)")
        exit(failures == 0 ? 0 : 1)
    }
}

// MARK: - iCloud write probe (`--sync-write-probe`)

extension AppDelegate {
    /// Adds one throwaway token, syncs, deletes it, syncs again. Proves **this device** can write the
    /// shared payload — not just read it — through the real container and key. Leaves nothing behind
    /// but a tombstone. Run it while the other device is in the foreground to watch it apply both
    /// steps in its own console.
    func runSyncWriteProbeIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--sync-write-probe") else { return false }
        settings.iCloudSyncEnabled = true
        ICloudSyncService.shared.isEnabled = true
        ICloudSyncService.shared.performSync = { [weak self] in self?.store.synchronizeWithICloud() }
        ICloudSyncService.shared.activate()

        let probe = TokenItem(name: "同步探針", plainValue: "probe-\(UUID().uuidString)",
                              note: "由 --sync-write-probe 建立，隨即刪除")

        // activate() resolves the container on a background thread; give it a beat before writing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { exit(1) }
            self.store.addToken(probe, to: nil)
            // In-place edit: this is the path a text field binding takes — token.objectWillChange →
            // DataStore.notify(touching:) → touch(). It used to overflow the stack there.
            probe.note = "探針（就地修改）"
            self.store.synchronizeWithICloud()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.store.deleteToken(probe)
                self.store.synchronizeWithICloud()
                print("SELFTEST probe removed; final status=\(ICloudSyncService.shared.statusText)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { exit(0) }
            }
        }
        return true
    }
}

// MARK: - Offscreen render (`--render-lock <path>`)

extension AppDelegate {
    /// Renders the real `LockView` to a PNG so the launch screen can be reviewed without screen
    /// recording permission (which an app should never need just to look at itself).
    @MainActor
    func runRenderLockIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--render-lock"), args.count > index + 1 else {
            return false
        }
        let path = args[index + 1]
        // Match how the lock screen actually appears: it inherits the app's colour scheme, and
        // ImageRenderer has no window to inherit from.
        let dark = !args.contains("--light")
        let view = LockView(auth: AuthService(), onUnlock: {})
            .frame(width: 420, height: 520)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("SELFTEST render failed")
            exit(1)
        }
        // The sandbox cannot write /tmp; fall back to the container's own temp directory and report
        // where the file actually landed.
        var target = URL(fileURLWithPath: path)
        do {
            try png.write(to: target)
        } catch {
            // Prefer the iCloud container: it is the one place the sandbox writes that a human (and
            // a shell) can read back without special permissions.
            target = FileManager.default
                .url(forUbiquityContainerIdentifier: ICloudSyncService.containerIdentifier)?
                .appendingPathComponent("Documents/tv-lock.png")
                ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tv-lock.png")
            do { try png.write(to: target) } catch {
                print("SELFTEST render write failed: \(error)")
                exit(1)
            }
        }
        print("SELFTEST rendered \(target.path) \(Int(image.size.width))x\(Int(image.size.height))")
        exit(0)
    }
}


// MARK: - Custom folder self-test (`--sync-folder-selftest`)

extension AppDelegate {
    /// Points the sync at a folder, writes, and reports where the payload actually landed. Covers
    /// the bookmark round trip, the directory switch and the write — everything the ✕「選擇資料夾」
    /// button does except the human choosing the folder.
    func runSyncFolderSelfTestIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--sync-folder-selftest") else { return false }
        settings.iCloudSyncEnabled = true
        ICloudSyncService.shared.isEnabled = true
        ICloudSyncService.shared.performSync = { [weak self] in self?.store.synchronizeWithICloud() }

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tv-folder-test", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try ICloudSyncService.shared.setCustomFolder(dir)
        } catch {
            print("SELFTEST folder bookmark failed: \(error)")
            exit(1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            ICloudSyncService.shared.requestSyncNow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                let file = dir.appendingPathComponent("TokenVault/vault.tvsync")
                let exists = FileManager.default.fileExists(atPath: file.path)
                let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
                let resolved = ICloudSyncService.shared.directory?.path ?? "-"
                print("SELFTEST customFolder=\(ICloudSyncService.shared.isUsingCustomFolder) wrote=\(exists) bytes=\(bytes ?? 0)")
                print("SELFTEST resolved=\(resolved)")
                ICloudSyncService.shared.clearCustomFolder()
                exit(exists ? 0 : 1)
            }
        }
        return true
    }
}

#endif
