import SwiftUI
import UIKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "跟隨系統"
        case .light: return "淺色"
        case .dark: return "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Preferences live in UserDefaults; the vault never does.
final class SettingsStore: ObservableObject {
    static let autoLockChoices: [(label: String, seconds: Int)] = [
        ("立即", 0), ("30 秒", 30), ("1 分鐘", 60), ("5 分鐘", 300), ("從不", -1)
    ]
    static let clipboardChoices: [(label: String, seconds: Int)] = [
        ("15 秒", 15), ("30 秒", 30), ("45 秒", 45), ("2 分鐘", 120), ("從不", -1)
    ]

    @Published var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    @Published var biometricLock: Bool { didSet { defaults.set(biometricLock, forKey: Keys.biometricLock) } }
    @Published var autoLockSeconds: Int { didSet { defaults.set(autoLockSeconds, forKey: Keys.autoLock) } }
    @Published var clipboardClearSeconds: Int { didSet { defaults.set(clipboardClearSeconds, forKey: Keys.clipboard) } }
    @Published var expiryReminders: Bool { didSet { defaults.set(expiryReminders, forKey: Keys.reminders) } }
    @Published var iCloudSync: Bool { didSet { defaults.set(iCloudSync, forKey: Keys.icloudSync) } }
    @Published var hasSeenWelcome: Bool { didSet { defaults.set(hasSeenWelcome, forKey: Keys.welcome) } }

    private let defaults: UserDefaults

    private enum Keys {
        static let appearance = "tv.appearance"
        static let biometricLock = "tv.biometricLock"
        static let autoLock = "tv.autoLockSeconds"
        static let clipboard = "tv.clipboardClearSeconds"
        static let reminders = "tv.expiryReminders"
        static let icloudSync = "tv.iCloudSync"
        static let icloudBackupLegacy = "tv.iCloudBackup"
        static let welcome = "tv.hasSeenWelcome"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        biometricLock = defaults.object(forKey: Keys.biometricLock) as? Bool ?? true
        autoLockSeconds = defaults.object(forKey: Keys.autoLock) as? Int ?? 60
        clipboardClearSeconds = defaults.object(forKey: Keys.clipboard) as? Int ?? 45
        expiryReminders = defaults.object(forKey: Keys.reminders) as? Bool ?? true
        iCloudSync = defaults.object(forKey: Keys.icloudSync) as? Bool
            ?? defaults.object(forKey: Keys.icloudBackupLegacy) as? Bool
            ?? true
        hasSeenWelcome = defaults.object(forKey: Keys.welcome) as? Bool ?? false
    }

    /// Whether time spent away should relock the vault.
    func shouldLock(afterAwayFor seconds: TimeInterval) -> Bool {
        guard biometricLock else { return false }
        if autoLockSeconds < 0 { return false }
        if autoLockSeconds == 0 { return true }
        return seconds >= TimeInterval(autoLockSeconds)
    }

    var autoLockLabel: String {
        Self.autoLockChoices.first { $0.seconds == autoLockSeconds }?.label ?? "自訂"
    }

    var clipboardLabel: String {
        Self.clipboardChoices.first { $0.seconds == clipboardClearSeconds }?.label ?? "自訂"
    }
}
