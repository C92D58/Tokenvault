import SwiftUI

/// The locked screen: the mark, what protects the vault, and one way in.
struct LockView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @State private var pulse = false
    @State private var asking = false
    @State private var didAutoPrompt = false

    var body: some View {
        ZStack {
            ScreenBackground()

            VStack(spacing: 0) {
                Spacer()

                VaultMark(pulse: pulse)
                    .frame(width: 108, height: 108)

                VStack(spacing: Theme.Space.xs) {
                    Text("TokenVault")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("AES-256-GCM · 只留在這台裝置")
                        .font(Theme.callout)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.top, Theme.Space.l)

                Spacer()

                VStack(spacing: Theme.Space.s) {
                    Button {
                        Task { await unlockNow() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: app.auth.symbol)
                                .font(.system(size: 15, weight: .semibold))
                            Text(settings.biometricLock ? "以 \(app.auth.label) 解鎖" : "進入保險庫")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.accentGradient))
                        .shadow(color: Theme.accent.opacity(0.35), radius: 18, y: 8)
                    }
                    .pressable()
                    .disabled(asking)
                    .accessibilityIdentifier("lock.unlock")

                    if let failure = app.auth.lastFailure {
                        Text(failure)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.danger)
                    }

                    Text("密鑰以 AES-256-GCM 加密，金鑰存在鑰匙圈，永不上傳")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: 300)
                        .padding(.top, Theme.Space.xxs)
                }
                .padding(.horizontal, Theme.Space.xl)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .task { await autoUnlockIfNeeded() }
        // Anywhere on the screen is the unlock button: nobody should have to aim at a pill.
        .contentShape(Rectangle())
        .onTapGesture { Task { await unlockNow() } }
    }
}

/// Concentric vault door — drawn, not an image, so it scales to any screen and the pulse is real.
private extension LockView {
    /// Face ID the moment the screen is up — a lock screen that waits for a tap is a lock screen
    /// that gets tapped. Once per appearance, so a cancelled prompt does not loop.
    func autoUnlockIfNeeded() async {
        guard !didAutoPrompt else { return }
        didAutoPrompt = true
        guard app.isLocked, settings.biometricLock else { return }
        // `AppState.prepare()` already asks once at launch; this is the second, later attempt so a
        // cancelled prompt does not leave a dead screen behind.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard app.isLocked else { return }
        await unlockNow()
    }

    func unlockNow() async {
        guard !asking, app.isLocked else { return }
        asking = true
        defer { asking = false }
        await app.unlock()
    }
}

struct VaultMark: View {
    var pulse: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.accent.opacity(0.18), lineWidth: 1)
                .scaleEffect(pulse ? 1.08 : 0.94)
                .opacity(pulse ? 0.4 : 0.9)

            Circle()
                .fill(Theme.accentGradient)
                .shadow(color: Theme.accent.opacity(0.45), radius: 24, y: 10)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.28), lineWidth: 1)
                        .blur(radius: 0.6)
                )
                .padding(10)

            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 3, height: 13)
                    .offset(y: -30)
                    .rotationEffect(.degrees(Double(index) * 90 + 45))
            }

            Circle()
                .fill(Color(hex: "#151024"))
                .frame(width: 13, height: 13)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color(hex: "#151024"))
                        .frame(width: 7, height: 20)
                        .offset(y: 13)
                }
        }
        .accessibilityHidden(true)
    }
}
