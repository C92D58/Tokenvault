import SwiftUI
import UIKit

/// One-shot confirmation at the bottom of the screen. Owns nothing but its own lifetime.
final class ToastCenter: ObservableObject {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let symbol: String
        let tint: Color
    }

    @Published private(set) var current: Toast?
    private var dismissWork: DispatchWorkItem?

    func show(_ text: String, symbol: String = "checkmark.circle.fill", tint: Color = Theme.success) {
        dismissWork?.cancel()
        withAnimation(Theme.Motion.snap) {
            current = Toast(text: text, symbol: symbol, tint: tint)
        }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.22)) { self?.current = nil }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
        Haptics.success()
    }

    func dismiss() {
        dismissWork?.cancel()
        current = nil
    }
}

struct ToastHost: View {
    @EnvironmentObject private var toast: ToastCenter

    var body: some View {
        ZStack {
            if let item = toast.current {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(item.tint)
                    Text(item.text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    Color.clear.glassCapsule()
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                )
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 96)
                .allowsHitTesting(false)
            }
        }
        .animation(Theme.Motion.snap, value: toast.current)
    }
}

/// Small, deliberate haptics — the kind that confirm an action instead of announcing the app.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
