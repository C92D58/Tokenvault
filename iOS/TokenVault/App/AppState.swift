import Foundation
import SwiftUI
import UIKit

/// Process launch switches. Only the UI-test / demo path uses them; a normal launch passes none.
struct LaunchOptions {
    var resetStore = false
    var seedDemo = false
    var startUnlocked = false
    var stayLocked = false

    /// Any UI-test launch. Used to skip one-time system prompts (notification permission) that
    /// would otherwise cover the screen and make the suite non-deterministic.
    var isUITest: Bool { resetStore || seedDemo || startUnlocked || stayLocked }

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        resetStore = arguments.contains("-uiTestReset")
        seedDemo = arguments.contains("-uiTestSeed")
        startUnlocked = arguments.contains("-uiTestUnlocked")
        stayLocked = arguments.contains("-uiTestLocked")
    }
}

/// Owns the four things every screen needs: the vault, the preferences, the lock, and the toast.
final class AppState: ObservableObject {
    let vault: VaultStore
    let settings: SettingsStore
    let toast = ToastCenter()
    let auth = AuthGate()

    @Published var isLocked = true
    /// Covers the UI in the app switcher, and while re-authenticating from the lock screen.
    @Published var isShielded = false

    private let options: LaunchOptions
    private var leftForegroundAt: Date?
    private var didPrepare = false

    init(options: LaunchOptions = LaunchOptions()) {
        self.options = options
        self.vault = VaultStore(reset: options.resetStore)
        self.settings = SettingsStore()
        if options.seedDemo { vault.seedDemoIfEmpty() }
        if options.stayLocked {
            isLocked = true
        } else if options.startUnlocked || !settings.biometricLock {
            isLocked = false
        }
    }

    // MARK: - Lifecycle

    func prepare() async {
        guard !didPrepare else { return }
        didPrepare = true
        // Screenshot mode: stay on the branded lock screen, no system sheet on top of it.
        if isLocked && !options.stayLocked { await unlock() }
        // 到期提醒預設開啟，但權限只有在設定頁被動打開過才會請求；不主動要一次，提醒永遠不會出現。
        if settings.expiryReminders && !options.isUITest { NotificationService.requestPermission() }
        refreshReminders()

        // iCloud: one round trip at launch, and a snapshot for the restore list.
        ICloudSyncService.shared.performSync = { [weak self] in self?.vault.synchronizeWithICloud() }
        if settings.iCloudSync && !options.isUITest {
            ICloudBackupService.shared.refreshStatus(enabled: true)
            ICloudBackupService.shared.backup(tokens: vault.activeTokens)
            ICloudSyncService.shared.isEnabled = true
            ICloudSyncService.shared.activate()
        }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            isShielded = true
            if leftForegroundAt == nil { leftForegroundAt = Date() }
            toast.dismiss()
            // The system may kill a backgrounded app at any time: push before that happens, then
            // keep an encrypted snapshot as the restore path of last resort.
            if case .background = phase, settings.iCloudSync {
                vault.synchronizeWithICloud()
                ICloudBackupService.shared.backup(tokens: vault.activeTokens, force: true)
            }
        case .active:
            isShielded = false
            if let left = leftForegroundAt {
                leftForegroundAt = nil
                let away = Date().timeIntervalSince(left)
                if settings.shouldLock(afterAwayFor: away) { lock() }
            }
            // Another device may have written while this app was in the background.
            ICloudSyncService.shared.requestSyncNow()
            // A clipboard clear may have been due while the app was suspended.
            ClipboardService.shared.clearIfExpired()
        @unknown default:
            break
        }
    }

    // MARK: - Lock / unlock

    func unlock() async {
        guard isLocked else { return }
        guard settings.biometricLock else {
            isLocked = false
            return
        }
        let ok = await auth.authenticate(reason: "解鎖 TokenVault 以存取你的 API 金鑰")
        if ok {
            isLocked = false
            SecurityLogService.shared.log(.unlocked, tokenID: UUID(), name: "—", provider: "—")
        }
    }

    func lock() {
        guard !isLocked else { return }
        ClipboardService.shared.clearNow()
        isLocked = true
        SecurityLogService.shared.log(.locked, tokenID: UUID(), name: "—", provider: "—")
    }

    // MARK: - Reminders

    func refreshReminders() {
        guard settings.expiryReminders else { return }
        NotificationService.scheduleExpiryReminders(for: vault.tokens)
    }
}
