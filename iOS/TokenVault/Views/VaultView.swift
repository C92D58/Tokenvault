import SwiftUI

/// The vault itself: header, search, filters, and one card per secret.
struct VaultView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var toast: ToastCenter

    @State private var query = ""
    @State private var filter: VaultFilter = .all
    @State private var detailToken: TokenItem?
    @State private var editingToken: TokenItem?
    @State private var showingEditor = false
    @State private var showingImport = false
    @State private var showingTrash = false
    @State private var showingFilters = false

    private var visible: [TokenItem] { vault.visibleTokens(filter, query: query) }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                VStack(spacing: 0) {
                    header
                    searchRow
                    filterRow
                    content
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $detailToken) { token in
            TokenDetailView(token: token)
        }
        .sheet(isPresented: $showingEditor) {
            TokenEditorView(existing: nil)
        }
        .sheet(item: $editingToken) { token in
            TokenEditorView(existing: token)
        }
        .sheet(isPresented: $showingImport) {
            ImportSheet()
        }
        .sheet(isPresented: $showingTrash) {
            TrashView()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: 3) {
                Text("保險庫")
                    .font(Theme.title)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityIdentifier("vault.title")

                HStack(spacing: 6) {
                    Text(L("%lld 個密鑰", vault.activeTokens.count))
                    if !vault.favorites.isEmpty {
                        Circle().fill(Theme.textTertiary).frame(width: 2.5, height: 2.5)
                        Text("\(vault.favorites.count) 收藏")
                    }
                    if !vault.expiring.isEmpty {
                        Circle().fill(Theme.textTertiary).frame(width: 2.5, height: 2.5)
                        Text("\(vault.expiring.count) 待處理")
                            .foregroundStyle(Theme.warning)
                    }
                }
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            HStack(spacing: Theme.Space.xs) {
                RoundIconButton(symbol: "lock.fill") { app.lock() }
                    .accessibilityIdentifier("vault.lock")

                Menu {
                    Button {
                        showingImport = true
                    } label: {
                        Label("匯入備份…", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        showingTrash = true
                    } label: {
                        Label(vault.trashedTokens.isEmpty ? "垃圾桶" : "垃圾桶（\(vault.trashedTokens.count)）",
                              systemImage: "trash")
                    }
                    Divider()
                    Text(L("%lld 個密鑰 · AES-256-GCM", vault.activeTokens.count))
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Theme.surface))
                        .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                }
                .accessibilityIdentifier("vault.menu")

                Button {
                    Haptics.tap()
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .glassCircle(tint: Theme.accent.opacity(0.75), fallback: Theme.accent)
                        .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 4)
                }
                .pressable()
                .accessibilityIdentifier("vault.add")
            }
        }
        .padding(.horizontal, Theme.inset)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.m)
    }

    private var searchRow: some View {
        SearchField(text: $query)
            .padding(.horizontal, Theme.inset)
            .padding(.bottom, Theme.Space.s)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.xs) {
                ForEach([VaultFilter.all, .favorites, .expiring], id: \.self) { item in
                    FilterChip(title: item.label, symbol: item.symbol, isOn: filter == item) {
                        withAnimation(Theme.Motion.snap) { filter = item }
                    }
                }
                ForEach(vault.categoriesInUse, id: \.self) { category in
                    FilterChip(title: category.rawValue, symbol: nil,
                               isOn: filter == .category(category)) {
                        withAnimation(Theme.Motion.snap) { filter = .category(category) }
                    }
                }
            }
            .padding(.horizontal, Theme.inset)
            .padding(.vertical, 2)
            .padding(.trailing, Theme.Space.xl)
        }
        .padding(.bottom, Theme.Space.s)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vault.activeTokens.isEmpty {
            ScrollView {
                EmptyState(
                    symbol: "key.horizontal",
                    title: "保險庫是空的",
                    message: "新增第一個 API 密鑰，或匯入 .env / CSV / JSON 備份。所有內容都會以 AES-256-GCM 加密後才寫入磁碟。",
                    action: ("新增密鑰", { showingEditor = true })
                )
                importButton
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.bottom, 80)
            }
        } else if visible.isEmpty {
            ScrollView {
                EmptyState(symbol: isSearching ? "magnifyingglass" : "line.3.horizontal.decrease",
                           title: isSearching ? "沒有符合的密鑰" : "這個分類還沒有密鑰",
                           message: isSearching
                            ? "試試 tag:、provider: 或 cat: 這類篩選語法。"
                            : "換個分類，或把密鑰加進這個分類。")
                if isSearching {
                    Button("清除搜尋條件") {
                        query = ""
                        filter = .all
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                }
            }
        } else {
            List {
                ForEach(visible) { token in
                    TokenRowView(token: token)
                        .contentShape(Rectangle())
                        .onTapGesture { detailToken = token }
                        .listRowInsets(EdgeInsets(top: 4, leading: Theme.inset,
                                                  bottom: 4, trailing: Theme.inset))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                copy(token)
                            } label: {
                                Label("複製", systemImage: "doc.on.doc")
                            }
                            .tint(Theme.accent)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                vault.trash(token)
                                toast.show("已移到垃圾桶", symbol: "trash.fill", tint: Theme.warning)
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                            Button {
                                vault.toggleFavorite(token)
                            } label: {
                                Label(token.isFavorite ? "取消收藏" : "收藏", systemImage: "star")
                            }
                            .tint(Theme.warning)
                        }
                        .contextMenu {
                            Button { copy(token) } label: { Label("複製密鑰", systemImage: "doc.on.doc") }
                            Button { editingToken = token } label: { Label("編輯", systemImage: "pencil") }
                            Button { vault.toggleFavorite(token) } label: {
                                Label(token.isFavorite ? "取消收藏" : "收藏", systemImage: "star")
                            }
                            Divider()
                            Button(role: .destructive) {
                                vault.trash(token)
                                toast.show("已移到垃圾桶", symbol: "trash.fill", tint: Theme.warning)
                            } label: { Label("移到垃圾桶", systemImage: "trash") }
                        }
                }

                // Keeps the last card clear of the floating tab bar.
                Color.clear
                    .frame(height: 64)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(Theme.Motion.snap, value: visible.count)
        }
    }

    private var importButton: some View {
        SecondaryButton(title: "匯入備份（.env / CSV / JSON）", symbol: "square.and.arrow.down") {
            showingImport = true
        }
    }

    // MARK: - Actions

    private func copy(_ token: TokenItem) {
        ClipboardService.shared.copy(token.decryptedValue(),
                                     clearAfter: settings.clipboardClearSeconds)
        vault.recordUse(token)
        let note = settings.clipboardClearSeconds > 0
            ? "已複製 · \(settings.clipboardClearSeconds) 秒後自動清除"
            : "已複製密鑰"
        toast.show(note, symbol: "doc.on.doc.fill", tint: Theme.accent)
    }
}

// MARK: - Row

struct TokenRowView: View {
    let token: TokenItem

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ProviderBadge(provider: token.provider, size: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(token.name)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if token.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.warning)
                    }
                    Spacer(minLength: 4)
                    EnvBadge(environment: token.environment)
                }

                HStack(spacing: 6) {
                    Text(token.maskedPreview)
                        .font(Theme.monoSmall)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Spacer(minLength: 2)

                    if token.isExpired {
                        Pill(text: "已過期", tint: Theme.danger)
                    } else if token.expiresSoon {
                        Pill(text: "即將到期", tint: Theme.warning)
                    }
                }
            }

            Image(systemName: "square.on.square")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.surfaceRaised))
        }
        .cardSurface(radius: Theme.Radius.card, padding: 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("token.\(token.name)")
    }
}
