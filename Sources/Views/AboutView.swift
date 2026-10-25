import SwiftUI
import AppKit

/// The About panel.
///
/// macOS answers one question here — what is this app and who made it — so the layout is a stack of
/// three facts under the real app icon, and nothing else competes with them. (An in-app SF Symbol
/// standing in for the icon is wrong: the About panel is the one place the icon should be itself.)
struct AboutView: View {
    @State private var tapped = 0

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    /// The bundle's own icon — the same artwork as the .icns, never a substitute symbol.
    private var appIcon: NSImage {
        NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 128, height: 128))
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 96, height: 96)
                .padding(.top, 32)
                .onTapGesture { tapped += 1 }

            Text("TokenVault")
                .font(.system(size: 23, weight: .bold))
                .tracking(-0.4)
                .padding(.top, 14)

            Text("版本 \(appVersion)")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(.top, 3)

            Text("開發者的 API 密鑰保險庫")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            VStack(spacing: 0) {
                feature(symbol: "lock.fill", title: "AES-256-GCM",
                        detail: "每個值獨立加密，金鑰存在鑰匙圈")
                hairline
                feature(symbol: "faceid", title: "Face ID / Touch ID",
                        detail: "解鎖 App 才看得到內容")
                hairline
                feature(symbol: "internaldrive", title: "本機儲存",
                        detail: "只留在這台 Mac，不上傳任何伺服器")
            }
            .padding(.top, 22)
            .padding(.horizontal, 26)

            Spacer(minLength: 12)

            VStack(spacing: 7) {
                Text(tapped >= 5 ? "🔐 安全無小事" : " ")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DS.Color.accentGradient)
                    .frame(height: 12)

                HStack(spacing: 6) {
                    Text("開發者")
                        .foregroundStyle(.secondary)
                    Link("WAHSUN", destination: URL(string: "https://wahsun.org")!)
                        .accessibilityIdentifier("developerLink")
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Link("隱私政策", destination: URL(string: "https://privacy.wahsun.org/")!)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("MIT 授權")
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 11))
                // Tab 鍵走過連結時 macOS 會畫一圈藍色 focus ring；整頁其他控制項都關了，這裡也關，
                // 否則只有 footer 這兩個字會突然亮起來。
                .focusEffectDisabled()
            }
            .padding(.bottom, 22)
        }
        .frame(width: 420, height: 476)
        .background(
            ZStack {
                Rectangle().fill(.regularMaterial)
                DS.Color.accentGradientSubtle.opacity(0.45)
                    .allowsHitTesting(false)
            }
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: tapped)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private func feature(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Color.accent)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DS.Color.accent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(L(title))
                    .font(.system(size: 12.5, weight: .medium))
                Text(L(detail))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }
}
