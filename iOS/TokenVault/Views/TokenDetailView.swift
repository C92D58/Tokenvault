import SwiftUI

/// Everything about one secret, in the order a developer asks for it:
/// what is it, what is the value, can I copy it, when does it expire, where does it live.
struct TokenDetailView: View {
    let token: TokenItem

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var toast: ToastCenter

    @State private var revealed = false
    @State private var showingEditor = false
    @State private var confirmTrash = false
    @State private var decoded: JWTDecoder.Decoded?
    @State private var showingJWT = false

    private var isJWT: Bool { JWTDecoder.looksLikeJWT(token.decryptedValue()) }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(spacing: Theme.Space.s) {
                        hero
                        valueCard
                        if isJWT { jwtCard }
                        metaCard
                        if !token.note.isEmpty { noteCard }
                        if !token.tags.isEmpty { tagsCard }
                        actions
                    }
                    .padding(.horizontal, Theme.inset)
                    .padding(.top, Theme.Space.xs)
                    .padding(.bottom, Theme.Space.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("關閉")) { dismiss() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingEditor = true } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("detail.edit")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            TokenEditorView(existing: token)
        }
        .sheet(isPresented: $showingJWT) {
            if let decoded {
                JWTSheet(decoded: decoded)
            }
        }
        .confirmationDialog(L("移到垃圾桶？"), isPresented: $confirmTrash, titleVisibility: .visible) {
            Button(L("移到垃圾桶"), role: .destructive) {
                vault.trash(token)
                dismiss()
                toast.show("已移到垃圾桶", symbol: "trash.fill", tint: Theme.warning)
            }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("30 天內可以從垃圾桶復原。"))
        }
    }

    // MARK: - Pieces

    private var hero: some View {
        HStack(spacing: Theme.Space.m) {
            ProviderBadge(provider: token.provider, size: 54)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(token.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if token.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.warning)
                    }
                }
                HStack(spacing: 6) {
                    EnvBadge(environment: token.environment)
                    Pill(text: token.provider.label, tint: token.provider.tint, filled: false)
                    Pill(text: token.kind.rawValue, tint: Theme.textSecondary, filled: false)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Space.m)
        .padding(.horizontal, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private var valueCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                SectionLabel("密鑰值")
                Spacer()
                Button {
                    Haptics.tap()
                    withAnimation(Theme.Motion.snap) { revealed.toggle() }
                } label: {
                    Label(revealed ? "隱藏" : "顯示", systemImage: revealed ? "eye.slash" : "eye")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("detail.reveal")
            }

            Text(revealed ? token.decryptedValue() : token.maskedPreview)
                .font(Theme.mono)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .lineLimit(revealed ? nil : 1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.surfaceRaised)
                )
                .accessibilityIdentifier("detail.value")

            HStack(spacing: Theme.Space.xs) {
                Button {
                    copy()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "doc.on.doc.fill").font(.system(size: 13, weight: .semibold))
                        Text(L("複製密鑰")).font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Theme.accentGradient))
                }
                .pressable()
                .accessibilityIdentifier("detail.copy")

                if let url = token.provider.serviceURL {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 46, height: 46)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Theme.surfaceRaised))
                    }
                }
            }
        }
        .cardSurface(padding: Theme.Space.m)
    }

    private var jwtCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(L("這是一個 JWT"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(L("解碼")) {
                    decoded = JWTDecoder.decode(token.decryptedValue())
                    showingJWT = decoded != nil
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            }
            if let decoded {
                Text(decoded.isExpired ? L("已於 %@ 過期", decoded.expiryLabel) : L("有效期限 %@", decoded.expiryLabel))
                    .font(Theme.caption)
                    .foregroundStyle(decoded.isExpired ? Theme.danger : Theme.textTertiary)
            }
        }
        .cardSurface(padding: Theme.Space.m)
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel("詳細資料")
            MetaRow(label: "服務商", value: token.provider.label, tint: token.provider.tint)
            MetaRow(label: "分類", value: token.category.rawValue)
            MetaRow(label: "格式", value: token.kind.rawValue)
            if let group = vault.group(for: token.groupID) {
                MetaRow(label: "群組", value: group.name)
            }
            MetaRow(label: "建立", value: token.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let used = token.lastUsedAt {
                MetaRow(label: "上次使用", value: used.formatted(date: .abbreviated, time: .shortened))
            }
            MetaRow(label: "複製次數", value: "\(token.copyCount)")
            if let expiry = token.expiresAt {
                MetaRow(label: "到期",
                        value: expiry.formatted(date: .abbreviated, time: .omitted),
                        tint: token.isExpired ? Theme.danger : Theme.textSecondary)
            }
            if !token.customFields.isEmpty {
                Divider().overlay(Theme.hairline).padding(.vertical, 2)
                ForEach(token.customFields.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                    MetaRow(label: pair.key, value: pair.value, mono: true)
                }
            }
        }
        .cardSurface(padding: Theme.Space.m)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel("備註")
            Text(token.note)
                .font(Theme.callout)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardSurface(padding: Theme.Space.m)
    }

    private var tagsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel("標籤")
            FlowTags(tags: token.tags)
        }
        .cardSurface(padding: Theme.Space.m)
    }

    private var actions: some View {
        VStack(spacing: Theme.Space.xs) {
            SecondaryButton(title: token.isFavorite ? "取消收藏" : "加入收藏",
                            symbol: token.isFavorite ? "star.slash" : "star") {
                vault.toggleFavorite(token)
            }
            SecondaryButton(title: "移到垃圾桶", symbol: "trash", destructive: true) {
                confirmTrash = true
            }
            .accessibilityIdentifier("detail.trash")
        }
        .padding(.top, Theme.Space.xs)
    }

    private func copy() {
        ClipboardService.shared.copy(token.decryptedValue(),
                                     clearAfter: settings.clipboardClearSeconds)
        vault.recordUse(token)
        let note = settings.clipboardClearSeconds > 0
            ? L("已複製 · %lld 秒後自動清除", settings.clipboardClearSeconds)
            : L("已複製密鑰")
        toast.show(note, symbol: "doc.on.doc.fill", tint: Theme.accent)
    }
}

// MARK: - Tags

struct FlowTags: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading,
                  spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(Theme.surfaceRaised))
            }
        }
    }
}

// MARK: - JWT sheet

struct JWTSheet: View {
    let decoded: JWTDecoder.Decoded
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(spacing: Theme.Space.s) {
                        HStack(spacing: Theme.Space.xs) {
                            Pill(text: decoded.isExpired ? "已過期" : "有效",
                                 tint: decoded.isExpired ? Theme.danger : Theme.success)
                            Text(decoded.expiryLabel)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textTertiary)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            SectionLabel("Header")
                            Text(decoded.header)
                                .font(Theme.monoSmall)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .cardSurface(padding: Theme.Space.m)

                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            SectionLabel("Payload")
                            ForEach(decoded.claims) { claim in
                                HStack(alignment: .top, spacing: Theme.Space.s) {
                                    Text(claim.key)
                                        .font(Theme.monoSmall)
                                        .foregroundStyle(Theme.textSecondary)
                                        .frame(width: 96, alignment: .leading)
                                    Text(claim.value)
                                        .font(Theme.monoSmall)
                                        .foregroundStyle(Theme.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .cardSurface(padding: Theme.Space.m)
                    }
                    .padding(.horizontal, Theme.inset)
                    .padding(.bottom, Theme.Space.xl)
                }
            }
            .navigationTitle(L("JWT 解碼"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("完成")) { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}
