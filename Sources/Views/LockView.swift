import SwiftUI

struct LockView: View {
    @ObservedObject var auth: AuthService
    let onUnlock: () -> Void

    @State private var pulse = false
    @State private var appear = false
    @State private var isActive = true
    @State private var asking = false
    @State private var didAutoPrompt = false
    @State private var glowRotation: Double = 0

    var body: some View {
        ZStack {
            // Glass material background with particles
            Color(.windowBackgroundColor).opacity(0.3)
            DS.Color.accentGradientSubtle.opacity(0.5)
            ParticleField(count: 20, color: DS.Color.accentLight)

            VStack(spacing: 0) {
                Spacer()

                // App mark — the real icon, edge to edge with the ring
                ZStack {
                    // Outer glow pulse
                    Circle()
                        .fill(DS.Color.accent.opacity(0.06))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulse && isActive ? 1.15 : 1.0)
                        .opacity(pulse && isActive ? 0.6 : 0.2)

                    // Ring
                    Circle()
                        .stroke(DS.Color.accentGradient, lineWidth: 2)
                        .frame(width: 100, height: 100)
                        .opacity(0.2)

                    // The icon fills the ring: no dead gap between the mark and the circle.
                    Circle()
                        .fill(Color(red: 0.09, green: 0.063, blue: 0.165))  // the icon's own base
                        .frame(width: 100, height: 100)
                    markShape
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                }

                Spacer().frame(height: 32)

                // Brand
                Text("TokenVault")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.6)

                Text("API Token 管理器")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

                Spacer().frame(height: 10)

                // Auth prompt
                Text("需要 \(auth.biometryType) 解鎖")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                if auth.authFailed {
                    Text("認證失敗，再試一次")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Capsule().fill(Color.red.opacity(0.08)))
                        .padding(.top, 6)
                        .transition(.scale.combined(with: .opacity))
                }

                Spacer().frame(height: 24)

                // Unlock button — glass pill
                Button {
                    Task { await unlockNow() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: auth.biometryType == "Face ID" ? "faceid" : "touchid")
                            .font(.system(size: 18))
                        Text("使用 \(auth.biometryType) 解鎖")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 32).padding(.vertical, 12)
                    .background(Capsule().fill(DS.Color.accent.opacity(0.12)))
                    .overlay(Capsule().stroke(DS.Color.accent.opacity(0.2), lineWidth: 1))
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                }
                .buttonStyle(.plain).focusEffectDisabled().keyboardShortcut(.return)

                Spacer()

                // Security note
                VStack(spacing: 6) {
                    Divider().frame(width: 160).opacity(0.3)

                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green.opacity(0.5))
                        Text("AES-256-GCM 加密 · Secure Enclave")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.35))
                    }
                }
                .padding(.bottom, 32)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 12)
        }
        .frame(width: 420, height: 520)
        .background(.ultraThinMaterial)
        .onAppear {
            isActive = true
            withAnimation(DS.Animation.fade) { appear = true }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onDisappear {
            isActive = false
            pulse = false
        }
        .task { await autoUnlockIfNeeded() }
    }

    /// Ask for Touch ID as soon as the window is up: a lock screen that waits for a click is a lock
    /// screen that gets clicked. Runs once per appearance so a cancelled prompt does not loop.
    private func autoUnlockIfNeeded() async {
        guard !didAutoPrompt else { return }
        didAutoPrompt = true
        // Let the window finish drawing first; a prompt over a blank window feels like a glitch.
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard isActive else { return }
        await unlockNow()
    }

    private func unlockNow() async {
        guard !asking else { return }
        asking = true
        defer { asking = false }
        if await auth.authenticate() { onUnlock() }
    }

    /// The app's own icon, so the launch screen matches the Dock and Finder. `NSApp` has no icon in
    /// a bare swiftc build (build.sh), so fall back to the drawn mark there.
    @ViewBuilder
    private var markShape: some View {
        if let icon = NSApp.applicationIconImage {
            // App-icon artwork carries a transparent margin (Apple's icon grid), so a plain clip
            // leaves a ring of nothing inside the circle. Scale past the frame and let the crop cut
            // into the artwork: the icon's own background reaches the edge.
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(1, contentMode: .fill)
                .scaleEffect(1.2)
        } else {
            Rectangle()
                .fill(DS.Color.accentGradient)
                .overlay(
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 46, weight: .medium))
                        .foregroundStyle(.white)
                )
        }
    }
}
