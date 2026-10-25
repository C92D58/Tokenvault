import SwiftUI

struct HelpView: View {
    /// The system `TabView` is an NSTabView on macOS and draws the blue keyboard focus ring around
    /// its tab bar the moment you press Tab. This window is read-only help text — nothing in it
    /// should ever be focusable — so the tab bar is drawn here instead.
    @State private var tab: HelpTab = .shortcuts

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().opacity(0.5)
            content
        }
        .frame(minWidth: 500, minHeight: 460)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        PillTabBar(items: HelpTab.allCases, title: \.title, icon: \.icon, selection: $tab)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .shortcuts: shortcutsTab
        case .guide: guideTab
        case .security: securityTab
        }
    }

    // MARK: - Shortcuts

    private var shortcutsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                shortcutRow("⌘N", "新增 Token")
                shortcutRow("⇧⌘N", "新增分組")
                shortcutRow("⌘⇧T", "貼上最近使用的 Token（全域）")
                shortcutRow("⌘L", "鎖定 TokenVault")
                shortcutRow("⌘K", "Spotlight 搜尋 Token")
                shortcutRow("⌘,", "開啟設定")
                shortcutRow("⌘W", "關閉視窗")
                shortcutRow("⌘Q", "退出")
                shortcutRow("↵", "在編輯器中儲存")
                shortcutRow("⎋", "取消編輯 / 關閉彈窗")
            }
            .padding()
        }
    }

    // MARK: - Guide

    private var guideTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                guideSection("快速開始", icon: "1.circle") {
                    Text("1. 按 `⌘N` 或點擊 `+` 新增 Token")
                    Text("2. 貼上 Token 值，輸入名稱")
                    Text("3. 可選：設定分組、到期日")
                    Text("4. 點擊卡片展開 → 點「複製」")
                }

                guideSection("選單列", icon: "menubar.rectangle") {
                    Text("• 點擊選單列 🔑 → 快速搜尋 → 一鍵複製")
                    Text("• 右鍵選單列圖示 → 顯示主視窗 / 鎖定")
                }

                guideSection("快捷貼上", icon: "keyboard") {
                    Text("按 `⌘⇧T`（全域快捷鍵）直接貼上你最常用的 Token，無需打開視窗。")
                }

                guideSection("分組管理", icon: "folder") {
                    Text("• 下拉選單切換分組篩選")
                    Text("• 點擊資料夾圖示新增分組")
                    Text("• 編輯 Token 時可選擇分組")
                }

                guideSection("到期提醒", icon: "clock") {
                    Text("• 🟠 橘色標記：7 天內到期")
                    Text("• 🔴 紅色標記：已過期")
                    Text("• 可設定到期日自動追蹤")
                }
            }
            .padding()
        }
    }

    // MARK: - Security

    private var securityTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                guideSection("加密", icon: "lock.shield") {
                    Text("所有 Token 值使用 AES-256-GCM 加密後儲存。主密鑰存放在 Secure Enclave 中，從不離開你的裝置。即使 iCloud 或 GitHub 上的數據被竊取，也無法解密。")
                }

                guideSection("資料隱私", icon: "eye.slash") {
                    Text("TokenVault 開發者（WAHSUN）無法存取你的任何 Token。加密和解密完全在你的裝置上進行。我們沒有伺服器，無法查看你的數據。")
                }

                guideSection("生物識別", icon: "faceid") {
                    Text("Face ID / Touch ID 僅用於解鎖 App，不參與加密過程。即使生物識別被繞過，Token 仍需主密鑰才能解密。")
                }

                guideSection("剪貼板", icon: "doc.on.clipboard") {
                    Text("複製到剪貼板的 Token 會在設定時間後自動清空，防止被其他 App 偷讀。")
                }

                guideSection("自動鎖定", icon: "lock") {
                    Text("離開視窗後自動鎖定。可在設定中調整閒置鎖定時間。")
                }
            }
            .padding()
        }
    }

    // MARK: - Components

    private func shortcutRow(_ key: String, _ desc: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.accentColor)
                .frame(width: 64, alignment: .trailing)
            Text(desc)
                .font(.system(size: 12))
            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
    }

    private func guideSection(_ title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L(title), systemImage: icon)
                .font(.system(size: 13, weight: .bold))
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }
    }
}

enum HelpTab: String, CaseIterable, Identifiable {
    case shortcuts, guide, security

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortcuts: return "快捷鍵"
        case .guide: return "使用說明"
        case .security: return "安全性"
        }
    }

    var icon: String {
        switch self {
        case .shortcuts: return "command"
        case .guide: return "book"
        case .security: return "lock.shield"
        }
    }
}
