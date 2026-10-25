import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var toast: ToastCenter
    @ObservedObject private var icloudBackup = ICloudBackupService.shared
    @ObservedObject private var icloudSync = ICloudSyncService.shared

    @State private var showingImport = false
    @State private var showingTrash = false
    @State private var showingExporter = false
    @State private var exportFormat: VaultStore.ExportFormat = .encryptedJSON
    @State private var exportDocument: ExportDocument?

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(spacing: Theme.Space.m) {
                        header
                        appearanceCard
                        securityCard
                        dataCard
                        aboutCard
                        footnote
                    }
                    .padding(.horizontal, Theme.inset)
                    .padding(.bottom, 110)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showingImport) { ImportSheet() }
        .sheet(isPresented: $showingTrash) { TrashView() }
        .fileExporter(isPresented: $showingExporter,
                      document: exportDocument,
                      contentType: exportFormat == .encryptedJSON ? .json : .plainText,
                      defaultFilename: exportFormat.filename) { result in
            switch result {
            case .success:
                toast.show("已匯出 \(exportFormat.label)", symbol: "square.and.arrow.up", tint: Theme.accent)
            case .failure(let error):
                toast.show("匯出失敗：\(error.localizedDescription)",
                           symbol: "exclamationmark.triangle.fill", tint: Theme.danger)
            }
            exportDocument = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("設定")
                .font(Theme.title)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("settings.title")
            Text("裝置、安全與資料")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Space.s)
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel("外觀")
            SlidingSegmented(items: AppearanceMode.allCases.map(\.label),
                             selection: Binding(
                                get: { AppearanceMode.allCases.firstIndex(of: settings.appearance) ?? 0 },
                                set: { settings.appearance = AppearanceMode.allCases[$0] }))
        }
        .cardSurface(padding: Theme.Space.m)
    }

    // MARK: - Security

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel("安全")

            SettingsRow(symbol: app.auth.symbol, title: "生物辨識解鎖",
                        detail: app.auth.isAvailable ? L("使用 %@ 或裝置密碼", app.auth.label) : L("尚未設定裝置密碼")) {
                Toggle("", isOn: $settings.biometricLock)
                    .labelsHidden()
                    .tint(Theme.accent)
                    .accessibilityIdentifier("settings.biometric")
            }

            Menu {
                ForEach(SettingsStore.autoLockChoices, id: \.seconds) { choice in
                    Button(choice.label) { settings.autoLockSeconds = choice.seconds }
                }
            } label: {
                SettingsRow(symbol: "lock.badge.clock", title: "離開後自動鎖定",
                            detail: "從背景回來時重新驗證") {
                    MenuValue(text: settings.autoLockLabel)
                }
            }
            .accessibilityIdentifier("settings.autolock")

            Menu {
                ForEach(SettingsStore.clipboardChoices, id: \.seconds) { choice in
                    Button(choice.label) { settings.clipboardClearSeconds = choice.seconds }
                }
            } label: {
                SettingsRow(symbol: "doc.on.clipboard", title: "剪貼板自動清除",
                            detail: "複製密鑰後自動清空") {
                    MenuValue(text: settings.clipboardLabel)
                }
            }
            .accessibilityIdentifier("settings.clipboard")

            SettingsRow(symbol: "bell.badge", title: "到期提醒",
                        detail: "到期前一天發送本機通知") {
                Toggle("", isOn: $settings.expiryReminders)
                    .labelsHidden()
                    .tint(Theme.accent)
                    .onChange(of: settings.expiryReminders) { _, isOn in
                        if isOn {
                            NotificationService.requestPermission()
                            app.refreshReminders()
                        }
                    }
            }

            Button {
                app.lock()
                toast.show("已鎖定", symbol: "lock.fill", tint: Theme.accent)
            } label: {
                SettingsRow(symbol: "lock.fill", title: "立即鎖定", tint: Theme.danger) {
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.lock")
        }
        .cardSurface(padding: Theme.Space.m)
    }

    // MARK: - Data

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel("資料")

            Button {
                showingImport = true
            } label: {
                SettingsRow(symbol: "square.and.arrow.down", title: "匯入密鑰",
                            detail: ".env · CSV · JSON 備份") {
                    Chevron()
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.import")

            Menu {
                ForEach(VaultStore.ExportFormat.allCases) { format in
                    Button {
                        prepareExport(format)
                    } label: {
                        Label(format.isPlaintext ? "\(format.label)（明文）" : format.label,
                              systemImage: format.isPlaintext ? "exclamationmark.triangle" : "lock.doc")
                    }
                }
            } label: {
                SettingsRow(symbol: "square.and.arrow.up", title: "匯出",
                            detail: vault.activeTokens.isEmpty ? L("尚無密鑰") : L("%lld 個密鑰", vault.activeTokens.count)) {
                    MenuValue(text: "選擇格式")
                }
            }
            .accessibilityIdentifier("settings.export")

            Button {
                showingTrash = true
            } label: {
                SettingsRow(symbol: "trash", title: "垃圾桶",
                            detail: vault.trashedTokens.isEmpty ? "空" : "\(vault.trashedTokens.count) 個項目 · 30 天後自動清除") {
                    Chevron()
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.trash")

            SettingsRow(symbol: "internaldrive", title: "儲存位置",
                        detail: "本機加密儲存；iCloud 另存加密同步檔") {
                Text("本機")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            SettingsRow(symbol: "icloud", title: "iCloud 同步",
                        detail: icloudSync.statusText) {
                Toggle("", isOn: $settings.iCloudSync)
                    .labelsHidden()
                    .tint(Theme.accent)
                    .onChange(of: settings.iCloudSync) { _, isOn in
                        ICloudSyncService.shared.isEnabled = isOn
                        icloudBackup.refreshStatus(enabled: isOn)
                        if isOn {
                            ICloudSyncService.shared.activate()
                        } else {
                            ICloudSyncService.shared.deactivate()
                        }
                    }
            }
            .accessibilityIdentifier("settings.icloud")
            .onAppear {
                ICloudSyncService.shared.isEnabled = settings.iCloudSync
                icloudBackup.refreshStatus(enabled: settings.iCloudSync)
            }

            if settings.iCloudSync {
                Button {
                    ICloudSyncService.shared.requestSyncNow()
                    toast.show("同步中…", symbol: "arrow.triangle.2.circlepath", tint: Theme.accent)
                } label: {
                    SettingsRow(symbol: "arrow.triangle.2.circlepath", title: "立即同步",
                                detail: "與 iCloud 上的其他裝置合併") {
                        Text("同步")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.syncNow")
            }
        }
        .cardSurface(padding: Theme.Space.m)
    }

    private func prepareExport(_ format: VaultStore.ExportFormat) {
        guard !vault.activeTokens.isEmpty else {
            toast.show("沒有可匯出的密鑰", symbol: "questionmark.circle", tint: Theme.warning)
            return
        }
        exportFormat = format
        exportDocument = ExportDocument(data: vault.exportData(format))
        showingExporter = true
        SecurityLogService.shared.log(.exported, tokenID: UUID(), name: format.label, provider: "匯出")
    }

    // MARK: - About

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel("關於")

            HStack(spacing: Theme.Space.s) {
                Image("AppMark")
                    .resizable()
                    .frame(width: Theme.IconSize.badge + 4, height: Theme.IconSize.badge + 4)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.hairlineStrong, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TokenVault")
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("iOS \(version)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(.bottom, 2)

            Link(destination: URL(string: "https://wahsun.org")!) {
                SettingsRow(symbol: "person.crop.circle", title: "開發者", detail: "WAHSUN") {
                    Chevron()
                }
            }
            .buttonStyle(.plain)

            Link(destination: URL(string: "https://privacy.wahsun.org/")!) {
                SettingsRow(symbol: "hand.raised", title: "隱私政策", detail: "privacy.wahsun.org") {
                    Chevron()
                }
            }
            .buttonStyle(.plain)
        }
        .cardSurface(padding: Theme.Space.m)
    }

    private var footnote: some View {
        VStack(spacing: 4) {
            Text("零知識：Token 值以 AES-256-GCM 加密後才寫入磁碟，金鑰存放於這台裝置的鑰匙圈。")
            Text("沒有伺服器、沒有分析、沒有任何追蹤。")
        }
        .font(Theme.caption)
        .foregroundStyle(Theme.textTertiary)
        .multilineTextAlignment(.center)
        .padding(.top, Theme.Space.xs)
    }
}

// MARK: - Small pieces

private struct MenuValue: View {
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Text(L(text))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

private struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
    }
}

/// Wraps exported bytes for `.fileExporter`.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText, .commaSeparatedText] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
