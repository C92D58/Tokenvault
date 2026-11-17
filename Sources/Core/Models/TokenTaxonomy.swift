import SwiftUI

// MARK: - Token Taxonomy
//
// 單一來源的 Token 分類系統，取代過去重疊的 TokenType / SecretProvider /
// SecretCategory / SecretType 四套分類。
//
//   TokenProvider  — 簽發服務（GitHub、OpenAI、AWS…）→ 品牌圖示、顏色、控台網址
//   TokenCategory  — 側欄功能分組（AI、雲端、資料庫…）
//   TokenKind      — 憑證格式（API 金鑰、OAuth、SSH 私鑰…）

// MARK: - Token Category

/// 功能分組，用於側欄分類。
enum TokenCategory: String, Codable, CaseIterable {
    case ai = "人工智慧"
    case cloud = "雲端服務"
    case database = "資料庫"
    case social = "社群通訊"
    case payment = "金流支付"
    case ssh = "SSH 金鑰"
    case jwt = "JWT 權杖"
    case certificate = "憑證"
    case server = "伺服器"
    case other = "其他"

    var emoji: String {
        switch self {
        case .ai: return "🤖"
        case .cloud: return "☁️"
        case .database: return "🗄️"
        case .social: return "💬"
        case .payment: return "💳"
        case .ssh: return "🔑"
        case .jwt: return "🎫"
        case .certificate: return "📜"
        case .server: return "🖥️"
        case .other: return "📦"
        }
    }

    /// Localized label. `rawValue` is both the lookup key and the persisted value, so the
    /// Chinese source string doubles as the key for `Localizable.strings`.
    var displayName: String { L(rawValue) }
    var icon: String {
        switch self {
        case .ai: return "brain.head.profile"
        case .cloud: return "cloud.fill"
        case .database: return "cylinder.fill"
        case .social: return "bubble.left.and.bubble.right.fill"
        case .payment: return "creditcard.fill"
        case .ssh: return "key.fill"
        case .jwt: return "ticket.fill"
        case .certificate: return "seal.fill"
        case .server: return "server.rack"
        case .other: return "archivebox.fill"
        }
    }

    var color: Color {
        switch self {
        case .ai: return Color(red: 0.06, green: 0.64, blue: 0.50)       // teal
        case .cloud: return Color(red: 0.95, green: 0.50, blue: 0.13)      // orange
        case .database: return Color(red: 0.23, green: 0.51, blue: 0.96)   // blue
        case .social: return Color(red: 0.91, green: 0.27, blue: 0.48)     // rose
        case .payment: return Color(red: 0.94, green: 0.40, blue: 0.31)    // coral
        case .ssh: return Color(red: 0.13, green: 0.72, blue: 0.66)        // brand cyan
        case .jwt: return Color(red: 0.96, green: 0.62, blue: 0.04)        // amber
        case .certificate: return Color(red: 0.20, green: 0.78, blue: 0.35) // green
        case .server: return Color(red: 0.42, green: 0.45, blue: 0.50)     // gray
        case .other: return Color(red: 0.61, green: 0.64, blue: 0.69)      // light gray
        }
    }
}

// MARK: - Token Kind

/// 憑證格式。
enum TokenKind: String, Codable, CaseIterable {
    case apiKey = "API 金鑰"
    case oauth = "OAuth 權杖"
    case sshKey = "SSH 私鑰"
    case jwt = "JWT 權杖"
    case cookie = "Cookie 憑證"
    case license = "軟體授權"
    case webhook = "Webhook 密鑰"
    case certificate = "數位憑證"
    case wireguard = "WireGuard 設定"
    case other = "其他"

    /// Localized label. `rawValue` is both the lookup key and the persisted value, so the
    /// Chinese source string doubles as the key for `Localizable.strings`.
    var displayName: String { L(rawValue) }
    var icon: String {
        switch self {
        case .apiKey: return "key.horizontal.fill"
        case .oauth: return "person.badge.key.fill"
        case .sshKey: return "key.fill"
        case .jwt: return "ticket.fill"
        case .cookie: return "circle.hexagongrid.fill"
        case .license: return "doc.text.fill"
        case .webhook: return "antenna.radiowaves.left.and.right"
        case .certificate: return "seal.fill"
        case .wireguard: return "point.3.connected.trianglepath.dotted"
        case .other: return "questionmark.square.fill"
        }
    }
}

// MARK: - Token Provider

/// 簽發服務，Token 的品牌識別來源（圖示、顏色、控台網址）。
enum TokenProvider: String, Codable, CaseIterable {
    case openai = "OpenAI"
    case claude = "Claude"
    case gemini = "Gemini"
    case deepseek = "DeepSeek"
    case github = "GitHub"
    case gitlab = "GitLab"
    case aws = "AWS"
    case azure = "Azure"
    case google = "Google Cloud"
    case cloudflare = "Cloudflare"
    case telegram = "Telegram"
    case discord = "Discord"
    case slack = "Slack"
    case stripe = "Stripe"
    case tailscale = "Tailscale"
    case apple = "Apple"
    case docker = "Docker"
    case vercel = "Vercel"
    case supabase = "Supabase"
    case huggingface = "HuggingFace"
    case custom = "自訂"

    /// 顯示名稱。
    var displayName: String { L(rawValue) }
    var label: String { displayName }

