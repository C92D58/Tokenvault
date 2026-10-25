import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsService.shared
    @ObservedObject private var backupService = ICloudBackupService.shared
    @ObservedObject private var syncService = ICloudSyncService.shared
    @State private var showGHSetup = false
    @State private var ghToken = ""
    @State private var syncing = false
    @State private var syncMessage = ""
    @State var showingRestore = false
    @State private var selectedTab: SettingsTab = .general

    private enum SettingsTab: Hashable { case general, sync, security, log }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab.tabItem { Label("一般", systemImage: "gearshape") }.tag(SettingsTab.general)
            syncTab.tabItem { Label("同步", systemImage: "arrow.triangle.capsulepath") }.tag(SettingsTab.sync)
            securityTab.tabItem { Label("安全", systemImage: "lock.shield") }.tag(SettingsTab.security)
            logTab.tabItem { Label("記錄", systemImage: "list.bullet.rectangle") }.tag(SettingsTab.log)
        }
        .frame(minWidth: 500, minHeight: 500)
        .onReceive(NotificationCenter.default.publisher(for: .showSettingsSyncTab)) { _ in
            selectedTab = .sync
        }
    }

    // MARK: - General

    private var generalTab: some View {
        ScrollView {
            Form {
                Section {
                    Picker("外觀", selection: $settings.appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: settings.appearanceMode) { _, _ in settings.applyAppearance() }
                } header: {
                    Text("外觀").font(.system(size: 11, weight: .semibold))
                }

                Section {
                    Toggle("自動鎖定", isOn: $settings.autoLockEnabled)
                    if settings.autoLockEnabled {
                        Picker("閒置鎖定", selection: $settings.autoLockSeconds) {
                            Text("30 秒").tag(30)
                            Text("1 分鐘").tag(60)
                            Text("5 分鐘").tag(300)
                            Text("15 分鐘").tag(900)
                        }
                    }
                } header: {
                    Text("隱私").font(.system(size: 11, weight: .semibold))
                }

                Section {
                    Picker("剪貼板清空", selection: $settings.clipboardClearSeconds) {
                        Text("15 秒").tag(15)
                        Text("30 秒").tag(30)
                        Text("45 秒").tag(45)
                        Text("永不").tag(0)
                    }
                } header: {
                    Text("剪貼板").font(.system(size: 11, weight: .semibold))
                }
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - Sync

    private var syncTab: some View {
        ScrollView {
            Form {
                Section {
                    Text("Vault 存在 App 的 Application Support 目錄，整份以 AES-256-GCM 加密。跨裝置還原請用下方 iCloud 備份或「匯出加密備份」。")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                } header: {
                    Text("本機儲存").font(.system(size: 11, weight: .semibold))
                }

                Section {
                    Toggle("iCloud 同步", isOn: $settings.iCloudSyncEnabled)
                        .onChange(of: settings.iCloudSyncEnabled) { _, on in
                            syncService.isEnabled = on
                            backupService.refreshStatus(enabled: on)
                            if on {
                                syncService.activate()
                            } else {
                                syncService.deactivate()
                            }
                        }
                        .onAppear {
                            syncService.isEnabled = settings.iCloudSyncEnabled
                            backupService.refreshStatus(enabled: settings.iCloudSyncEnabled)
                        }

                    Text(syncService.statusText)
                        .font(.system(size: 10))
                        .foregroundColor(syncFailed ? .red : .secondary)

                    HStack(spacing: 8) {
                        Button(syncService.state == .syncing ? "同步中…" : "立即同步") {
                            syncService.requestSyncNow()
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(!settings.iCloudSyncEnabled)

                        Button("從備份還原…") { showingRestore = true }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(!settings.iCloudSyncEnabled || !backupService.isAvailable)

                        Button(syncService.isUsingCustomFolder ? "更改資料夾…" : "選擇資料夾…") {
                            chooseSyncFolder()
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(!settings.iCloudSyncEnabled || !syncService.isAvailable)

                        if syncService.isUsingCustomFolder {
                            Button("改用 App 容器") {
                                syncService.clearCustomFolder()
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }

                        Button("在 Finder 中顯示") {
                            // Apple hides app containers from Finder's iCloud 雲盤 unless the app is
                            // document-based, so give the folder a way to be seen and inspected.
                            guard let file = ICloudSyncService.shared.fileURL else { return }
                            let url = FileManager.default.fileExists(atPath: file.path)
                                ? file : file.deletingLastPathComponent()
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(!settings.iCloudSyncEnabled || !syncService.isAvailable)
                    }
                    .sheet(isPresented: $showingRestore) { restoreSheet }

                    Text("整份加密後寫入 iCloud Drive/TokenVault/vault.tvsync：同一 Apple ID 的 Mac 與 iPhone 自動雙向合併，逐筆以修改時間為準。金鑰存在 iCloud 鑰匙圈，加密備份另保留最近 7 份。這是 App 專屬容器，用「在 Finder 中顯示」可直接打開。")
                        .font(.system(size: 10)).foregroundColor(.secondary)

                    Text(locationLine)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                } header: {
                    Text("iCloud".uppercased()).font(.system(size: 11, weight: .semibold))
                }

                Section {
                    Toggle("GitHub 備份", isOn: $settings.githubSyncEnabled)
                    if settings.githubSyncEnabled {
                        TextField("倉庫 (user/repo)", text: $settings.githubRepo)
                            .textFieldStyle(.roundedBorder).font(.system(size: 12))
                            .frame(width: 200)

                        HStack {
                            Button("設定 Token") { showGHSetup = true }
                                .buttonStyle(.bordered).controlSize(.small)
                            if !syncMessage.isEmpty {
                                Text(syncMessage)
                                    .font(.system(size: 10))
                                    .foregroundColor(syncMessage.contains("✅") ? .green : .red)
                            }
                        }

                        Button {
                            syncToGitHub()
                        } label: {
                            Label(syncing ? "同步中..." : "立即同步", systemImage: "arrow.triangle.capsulepath")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(syncing || settings.githubRepo.isEmpty)

                        Text("Token 已 AES-256 加密，即使 GitHub 倉庫公開也無法被讀取。")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                } header: {
                    Text("GitHub").font(.system(size: 11, weight: .semibold))
                }
            }
            .formStyle(.grouped)
        }
        .sheet(isPresented: $showGHSetup) {
            VStack(spacing: 18) {
                Text("GitHub Token").font(.system(size: 15, weight: .bold))
                Text("需要 repo 寫入權限").font(.system(size: 11)).foregroundColor(.secondary)
                SecureField("ghp_...", text: $ghToken)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                HStack {
                    Button("取消") { showGHSetup = false }
                    Button("儲存") {
                        let tag = "org.wahsun.tokenvault.ghtoken".data(using: .utf8)!
                        try? KeychainService.write(tag: tag, data: Data(ghToken.utf8))
                        showGHSetup = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ghToken.isEmpty)
                }
            }
            .padding().frame(width: 320, height: 200)
        }
    }

    // MARK: - Security

    private var securityTab: some View {
        ScrollView {
            Form {
                Section {
                    HStack {
                        Text("加密狀態")
                        Spacer()
                        Label("AES-256-GCM", systemImage: "checkmark.shield.fill")
                            .font(.system(size: 11)).foregroundColor(.green)
                    }
                    HStack {
                        Text("主密鑰")
                        Spacer()
                        Label("Secure Enclave", systemImage: "checkmark.shield.fill")
                            .font(.system(size: 11)).foregroundColor(.green)
                    }
                    HStack {
                        Text("儲存位置")
                        Spacer()
                        Text("本機")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                } header: {
                    Text("安全資訊").font(.system(size: 11, weight: .semibold))
                }

                Section {
                    Button("匯出加密備份 (JSON)") { exportBackup(format: "json") }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("匯出 .env") { exportBackup(format: "env") }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("匯出 CSV") { exportBackup(format: "csv") }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("匯入備份") { importBackup() }
                        .buttonStyle(.bordered).controlSize(.small)
                } header: {
                    Text("備份").font(.system(size: 11, weight: .semibold))
                }
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - Security Log

    private var logTab: some View {
        @ObservedObject var logService = SecurityLogService.shared

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if logService.entries.isEmpty {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 60)
                        Image(systemName: "list.bullet.rectangle").font(.system(size: 28)).foregroundColor(.secondary.opacity(0.3))
                        Text("尚無操作記錄").font(.system(size: 13)).foregroundColor(.secondary)
                        Text("所有 Token 操作將自動記錄於此").font(.system(size: 11)).foregroundColor(.secondary.opacity(0.5))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(logService.entries.prefix(50)) { entry in
                        HStack(spacing: 10) {
                            Image(systemName: entry.action.icon)
                                .font(.system(size: 11))
                                .foregroundColor(entry.action == .copied ? .blue : .secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(L(entry.action.rawValue)) · \(entry.tokenName) · \(L(entry.provider))").font(.system(size: 12))
                                Text("\(entry.provider) · \(entry.relativeTime)")
                                    .font(.system(size: 10)).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Sync location

    private var locationLine: String {
        if syncService.isUsingCustomFolder {
            let path = syncService.customFolderDisplayPath ?? ""
            return L("位置：%@/TokenVault（iCloud 雲盤，Finder 與檔案 App 都看得到）", path)
        }
        return L("位置：App 容器（Finder 的 iCloud 雲盤不一定會列出，用上面的按鈕打開）")
    }

    /// iCloud Drive proper needs a user grant: a sandboxed app cannot write there on its own.
    private func chooseSyncFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L("使用這個資料夾")
        panel.message = L("選擇 iCloud 雲盤裡的資料夾；TokenVault 會在裡面建立 TokenVault/vault.tvsync")
        panel.directoryURL = FileManager.default
            .url(forUbiquityContainerIdentifier: ICloudSyncService.containerIdentifier)?
            .deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try syncService.setCustomFolder(url)
        } catch {
            NSSound.beep()
            print("[sync] could not store the bookmark: \(error.localizedDescription)")
        }
    }

    // MARK: - Actions

    private func syncToGitHub() {
        syncing = true; syncMessage = ""
        let repo = settings.githubRepo.trimmingCharacters(in: .whitespaces)
        guard !repo.isEmpty else { syncMessage = "請輸入倉庫"; syncing = false; return }

        Task.detached {
            let tag = "org.wahsun.tokenvault.ghtoken".data(using: .utf8)!
            guard let ghData = try? KeychainService.read(tag: tag),
                  let ghToken = String(data: ghData, encoding: .utf8) else {
                await MainActor.run { syncMessage = "請先設定 GitHub Token"; syncing = false }
                return
            }

            guard let d = await MainActor.run(body: { NSApp.delegate as? AppDelegate }) else { return }
            let snap = DataStore.BackupSnapshot(groups: d.store.groups, tokens: d.store.activeTokens)
            let content = (try? JSONEncoder().encode(snap))?.base64EncodedString() ?? ""

            guard let url = URL(string: "https://api.github.com/repos/\(repo)/contents/tokenvault-backup.json") else {
                await MainActor.run { syncMessage = "❌ 無效的倉庫名稱"; syncing = false }
                return
            }
            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            req.setValue("Bearer \(ghToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("TokenVault", forHTTPHeaderField: "User-Agent")
            req.httpBody = try? JSONSerialization.data(withJSONObject: [
                "message": "TokenVault 備份 \(Date().formatted(date: .abbreviated, time: .shortened))",
                "content": content
            ])

            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let ok = json?["content"] != nil || json?["commit"] != nil
                await MainActor.run { syncMessage = ok ? "✅ 同步完成" : "❌ 同步失敗"; syncing = false }
            } catch {
                await MainActor.run { syncMessage = "❌ \(error.localizedDescription)"; syncing = false }
            }
        }
    }

    private func exportBackup(format: String = "json") {
        guard let d = NSApp.delegate as? AppDelegate else { return }
        let tokens = d.store.activeTokens
        let savePanel = NSSavePanel()

        switch format {
        case "env":
            savePanel.nameFieldStringValue = "tokenvault-\(Date().formatted(date: .abbreviated, time: .omitted)).env"
            savePanel.allowedContentTypes = [.plainText]
            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    let content = ImportExportHelper.exportEnv(tokens)
                    try? content.write(to: url, atomically: true, encoding: .utf8)
                }
            }
        case "csv":
            savePanel.nameFieldStringValue = "tokenvault-\(Date().formatted(date: .abbreviated, time: .omitted)).csv"
            savePanel.allowedContentTypes = [.commaSeparatedText]
            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    let content = ImportExportHelper.exportCSV(tokens)
                    try? content.write(to: url, atomically: true, encoding: .utf8)
                }
            }
        default:
            savePanel.nameFieldStringValue = "tokenvault-backup-\(Date().formatted(date: .abbreviated, time: .omitted)).json"
            savePanel.allowedContentTypes = [.json]
            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    let snap = DataStore.BackupSnapshot(groups: d.store.groups, tokens: d.store.allTokens)
                    if let data = try? JSONEncoder().encode(snap) { try? data.write(to: url) }
                }
            }
        }
    }

    private func importBackup() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.begin { response in
            guard response == .OK, let url = openPanel.url,
                  let data = try? Data(contentsOf: url) else { return }
            DispatchQueue.main.async {
                guard let d = NSApp.delegate as? AppDelegate,
                      let snap = try? JSONDecoder().decode(DataStore.BackupSnapshot.self, from: data) else { return }
                let existingIDs = Set(d.store.allTokens.map(\.id))
                for token in snap.tokens where !existingIDs.contains(token.id) {
                    d.store.addToken(token, to: nil)
                }
                let existingGroupIDs = Set(d.store.groups.map(\.id))
                for group in snap.groups where !existingGroupIDs.contains(group.id) {
                    d.store.groups.append(group)
                }
                d.store.save()
            }
        }
    }
}

// MARK: - iCloud restore

extension SettingsView {
    var liveStore: DataStore? { (NSApp.delegate as? AppDelegate)?.store }

    var backupFailed: Bool {
        if case .failed = backupService.status { return true }
        return false
    }

    var syncFailed: Bool {
        if case .failed = syncService.state { return true }
        if case .unavailable = syncService.state { return true }
        return false
    }

    var restoreSheet: some View {
        let snapshots = backupService.snapshots()
        return VStack(alignment: .leading, spacing: 12) {
            Text("從 iCloud 還原").font(.system(size: 15, weight: .bold))
            Text("只會補上缺少的 Token，不會覆蓋現有資料。")
                .font(.system(size: 11)).foregroundColor(.secondary)

            if snapshots.isEmpty {
                Text("沒有可用的備份")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(snapshots, id: \.url) { snap in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Self.snapshotFormatter.string(from: snap.createdAt))
                                        .font(.system(size: 12, weight: .medium))
                                    Text("\(snap.tokens.count) 個 Token")
                                        .font(.system(size: 10)).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("還原") { restore(from: snap) }
                                    .buttonStyle(.borderedProminent).controlSize(.small)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            HStack {
                Spacer()
                Button("關閉") { showingRestore = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 430)
    }

    private func restore(from snapshot: ICloudBackupService.Snapshot) {
        guard let store = liveStore else { return }
        let existing = Set(store.allTokens.map(\.id))
        for token in snapshot.tokens where !existing.contains(token.id) {
            let group = store.groups.first { $0.id == token.groupID }
            store.addToken(token, to: group)
        }
        store.save()
        showingRestore = false
    }

    private static let snapshotFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d HH:mm"
        return f
    }()
}
