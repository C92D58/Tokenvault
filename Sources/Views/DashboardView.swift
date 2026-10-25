import SwiftUI

// MARK: - Dashboard Bar

struct DashboardBar: View {
    @ObservedObject var store: DataStore
    @Binding var filterExpiringSoon: Bool
    @Binding var filterExpired: Bool
    @State private var appeared = false

    private var stats: (total: Int, expired: Int, expiringSoon: Int, mostUsed: TokenItem?, recent: TokenItem?) {
        let active = store.activeTokens
        let total = active.count
        let expired = active.filter(\.isExpired).count
        let soon = active.filter(\.expiresSoon).count
        let mostUsed = active.max(by: { $0.copyCount < $1.copyCount })
        let recent = active.filter { $0.lastUsedAt != nil }.max(by: { ($0.lastUsedAt ?? .distantPast) < ($1.lastUsedAt ?? .distantPast) })
        return (total, expired, soon, mostUsed, recent)
    }

    var body: some View {
        HStack(spacing: 0) {
            statCell(title: "即將到期", value: "\(stats.expiringSoon)",
                     icon: "clock.badge.exclamationmark",
                     color: stats.expiringSoon > 0 ? .orange : .secondary,
                     isActive: filterExpiringSoon,
                     showDivider: false,
                     action: { filterExpiringSoon.toggle(); filterExpired = false })

            statCell(title: "已過期", value: "\(stats.expired)",
                     icon: "xmark.shield.fill",
                     color: stats.expired > 0 ? .red : .secondary,
                     isActive: filterExpired,
                     action: { filterExpired.toggle(); filterExpiringSoon = false })

            statCell(title: recentLabel, value: recentName,
                     icon: recentIcon,
                     color: recentColor,
                     subtitle: recentSubtitle)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .surface(level: .standard, cornerRadius: 12)
        .shadow(color: DS.Shadow.card.color, radius: DS.Shadow.card.radius, y: DS.Shadow.card.y)
        .padding(.horizontal, 14).padding(.top, 8)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(DS.Animation.spring) {
                appeared = true
            }
        }
    }

    // MARK: - Stat Cell

    private func statCell(title: String, value: String, icon: String,
                          color: Color, subtitle: String? = nil,
                          isActive: Bool = false,
                          showDivider: Bool = true,
                          action: (() -> Void)? = nil) -> some View {
        let content = HStack(spacing: 0) {
            if showDivider {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1, height: 32)
            }

            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(L(title))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
        }

        return Group {
            if let action = action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? color.opacity(0.08) : Color.clear)
                )
                .help("點擊篩選\(title)的 Token")
            } else {
                content
            }
        }
    }

    // MARK: - Recent Helpers

    private var recentLabel: String {
        stats.recent != nil ? "最近使用" : "最常用"
    }

    private var recentName: String {
        if stats.recent != nil {
            return stats.recent!.name
        } else if let most = stats.mostUsed {
            return most.name
        }
        return "—"
    }

    private var recentSubtitle: String {
        if let recent = stats.recent, let lu = recent.lastUsedAt {
            return relativeTime(lu)
        } else if let most = stats.mostUsed {
            return "已使用 \(most.copyCount) 次"
        }
        return "尚無記錄"
    }

    private var recentIcon: String {
        stats.recent != nil ? "clock.arrow.2.circlepath" : (stats.mostUsed != nil ? "flame.fill" : "clock")
    }

    private var recentColor: Color {
        stats.recent != nil ? .blue : (stats.mostUsed != nil ? .orange : .secondary)
    }

    private func relativeTime(_ date: Date) -> String {
        guard Date().timeIntervalSince(date) < 604800 else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

}

// MARK: - Token Generator + JWT Decoder

/// Token Generator + JWT Decoder
enum GenTab: String, CaseIterable {
    case generate, jwt

    var title: String {
        switch self {
        case .generate: return "隨機生成"
        case .jwt: return "JWT 解碼"
        }
    }

    var icon: String {
        switch self {
        case .generate: return "dice"
        case .jwt: return "doc.text.magnifyingglass"
        }
    }
}