    var icon: String {
        switch self {
        case .openai: return "brain.fill"
        case .claude: return "sparkles"
        case .gemini: return "star.fill"
        case .deepseek: return "magnifyingglass.circle.fill"
        case .github: return "cat.fill"
        case .gitlab: return "fox"
        case .aws: return "cloud.fill"
        case .azure: return "building.2.fill"
        case .google: return "g.circle.fill"
        case .cloudflare: return "globe"
        case .telegram: return "paperplane.fill"
        case .discord: return "message.fill"
        case .slack: return "tag.fill"
        case .stripe: return "creditcard.fill"
        case .tailscale: return "point.3.connected.trianglepath.dotted"
        case .apple: return "apple.logo"
        case .docker: return "shippingbox.fill"
        case .vercel: return "triangle.fill"
        case .supabase: return "cylinder.fill"
        case .huggingface: return "face.smiling.fill"
        case .custom: return "questionmark.square.fill"
        }
    }

    /// 品牌色（單一正規 hex，明暗模式皆可讀）。
    var color: String {
        switch self {
        case .openai: return "#10A37F"
        case .claude: return "#D97706"
        case .gemini: return "#4285F4"
        case .deepseek: return "#4F46E5"
        case .github: return "#7C5CBF"
        case .gitlab: return "#E05D2E"
        case .aws: return "#E68A00"
        case .azure: return "#0078D4"
        case .google: return "#4285F4"
        case .cloudflare: return "#E07520"
        case .telegram: return "#26A5E4"
        case .discord: return "#5865F2"
        case .slack: return "#6E34B8"
        case .stripe: return "#5850D8"
        case .tailscale: return "#6B7280"
        case .apple: return "#555555"
        case .docker: return "#2496ED"
        case .vercel: return "#4B5563"
        case .supabase: return "#3ECF8E"
        case .huggingface: return "#E0B800"
        case .custom: return "#9CA3AF"
        }
    }

    /// 預設功能分組。
    var category: TokenCategory {
        switch self {
        case .openai, .claude, .gemini, .deepseek, .huggingface: return .ai
        case .aws, .azure, .google, .cloudflare, .vercel: return .cloud
        case .supabase: return .database
        case .telegram, .discord, .slack: return .social
        case .stripe: return .payment
        case .tailscale: return .server
        case .github, .gitlab, .docker, .apple: return .other
        case .custom: return .other
        }
    }

    /// 服務控台 / 憑證管理網址。
    var serviceURL: URL? {
        switch self {
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .claude: return URL(string: "https://console.anthropic.com/keys")
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .deepseek: return URL(string: "https://platform.deepseek.com/api_keys")
        case .github: return URL(string: "https://github.com/settings/tokens")
        case .gitlab: return URL(string: "https://gitlab.com/-/user_settings/personal_access_tokens")
        case .aws: return URL(string: "https://console.aws.amazon.com/iam/home#/security_credentials")
        case .azure: return URL(string: "https://portal.azure.com/#view/Microsoft_AAD_IAM/TenantOverview.ReactView")
        case .google: return URL(string: "https://console.cloud.google.com/apis/credentials")
        case .cloudflare: return URL(string: "https://dash.cloudflare.com/profile/api-tokens")
        case .telegram: return URL(string: "https://t.me/BotFather")
        case .discord: return URL(string: "https://discord.com/developers/applications")
        case .slack: return URL(string: "https://api.slack.com/apps")
        case .stripe: return URL(string: "https://dashboard.stripe.com/apikeys")
        case .tailscale: return URL(string: "https://login.tailscale.com/admin/settings/keys")
        case .apple: return URL(string: "https://appstoreconnect.apple.com/access/api")
        case .docker: return URL(string: "https://hub.docker.com/settings/security")
        case .vercel: return URL(string: "https://vercel.com/account/tokens")
        case .supabase: return URL(string: "https://app.supabase.com/account/tokens")
        case .huggingface: return URL(string: "https://huggingface.co/settings/tokens")
        case .custom: return nil
        }
    }

    /// 依名稱 / token 前綴自動偵測服務商。
    static func detect(from name: String, value: String) -> TokenProvider {
        let q = "\(name) \(value.prefix(16))".lowercased()
        if q.contains("sk-") && q.contains("openai") || q.contains("sk-proj-") || q.contains("sk-admin-") { return .openai }
        if q.contains("sk-ant-") || q.contains("claude") || q.contains("anthropic") { return .claude }
        if q.contains("gemini") || q.contains("google") && q.contains("ai") { return .gemini }
        if q.contains("deepseek") { return .deepseek }
        if q.contains("ghp_") || q.contains("github") || q.contains("gho_") || q.contains("ghu_") { return .github }
        if q.contains("glpat-") || q.contains("gitlab") { return .gitlab }
        if q.contains("akia") || q.contains("aws") { return .aws }
        if q.contains("azure") { return .azure }
        if q.contains("cloudflare") || q.contains("cf_") { return .cloudflare }
        if q.contains("hf_") || q.contains("huggingface") { return .huggingface }
        if q.contains("vercel") { return .vercel }
        if q.contains("supabase") || q.contains("sb_") { return .supabase }
        if q.contains("telegram") || q.contains("bot") && q.contains("token") { return .telegram }
        if q.contains("discord") { return .discord }
        if q.contains("xoxb-") || q.contains("slack") { return .slack }
        if q.contains("sk_live") || q.contains("sk_test") || q.contains("stripe") { return .stripe }
        if q.contains("tskey-") || q.contains("tailscale") { return .tailscale }
        if q.contains("apple") || q.contains("appstore") { return .apple }
        if q.contains("docker") { return .docker }
        return .custom
    }

    /// 從舊版 TokenType（lowercase rawValue）遷移對映。
    static func fromLegacyTokenType(_ raw: String) -> TokenProvider {
        switch raw.lowercased() {
        case "google": return .google
        case "other", "": return .custom
        default:
            return TokenProvider.allCases.first { $0.rawValue.lowercased() == raw.lowercased() } ?? .custom
        }
    }
}
