import SwiftUI


// MARK: - Liquid Glass

/// The one place the glass recipe lives. `interactive()` gives the touch response — the lens
/// bends and springs under the finger — which is what makes a control feel physical rather than
/// merely translucent.
@available(iOS 26.0, *)
private func glassMaterial(tint: Color? = nil, interactive: Bool = true) -> Glass {
    var glass: Glass = .regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

extension View {
    /// Liquid Glass capsule on iOS 26; the flat surface it replaces below that.
    @ViewBuilder
    func glassCapsule(tint: Color? = nil,
                      interactive: Bool = true,
                      fallback: Color = Theme.surface) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(glassMaterial(tint: tint, interactive: interactive), in: .capsule)
        } else {
            background(Capsule().fill(fallback))
        }
    }

    @ViewBuilder
    func glassCircle(tint: Color? = nil,
                     interactive: Bool = true,
                     fallback: Color = Theme.surface) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(glassMaterial(tint: tint, interactive: interactive), in: .circle)
        } else {
            background(Circle().fill(fallback))
        }
    }

    @ViewBuilder
    func glassRounded(_ radius: CGFloat,
                      tint: Color? = nil,
                      interactive: Bool = true,
                      fallback: Color = Theme.surface) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(glassMaterial(tint: tint, interactive: interactive),
                        in: .rect(cornerRadius: radius, style: .continuous))
        } else {
            background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fallback))
        }
    }
}

// MARK: - Surfaces

/// The one card treatment in the app: a rounded rect on the surface colour, a single hairline,
/// and a shadow soft enough to suggest depth without drawing attention to itself.
struct CardSurface: ViewModifier {
    var radius: CGFloat = Theme.Radius.card
    var padding: CGFloat = Theme.Space.m
    var raised = false

    func body(content: Content) -> some View {
        // iOS 26+: real Liquid Glass, so cards refract the bloom behind them. Older systems keep
        // the flat surface + hairline, which is the same silhouette without the material cost.
        if #available(iOS 26.0, *) {
            content
                .padding(padding)
                .glassEffect(.regular, in: .rect(cornerRadius: radius, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        } else {
            content
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(raised ? Theme.surfaceRaised : Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        }
    }
}

extension View {
    func cardSurface(radius: CGFloat = Theme.Radius.card,
                     padding: CGFloat = Theme.Space.m,
                     raised: Bool = false) -> some View {
        modifier(CardSurface(radius: radius, padding: padding, raised: raised))
    }

    /// Gives any tappable surface the pressed-in feel of a physical control.
    func pressable() -> some View { buttonStyle(PressableStyle()) }
}

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

/// A quiet screen background: the flat base plus one violet bloom off the top corner.
struct ScreenBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            RadialGradient(colors: [Theme.backgroundGlow.opacity(0.55), .clear],
                           center: .topTrailing, startRadius: 8, endRadius: 420)
                .frame(height: 420)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Badges

struct Pill: View {
    let text: String
    var tint: Color = Theme.textSecondary
    var filled = true

    var body: some View {
        Text(L(text))
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(filled ? tint : Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                Capsule().fill(filled ? tint.opacity(0.14) : Color.clear)
            )
            .overlay(
                Capsule().stroke(filled ? .clear : Theme.hairline, lineWidth: 1)
            )
    }
}

struct EnvBadge: View {
    let environment: TokenEnvironment

    var body: some View {
        Text(environment.shortLabel)
            .font(.system(size: 9.5, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(environment.brandColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(environment.brandColor.opacity(0.14)))
            .accessibilityLabel(environment.rawValue)
    }
}

/// The provider's square: brand tint behind the provider's glyph, bound by a hairline so it
/// still reads on a light card where the tint is pale.
struct ProviderBadge: View {
    let provider: TokenProvider
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(provider.tint.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .stroke(provider.tint.opacity(0.28), lineWidth: 1)
            )
            .overlay(
                Image(systemName: provider.iosSymbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(provider.tint)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Controls

struct RoundIconButton: View {
    let symbol: String
    var tint: Color = Theme.textPrimary
    var size: CGFloat = 38
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .glassCircle()
        }
        .pressable()
    }
}

/// A segmented control whose selected pill slides instead of cutting.
/// Small pill-shaped selector: a glass capsule rail with a lens that slides between options.
/// Deliberately compact — 30pt tall, 6pt inner padding — so it reads as a control, not a card.
struct SlidingSegmented: View {
    let items: [String]
    @Binding var selection: Int
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, title in
                Button {
                    guard selection != index else { return }
                    Haptics.select()
                    withAnimation(Theme.Motion.snap) { selection = index }
                } label: {
                    Text(L(title))
                        .font(.system(size: 12.5, weight: selection == index ? .semibold : .medium))
                        .foregroundStyle(selection == index ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 6)
                        .contentShape(Capsule())
                        .background {
                            if selection == index { lens }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background { rail }
    }

    /// The moving body: glass with the same tint-and-rim recipe as SHELL's language switch.
    /// It used to be a flat fill with a shadow — a chip, not a lens. `matchedGeometryEffect`
    /// stays, so the lens travels between segments rather than blinking.
    @ViewBuilder
    private var lens: some View {
        let shape = Capsule()
        if #available(iOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular.tint(Theme.textPrimary.opacity(0.14)).interactive(),
                             in: shape)
                .overlay { Capsule().stroke(.white.opacity(0.26), lineWidth: 0.8) }
                .matchedGeometryEffect(id: "segment", in: namespace)
        } else {
            shape
                .fill(Theme.textPrimary.opacity(0.10))
                .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.16), radius: 4, y: 1)
                .matchedGeometryEffect(id: "segment", in: namespace)
        }
    }

    @ViewBuilder
    private var rail: some View {
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            Capsule()
                .fill(Theme.surfaceRaised)
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String = L("搜尋名稱、服務商、標籤…")
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            TextField(placeholder, text: $text)
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("vault.search")

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassRounded(Theme.Radius.control, interactive: false)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .stroke(focused ? Theme.accent.opacity(0.5) : .clear, lineWidth: 1)
        )
        .animation(Theme.Motion.press, value: focused)
    }
}

struct FilterChip: View {
    let title: String
    var symbol: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                }
                Text(L(title)).font(.system(size: 12.5, weight: isOn ? .semibold : .medium))
            }
            .foregroundStyle(isOn ? Color.white : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isOn ? AnyShapeStyle(Theme.accentGradient)
                                    : AnyShapeStyle(Color.clear))
            )
            .glassCapsule(tint: isOn ? nil : nil, interactive: !isOn)
        }
        .pressable()
        .accessibilityIdentifier("filter.\(title)")
    }
}