struct TokenGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var generatedToken = ""
    @State private var tokenLength = 32
    @State private var includeSpecial = true
    @State private var jwtInput = ""
    @State private var jwtOutput = ""
    @State private var genTab: GenTab = .generate
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Token 工具箱", systemImage: "wand.and.stars")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            Divider()

            VStack(spacing: 0) {
                PillTabBar(
                    items: GenTab.allCases,
                    title: \.title,
                    icon: \.icon,
                    selection: $genTab
                )
                Divider().opacity(0.5)
                Group {
                    switch genTab {
                    case .generate: generateTab
                    case .jwt: jwtTab
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 460, minHeight: 360)
        .frame(width: 480, height: 400)
    }

    // MARK: - Generate Tab

    private var generateTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Token 長度").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                Picker("", selection: $tokenLength) {
                    Text("16").tag(16)
                    Text("32").tag(32)
                    Text("48").tag(48)
                    Text("64").tag(64)
                }
                .pickerStyle(.segmented)
            }

            Toggle(isOn: $includeSpecial) {
                Label("包含特殊字元 (!@#$%^&*)", systemImage: "textformat.alt")
                    .font(.system(size: 12))
            }

            HStack {
                Button {
                    generateToken()
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                } label: {
                    Label("產生", systemImage: "wand.and.stars")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 16).padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    generatedToken = ""
                } label: {
                    Text("清除").font(.system(size: 11))
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(generatedToken.isEmpty)
            }

            if !generatedToken.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    VStack(spacing: 6) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(generatedToken)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(12)
                        }
                        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                        .frame(maxWidth: .infinity)
                    }

                    HStack(spacing: 8) {
                        Button {
                            ClipboardService.shared.copy(generatedToken, clearAfter: TimeInterval(SettingsService.shared.clipboardClearSeconds))
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                            withAnimation(.spring(response: 0.3)) { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { copied = false } }
                        } label: {
                            Label(copied ? "已複製" : "複製到剪貼板", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(copied ? Color.green.opacity(0.12) : Color.accentColor.opacity(0.1)))
                                .foregroundColor(copied ? .green : .accentColor)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text("\(generatedToken.count) 字元")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - JWT Tab

    private var jwtTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("貼上 JWT Token").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                TextEditor(text: $jwtInput)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(height: 50)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.10), lineWidth: 1))
            }

            HStack {
                Button {
                    decodeJWT()
                } label: {
                    Label("解碼", systemImage: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(jwtInput.trimmingCharacters(in: .whitespaces).isEmpty)

                Button {
                    jwtInput = ""; jwtOutput = ""
                } label: {
                    Text("清除").font(.system(size: 11))
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(jwtInput.isEmpty && jwtOutput.isEmpty)
            }

            if !jwtOutput.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("解碼結果").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)

                    ScrollView {
                        Text(jwtOutput)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 160)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.10), lineWidth: 1))
                }
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func generateToken() {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            + (includeSpecial ? "!@#$%^&*()-_=+[]{}|;:,.<>?" : "")
        generatedToken = String((0..<tokenLength).map { _ in chars.randomElement()! })
    }

    private func decodeJWT() {
        let parts = jwtInput.components(separatedBy: ".")
        guard parts.count == 3 else {
            jwtOutput = "❌ 無效的 JWT 格式（應為 header.payload.signature）"
            return
        }
        var output = ""
        for (i, part) in parts.enumerated() {
            let label = ["HEADER", "PAYLOAD", "SIGNATURE"][i]
            if i < 2, let decoded = decodeBase64URL(part),
               let obj = try? JSONSerialization.jsonObject(with: decoded),
               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: pretty, encoding: .utf8) {
                output += "═══ \(label) ═══\n\(str)\n\n"
            } else {
                output += "═══ \(label) ═══\n\(part.count > 50 ? part.prefix(50) + "..." : part)\n\n"
            }
        }
        jwtOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeBase64URL(_ str: String) -> Data? {
        var base64 = str.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)
    }
}
