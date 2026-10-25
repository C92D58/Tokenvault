import SwiftUI

/// A capsule segmented bar that can never take keyboard focus.
///
/// On macOS a system `TabView` is an `NSTabView`, and its tab bar draws a blue focus ring the
/// moment Tab moves through the window. Page switches are not keyboard targets, so every tab bar
/// in the app is built from this: plain buttons, `focusable(false)`, one accent capsule marking
/// the current page.
struct PillTabBar<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    let icon: (Item) -> String
    @Binding var selection: Item

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                let isSelected = selection == item
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selection = item }
                } label: {
                    Label(L(title(item)), systemImage: icon(item))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? DS.Color.accent : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                isSelected ? DS.Color.accent.opacity(0.14) : Color.clear
                            )
                        )
                        .overlay(
                            Capsule().stroke(
                                isSelected ? DS.Color.accent.opacity(0.25) : .clear,
                                lineWidth: 1
                            )
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
