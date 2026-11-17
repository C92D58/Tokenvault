import SwiftUI

/// Four utilities that do not need a network round-trip to be useful on a phone.
struct ToolsView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var toast: ToastCenter

    // Generator
    @State private var mode = 0
    @State private var length: Double = 32
    @State private var useUpper = true
    @State private var useLower = true
    @State private var useDigits = true
    @State private var useSymbols = false
    @State private var generated = ""

    // JWT
    @State private var jwtInput = ""
    @State private var decoded: JWTDecoder.Decoded?
    @State private var jwtMessage: String?

    // Health
    @State private var results: [HealthCheckService.HealthResult] = []
    @State private var checking = false

    // Duplicates
    @State private var duplicates: [(TokenItem, TokenItem)] = []
    @State private var scanned = false

    private let modes = ["API 金鑰", "密碼", "十六進位"]

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(spacing: Theme.Space.m) {
                        header
                        generatorCard
                        jwtCard
                        healthCard
                        duplicateCard
                    }
                    .padding(.horizontal, Theme.inset)
                    .padding(.bottom, 110)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            if generated.isEmpty { generate() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L("工具"))
                .font(Theme.title)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("tools.title")
            Text(L("產生、解碼、檢查 — 全部在這台裝置上完成"))
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Space.s)
    }

    // MARK: - Generator

    private var generatorCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            cardTitle("密鑰產生器", symbol: "wand.and.stars")

            SlidingSegmented(items: modes, selection: $mode)
                .onChange(of: mode) { _, _ in generate() }

            Text(generated.isEmpty ? "—" : generated)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.surfaceRaised))
                .accessibilityIdentifier("tools.generated")

            HStack(spacing: Theme.Space.xs) {
                Text(L("長度"))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                Slider(value: $length, in: 8...64, step: 1)
                    .tint(Theme.accent)
                    .onChange(of: length) { _, _ in generate() }
                Text("\(Int(length))")
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 26, alignment: .trailing)
            }

            if mode != 2 {
                HStack(spacing: Theme.Space.xs) {
                    charsetToggle("A-Z", isOn: $useUpper)
                    charsetToggle("a-z", isOn: $useLower)
                    charsetToggle("0-9", isOn: $useDigits)
                    if mode == 1 { charsetToggle("!@#", isOn: $useSymbols) }
                }
            }

            HStack(spacing: Theme.Space.xs) {
                SecondaryButton(title: "重新產生", symbol: "arrow.triangle.2.circlepath") {
                    generate()
                }
                SecondaryButton(title: "複製", symbol: "doc.on.doc") {
                    ClipboardService.shared.copy(generated, clearAfter: settings.clipboardClearSeconds)
                    toast.show("已複製新密鑰", symbol: "doc.on.doc.fill", tint: Theme.accent)
                }
            }
        }
        .cardSurface(padding: Theme.Space.m)
    }

    private func charsetToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            Haptics.select()
            isOn.wrappedValue.toggle()
            generate()
        } label: {
            Text(L(label))
                .font(Theme.monoSmall)
                .foregroundStyle(isOn.wrappedValue ? Color.white : Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(isOn.wrappedValue
                    ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceRaised)))
        }
        .pressable()
    }

    private func generate() {
        var alphabet = ""
        switch mode {
        case 2:
            alphabet = "0123456789abcdef"
        default:
            if useUpper { alphabet += "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
            if useLower { alphabet += "abcdefghijklmnopqrstuvwxyz" }
            if useDigits { alphabet += "0123456789" }
            if useSymbols && mode == 1 { alphabet += "!@#$%^&*()-_=+[]{};:,.?/" }
        }
        if alphabet.isEmpty { alphabet = "abcdefghijklmnopqrstuvwxyz0123456789" }
        let chars = Array(alphabet)
        generated = String((0..<Int(length)).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    // MARK: - JWT

    private var jwtCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            cardTitle("JWT 解碼", symbol: "ticket")

            TextField(L("貼上 JWT（eyJ…）"), text: $jwtInput, axis: .vertical)
                .font(Theme.monoSmall)
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(2...4)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.surfaceRaised))
                .accessibilityIdentifier("tools.jwtInput")

            HStack(spacing: Theme.Space.xs) {
                SecondaryButton(title: "解碼", symbol: "lock.open") {
                    if let result = JWTDecoder.decode(jwtInput) {
                        decoded = result
                        jwtMessage = nil
                        Haptics.success()
                    } else {
                        decoded = nil
                        jwtMessage = L("這不是有效的 JWT（需三段以 . 分隔的 base64url）")
                        Haptics.warning()
                    }
                }
                SecondaryButton(title: "貼上", symbol: "doc.on.clipboard") {
                    if let text = UIPasteboard.general.string { jwtInput = text }
                }
            }

            if let message = jwtMessage {
                Text(message)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
            }

            if let decoded {
                Divider().overlay(Theme.hairline)
                HStack(spacing: Theme.Space.xs) {
                    Pill(text: decoded.isExpired ? "已過期" : "有效",
                         tint: decoded.isExpired ? Theme.danger : Theme.success)
                    Text(decoded.expiryLabel)
                        .font(Theme.monoSmall)
                        .foregroundStyle(Theme.textTertiary)
                }
                ForEach(decoded.claims.prefix(12)) { claim in
                    HStack(alignment: .top, spacing: Theme.Space.s) {
                        Text(claim.key)
                            .font(Theme.monoSmall)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 88, alignment: .leading)
                        Text(claim.value)
                            .font(Theme.monoSmall)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .cardSurface(padding: Theme.Space.m)
    }

    // MARK: - Health

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            cardTitle("Token 健康檢查", symbol: "stethoscope")

            Text(L("對 GitHub、OpenAI、Cloudflare 實際發出一次驗證請求，確認密鑰仍然有效。只在你按下按鈕時才會連網。"))
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            SecondaryButton(title: checking ? "檢查中…" : "開始檢查",
                            symbol: checking ? "hourglass" : "play.fill") {
                runHealthCheck()
            }
            .disabled(checking)

            ForEach(results) { result in
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: result.status.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: result.status.color))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.tokenName)
                            .font(Theme.callout)
                            .foregroundStyle(Theme.textPrimary)
                        Text(result.message)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Text(result.provider.label)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.vertical, 3)
            }
        }
        .cardSurface(padding: Theme.Space.m)
    }

    private func runHealthCheck() {
        checking = true
        let tokens = vault.activeTokens.filter { [.github, .openai, .cloudflare].contains($0.provider) }
        guard !tokens.isEmpty else {
            checking = false
            results = []
            toast.show("沒有可自動檢查的 Token", symbol: "questionmark.circle", tint: Theme.warning)
            return
        }
        Task {
            var collected: [HealthCheckService.HealthResult] = []
            for token in tokens {
                collected.append(await HealthCheckService.shared.check(token))
            }
            await MainActor.run {
                results = collected
                checking = false
                Haptics.success()
            }
        }
    }

    // MARK: - Duplicates

    private var duplicateCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            cardTitle("重複密鑰", symbol: "square.on.square.dashed")

            Text(L("同一個值存了兩份，通常代表輪換沒做完。"))
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)

            SecondaryButton(title: "掃描", symbol: "magnifyingglass") {
                duplicates = HealthCheckService.findDuplicates(in: vault.activeTokens)
                scanned = true
                Haptics.tap()
            }

            if scanned {
                if duplicates.isEmpty {
                    Text(L("沒有重複的密鑰"))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.success)
                } else {
                    ForEach(Array(duplicates.enumerated()), id: \.offset) { _, pair in
                        HStack(spacing: 6) {
                            Text(pair.0.name)
                                .font(Theme.callout)
                                .foregroundStyle(Theme.textPrimary)
                            Image(systemName: "equal")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.textTertiary)
                            Text(pair.1.name)
                                .font(Theme.callout)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .cardSurface(padding: Theme.Space.m)
    }

    // MARK: - Shared bits

    private func cardTitle(_ title: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(L(title))
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
    }
}
