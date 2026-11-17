import SwiftUI
import UniformTypeIdentifiers

/// Import from a file, or from whatever is on the clipboard — the two ways secrets actually
/// arrive on a phone.
struct ImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var toast: ToastCenter

    @State private var mode = 0
    @State private var pasted = ""
    @State private var showingPicker = false
    @State private var report: VaultStore.ImportReport?

    private let modes = ["檔案", "貼上"]

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(spacing: Theme.Space.m) {
                        SlidingSegmented(items: modes, selection: $mode)

                        if mode == 0 {
                            fileCard
                        } else {
                            pasteCard
                        }

                        if let report {
                            resultCard(report)
                        }
                    }
                    .padding(.horizontal, Theme.inset)
                    .padding(.top, Theme.Space.s)
                    .padding(.bottom, Theme.Space.xl)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(L("匯入密鑰"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("完成")) { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .fileImporter(isPresented: $showingPicker,
                      allowedContentTypes: [.json, .plainText, .commaSeparatedText, .text],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let outcome = vault.importFile(at: url)
                finish(outcome)
            case .failure(let error):
                report = VaultStore.ImportReport(failure: L("選擇檔案失敗：%@", error.localizedDescription))
            }
        }
    }

    private var fileCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel("從檔案匯入")

            Text(L("支援 macOS 版匯出的加密 JSON 備份、.env 環境檔，以及 CSV（名稱,值,備註,環境）。"))
                .font(Theme.callout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(title: "選擇檔案", symbol: "folder") {
                showingPicker = true
            }
            .accessibilityIdentifier("import.pickFile")

            Text(L("來自其他裝置的加密備份無法在這裡解密 — 那需要該裝置鑰匙圈裡的金鑰。這種情況請改用 .env 或 CSV 匯入。"))
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardSurface(padding: Theme.Space.m)
    }

    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel("貼上內容")

            TextField("KEY=value\nANOTHER_KEY=value", text: $pasted, axis: .vertical)
                .font(Theme.monoSmall)
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(6...12)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.surfaceRaised))
                .accessibilityIdentifier("import.paste")

            HStack(spacing: Theme.Space.xs) {
                SecondaryButton(title: "貼上剪貼板", symbol: "doc.on.clipboard") {
                    pasted = UIPasteboard.general.string ?? ""
                }
                PrimaryButton(title: "匯入") {
                    finish(vault.importText(pasted, filename: "paste.env"))
                    pasted = ""
                }
                .accessibilityIdentifier("import.pasteRun")
            }
        }
        .cardSurface(padding: Theme.Space.m)
    }

    private func resultCard(_ report: VaultStore.ImportReport) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.xs) {
            Image(systemName: report.failure == nil ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(report.failure == nil ? Theme.success : Theme.danger)
            Text(report.summary)
                .font(Theme.callout)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .cardSurface(padding: Theme.Space.m)
    }

    private func finish(_ outcome: VaultStore.ImportReport) {
        report = outcome
        if outcome.failure == nil && (outcome.added > 0 || outcome.updated > 0) {
            toast.show(outcome.summary, symbol: "square.and.arrow.down.fill", tint: Theme.accent)
            app.refreshReminders()
        } else {
            Haptics.warning()
        }
    }
}