// MARK: - Structure

struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(L(text).uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .tracking(0.9)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Label on the left, value on the right — the row every metadata card is built from.
struct MetaRow: View {
    let label: String
    let value: String
    var mono = false
    var tint: Color = Theme.textSecondary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L(label))
                .font(Theme.callout)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: Theme.Space.m)
            Text(value)
                .font(mono ? Theme.monoSmall : Theme.callout)
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 5)
    }
}

/// A settings row: symbol, title, optional detail, and a trailing control.
struct SettingsRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var detail: String?
    var tint: Color = Theme.accent
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: Theme.IconSize.row * 0.47, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Theme.IconSize.row, height: Theme.IconSize.row)
                .background(RoundedRectangle(cornerRadius: Theme.IconSize.row * 0.3, style: .continuous)
                    .fill(tint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(L(title))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                if let detail {
                    Text(L(detail)).font(Theme.caption).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: Theme.Space.s)
            trailing()
        }
        .padding(.vertical, 5)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var action: (title: String, handler: () -> Void)?

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.accent)
                .padding(.bottom, 2)
            Text(L(title))
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(Theme.callout)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action: action.handler) {
                    Text(action.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Theme.accentGradient))
                }
                .pressable()
                .padding(.top, Theme.Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.xxl)
    }
}

/// Primary action: full-width, violet, one per screen at most.
struct PrimaryButton: View {
    let title: String
    var symbol: String?
    var tint: LinearGradient = Theme.accentGradient
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)) }
                Text(L(title)).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint))
        }
        .pressable()
    }
}

struct SecondaryButton: View {
    let title: String
    var symbol: String?
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)) }
                Text(L(title)).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(destructive ? Theme.danger : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .glassRounded(14, tint: destructive ? Theme.danger.opacity(0.55) : nil)
        }
        .pressable()
    }
}
