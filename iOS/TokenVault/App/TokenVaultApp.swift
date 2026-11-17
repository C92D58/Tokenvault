import SwiftUI

@main
struct TokenVaultApp: App {
    @StateObject private var app = AppState()

    init() {
        // Before the first body runs: the app's own language has to win over the device's.
        installLanguageOverride()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(app.vault)
                .environmentObject(app.settings)
                .environmentObject(app.toast)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.scenePhase) private var scenePhase
    /// Observed, so a language change re-renders the tree and re-reads every string.
    @ObservedObject private var language = LanguageStore.shared
    /// The tab lives here, not in `MainTabView`: re-identifying the tree on a language change
    /// must not throw the user back to the vault.
    @State private var tab = MainTabView.initialTab

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if app.isLocked {
                LockView()
                    .transition(.opacity)
            } else {
                MainTabView(tab: $tab)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        // A new identity is what makes SwiftUI ask for the strings again; a passive environment
        // change would leave already-built labels in the old language.
        .id(language.language)
        .environment(\.locale, language.locale)
        .animation(Theme.Motion.appear, value: app.isLocked)
        // Applied here, not in the App struct: the App body never observes SettingsStore, so a
        // colour-scheme change made in Settings would not re-render until something else moved.
        .preferredColorScheme(settings.appearance.colorScheme)
        .overlay {
            if app.isShielded {
                PrivacyShield()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) { ToastHost() }
        .onChange(of: scenePhase) { _, phase in
            app.scenePhaseChanged(phase)
        }
        .task { await app.prepare() }
    }
}

/// Drawn over the whole app whenever it leaves the foreground, so the app switcher never
/// photographs a vault. Also the visual that stops a shoulder without any extra chrome.
struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: Theme.Space.s) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 28, weight: .semibold))
                Text("TokenVault")
                    .font(Theme.heading)
            }
            .foregroundStyle(Theme.textSecondary)
        }
        .ignoresSafeArea()
    }
}
