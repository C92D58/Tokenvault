import SwiftUI
import UIKit

/// Add or edit a secret. The field order matches how people actually think about a key:
/// what it is → what it is worth → where it belongs → when it dies.
struct TokenEditorView: View {
    let existing: TokenItem?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var toast: ToastCenter
    @EnvironmentObject private var app: AppState

    @State private var name: String
    @State private var value: String
    @State private var note: String
    @State private var envIndex: Int
    @State private var provider: TokenProvider
    @State private var providerLocked: Bool
    @State private var category: TokenCategory
    @State private var kind: TokenKind
    @State private var tagsText: String
    @State private var hasExpiry: Bool
    @State private var expiresAt: Date
    @State private var groupID: UUID?

    @State private var revealed = false
    @State private var showingNewGroup = false
    @State private var newGroupName = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable { case name, value, note }

    init(existing: TokenItem?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _value = State(initialValue: existing?.decryptedValue() ?? "")
        _note = State(initialValue: existing?.note ?? "")
        _envIndex = State(initialValue: TokenEnvironment.allCases.firstIndex(of: existing?.environment ?? .production) ?? 2)
        _provider = State(initialValue: existing?.provider ?? .custom)
        _providerLocked = State(initialValue: existing != nil)
        _category = State(initialValue: existing?.category ?? .other)
        _kind = State(initialValue: existing?.kind ?? .apiKey)
        _tagsText = State(initialValue: (existing?.tags ?? []).joined(separator: ", "))
        _hasExpiry = State(initialValue: existing?.expiresAt != nil)
        _expiresAt = State(initialValue: existing?.expiresAt ?? Date().addingTimeInterval(60 * 60 * 24 * 30))
        _groupID = State(initialValue: existing?.groupID)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(spacing: Theme.Space.s) {
                        identityCard
                        classificationCard
                        detailsCard
                        PrimaryButton(title: existing == nil ? "加密並儲存" : "儲存變更",
                                      symbol: "lock.fill", action: save)
                            .disabled(!canSave)
                            .opacity(canSave ? 1 : 0.45)
                            .padding(.top, Theme.Space.xs)
                            .accessibilityIdentifier("editor.save")
                    }
                    .padding(.horizontal, Theme.inset)
                    .padding(.top, Theme.Space.xs)
                    .padding(.bottom, Theme.Space.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .onChange(of: name) { _, _ in detectProvider() }
            .onChange(of: value) { _, _ in detectProvider() }
            .navigationTitle(existing == nil ? "新增密鑰" : "編輯密鑰")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("取消")) { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("儲存"), action: save)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canSave ? Theme.accent : Theme.textTertiary)
                        .disabled(!canSave)
                }
            }
            .alert(L("新增群組"), isPresented: $showingNewGroup) {
                TextField(L("群組名稱"), text: $newGroupName)
                Button(L("建立")) {
                    let trimmed = newGroupName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    let group = vault.createGroup(named: trimmed)
                    groupID = group.id
                    newGroupName = ""
                }
                Button(L("取消"), role: .cancel) { newGroupName = "" }
            }
        }
    }

    // MARK: - Cards

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel("密鑰")

            EditorTextField(label: "名稱", placeholder: "例：OpenAI 專案金鑰",
                            text: $name, identifier: "editor.name")
                .focused($focus, equals: .name)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("值"))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    Button {
                        if let pasted = UIPasteboard.general.string {
                            value = pasted
                            Haptics.tap()
                        }
                    } label: {
                        Label(L("貼上"), systemImage: "doc.on.clipboard")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(Theme.Motion.press) { revealed.toggle() }
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("editor.reveal")
                }

                Group {
                    if revealed {
                        TextField(L("貼上或輸入密鑰"), text: $value, axis: .vertical)
                    } else {
                        SecureField(L("貼上或輸入密鑰"), text: $value)
                    }
                }
                .font(Theme.mono)
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(revealed ? 1...6 : 1...1)
                .focused($focus, equals: .value)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.surfaceRaised))
                .accessibilityIdentifier("editor.value")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L("環境"))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                SlidingSegmented(items: TokenEnvironment.allCases.map(\.rawValue), selection: $envIndex)
            }
        }
        .cardSurface(padding: Theme.Space.m)
    }

    private var classificationCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel("分類")

            MenuRow(title: "服務商", symbol: provider.iosSymbol, tint: provider.tint,
                    value: provider.label) {
                Button {
                    providerLocked = false
                    detectProvider()
                } label: {
                    Label(L("自動偵測"), systemImage: "sparkles")
                }
                Divider()
                ForEach(TokenProvider.allCases, id: \.self) { item in
                    Button {
                        provider = item
                        category = item.category
                        providerLocked = true
                    } label: {
                        Label(item.label, systemImage: item.iosSymbol)
                    }
                }
            }

            MenuRow(title: "分類", symbol: category.icon, tint: category.color,
                    value: category.rawValue) {
                ForEach(TokenCategory.allCases, id: \.self) { item in
                    Button(item.rawValue) { category = item }
                }
            }

            MenuRow(title: "格式", symbol: kind.icon, tint: Theme.textSecondary,
                    value: kind.rawValue) {
                ForEach(TokenKind.allCases, id: \.self) { item in
                    Button(item.rawValue) { kind = item }
                }
            }

            MenuRow(title: "群組", symbol: "folder.fill", tint: Theme.textSecondary,
                    value: vault.group(for: groupID)?.name ?? "未分類") {
                Button(L("未分類")) { groupID = nil }
                if !vault.groups.isEmpty { Divider() }
                ForEach(vault.groups) { group in
                    Button(group.name) { groupID = group.id }
                }
                Divider()
                Button {
                    showingNewGroup = true
                } label: {
                    Label(L("新增群組…"), systemImage: "plus")
                }
            }
        }
        .cardSurface(padding: Theme.Space.m)
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel("其他")

            Toggle(isOn: $hasExpiry.animation(Theme.Motion.snap)) {
                Text(L("設定到期日"))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.accent)

            if hasExpiry {
                DatePicker("到期日", selection: $expiresAt, displayedComponents: .date)
                    .font(Theme.callout)
                    .tint(Theme.accent)
            }

            EditorTextField(label: "標籤", placeholder: "以逗號分隔，例：prod, llm",
                            text: $tagsText, identifier: "editor.tags")

            VStack(alignment: .leading, spacing: 6) {
                Text(L("備註"))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                TextField(L("用途、權限範圍、負責人…"), text: $note, axis: .vertical)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2...5)
                    .focused($focus, equals: .note)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.surfaceRaised))
            }
        }
        .cardSurface(padding: Theme.Space.m)
    }

    // MARK: - Behaviour

    private func detectProvider() {
        guard !providerLocked else { return }
        let detected = TokenProvider.detect(from: name, value: value)
        guard detected != .custom else { return }
        provider = detected
        category = detected.category
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard canSave else { return }
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let environment = TokenEnvironment.allCases[envIndex]
        let expiry: Date? = hasExpiry ? expiresAt : nil

        if let token = existing {
            token.name = trimmedName
            token.note = note
            token.environment = environment
            token.provider = provider
            token.category = category
            token.kind = kind
            token.tags = tags
            token.groupID = groupID
            token.expiresAt = expiry
            if value != token.decryptedValue() {
                token.encryptedValue = (try? EncryptionService.encrypt(value)) ?? value
            }
            vault.commitEdits(to: token)
        } else {
            let token = TokenItem(name: trimmedName, plainValue: value, note: note,
                                  environment: environment,
                                  provider: providerLocked ? provider : nil,
                                  category: category, kind: kind, tags: tags,
                                  expiresAt: expiry, groupID: groupID)
            vault.add(token)
        }

        app.refreshReminders()
        toast.show(existing == nil ? "已加密儲存" : "已儲存變更",
                   symbol: "lock.fill", tint: Theme.accent)
        dismiss()
    }
}

// MARK: - Field pieces

private struct EditorTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var identifier: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L(label))
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
            TextField(L(placeholder), text: $text)
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.surfaceRaised))
                .accessibilityIdentifier(identifier ?? label)
        }
    }
}

/// A settings-style row that opens a menu — the value is visible without opening anything.
private struct MenuRow<Content: View>: View {
    let title: String
    let symbol: String
    var tint: Color = Theme.textSecondary
    let value: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.12)))
                Text(L(title))
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("menu.\(title)")
    }
}
