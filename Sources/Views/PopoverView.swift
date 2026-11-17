import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: DataStore
    @State private var searchText = ""
    @State private var copiedID: UUID?
    @State private var hoveredID: UUID?

    var tokens: [TokenItem] {
        if searchText.isEmpty {
            return Array(store.activeTokens.sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }.prefix(10))
        }
        return store.search(searchText, in: nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .frame(width: 24, height: 24)
                            .background(
                                AnimatedGradient(colors: [DS.Color.accentLight, DS.Color.accent, DS.Color.accentDark])
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(.white.opacity(0.15), lineWidth: 1)
                            )
                        Image(systemName: "key.horizontal.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(DS.Color.onAccent)
                    }
                    Text("TokenVault")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(-0.3)
                }
                Spacer()
                Button {
                    (NSApp.delegate as? AppDelegate)?.showMainContent()
                    NSApp.keyWindow?.performClose(nil)
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.quaternary.opacity(0.4)))
                }
                .buttonStyle(.plain).focusEffectDisabled()
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

            // Search — glass field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary.opacity(0.5))
                    .font(.system(size: 11))
                TextField("搜尋...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .inputField()
            .padding(.horizontal, 12).padding(.bottom, 8)

            Divider().opacity(0.3)

            if tokens.isEmpty {
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: searchText.isEmpty ? "key.slash" : "magnifyingglass")
                            .font(.system(size: 22))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text(searchText.isEmpty ? "尚無 Token" : "無匹配")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(tokens) { token in
                            Button {
                                let value = token.decryptedValue()
                                ClipboardService.shared.copy(value)
                                store.useToken(token)
                                let id = token.id
                                withAnimation(.spring(response: 0.3)) { copiedID = id }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    if copiedID == id { withAnimation { copiedID = nil } }
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    NSApp.keyWindow?.performClose(nil)
                                }
                            } label: {
                                popoverRow(token)
                            }
                            .buttonStyle(.plain).focusEffectDisabled()
                        }
                    }
                }
            }

            Divider().opacity(0.3)

            // Footer
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "command").font(.system(size: 10))
                    Image(systemName: "shift").font(.system(size: 10))
                    Text("T").font(.system(size: 10, weight: .bold, design: .monospaced))
                    Text("貼上").font(.system(size: 10))
                }
                .foregroundColor(.secondary.opacity(0.4))
                Spacer()
                Text("\(store.activeTokens.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.35))
                Text("·").foregroundColor(.secondary.opacity(0.15))
                Text("🔒").font(.system(size: 8)).opacity(0.3)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(width: 360)
        .background(Color(.windowBackgroundColor).overlay(.ultraThinMaterial))
    }

    private func popoverRow(_ token: TokenItem) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(token.isFavorite
                        ? AnyShapeStyle(Color.orange.opacity(0.12))
                        : AnyShapeStyle(token.provider.color.swiftUIColor.opacity(0.1)))
                    .frame(width: 26, height: 26)
                Image(systemName: token.isFavorite ? "star.fill" : token.provider.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(token.isFavorite
                        ? AnyShapeStyle(Color.orange)
                        : AnyShapeStyle(token.provider.color.swiftUIColor))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(token.name)
                        .font(.system(size: 12, weight: .medium))
                        .tracking(-0.2).lineLimit(1)
                    Text(token.category.emoji).font(.system(size: 9))
                }
                Text("\(token.provider.displayName) · \(token.environment.displayName)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            if copiedID == token.id {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hoveredID == token.id
                    ? Color.primary.opacity(0.04)
                    : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredID = hovering ? token.id : nil
            }
        }
        .contextMenu {
            Button {
                let value = token.decryptedValue()
                ClipboardService.shared.copy(value)
                store.useToken(token)
            } label: {
                Label("複製", systemImage: "doc.on.doc")
            }
            Button {
                (NSApp.delegate as? AppDelegate)?.toggleFav(token)
            } label: {
                Label(token.isFavorite ? "取消收藏" : "收藏", systemImage: token.isFavorite ? "star.slash" : "star")
            }
            Divider()
            Button {
                store.softDeleteToken(token)
            } label: {
                Label("刪除", systemImage: "trash")
            }
        }
    }
}
