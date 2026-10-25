import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system = "跟隨系統"
    case dark = "深色"
    case light = "淺色"

    var displayName: String { String(localized: String.LocalizationValue(rawValue)) }
}

final class SettingsService: ObservableObject {
    static let shared = SettingsService()

    @Published var appearanceMode: AppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearance") }
    }
    @Published var clipboardClearSeconds: Int {
        didSet { UserDefaults.standard.set(clipboardClearSeconds, forKey: "clipboard_clear") }
    }
    @Published var autoLockEnabled: Bool {
        didSet { UserDefaults.standard.set(autoLockEnabled, forKey: "auto_lock") }
    }
    @Published var autoLockSeconds: Int {
        didSet { UserDefaults.standard.set(autoLockSeconds, forKey: "auto_lock_sec") }
    }
    @Published var githubSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(githubSyncEnabled, forKey: "gh_sync") }
    }
    @Published var githubRepo: String {
        didSet { UserDefaults.standard.set(githubRepo, forKey: "gh_repo") }
    }
    @Published var iCloudSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(iCloudSyncEnabled, forKey: "icloud_sync") }
    }

    init() {
        let d = UserDefaults.standard
        appearanceMode = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        clipboardClearSeconds = d.object(forKey: "clipboard_clear") as? Int ?? 45
        autoLockEnabled = d.object(forKey: "auto_lock") as? Bool ?? true
        autoLockSeconds = d.object(forKey: "auto_lock_sec") as? Int ?? 60
        githubSyncEnabled = d.object(forKey: "gh_sync") as? Bool ?? false
        githubRepo = d.string(forKey: "gh_repo") ?? ""
        // The old switch only wrote encrypted snapshots; that became live sync. Carry the user's
        // choice over instead of silently turning a setting off.
        iCloudSyncEnabled = d.object(forKey: "icloud_sync") as? Bool
            ?? d.object(forKey: "icloud_backup") as? Bool
            ?? true
    }

    /// Apply appearance to all windows.
    func applyAppearance() {
        let appearance: NSAppearance?
        switch appearanceMode {
        case .dark: appearance = NSAppearance(named: .darkAqua)
        case .light: appearance = NSAppearance(named: .aqua)
        case .system: appearance = nil
        }
        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
        }
    }
}
