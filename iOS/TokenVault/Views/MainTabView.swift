import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var app: AppState
    /// Owned by `RootView` so a language change can re-identify this subtree without losing the tab.
    @Binding var tab: Int

    /// `-uiStartSettings` / `-uiStartTab N` open a specific tab on launch (used for screenshots).
    static var initialTab: Int {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiStartSettings") { return 3 }
        if let i = args.firstIndex(of: "-uiStartTab"), i + 1 < args.count, let n = Int(args[i + 1]) { return n }
        return 0
    }

    var body: some View {
        TabView(selection: $tab) {
            VaultView()
                .tabItem { Label(L("保險庫"), systemImage: "key.fill") }
                .tag(0)

            ToolsView()
                .tabItem { Label(L("工具"), systemImage: "wand.and.stars") }
                .tag(1)

            SecurityLogView()
                .tabItem { Label(L("日誌"), systemImage: "clock.arrow.circlepath") }
                .tag(2)

            SettingsView()
                .tabItem { Label(L("設定"), systemImage: "slider.horizontal.3") }
                .tag(3)
        }
        .tint(Theme.accent)
        .onChange(of: tab) { _, _ in
            if app.isLocked { tab = 0 }
        }
    }
}
