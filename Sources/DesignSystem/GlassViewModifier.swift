import SwiftUI

// MARK: - Surface Modifiers
// Solid-surface modifiers replacing the previous glass-effect materials.
// Uses opaque system colors for a clean, distraction-free appearance.

/// Level of surface prominence
enum SurfaceLevel {
    case subtle     // Slightly recessed — for sidebar, toolbar
    case standard   // Standard surface — for cards, panels
    case prominent  // Elevated surface — for lock screen, prominent panels
    case chrome     // Window chrome — for title bars

    var backgroundColor: Color {
        switch self {
        case .subtle:    return Color(.controlBackgroundColor)
        case .standard:  return Color(.controlBackgroundColor)
        case .prominent: return Color(.windowBackgroundColor)
        case .chrome:    return Color(.windowBackgroundColor)
        }
    }

    var strokeColor: Color {
        switch self {
        case .subtle:    return Color.primary.opacity(0.06)
        case .standard:  return Color.primary.opacity(0.08)
        case .prominent: return Color.primary.opacity(0.10)
        case .chrome:    return Color.primary.opacity(0.04)
        }
    }

    /// Material overlay for translucent glass effect.
    var material: Material {
        switch self {
        case .subtle:    return .ultraThinMaterial
        case .standard:  return .ultraThinMaterial
        case .prominent: return .regularMaterial
        case .chrome:    return .ultraThinMaterial
        }
    }
}

// MARK: - Surface Modifier

/// Applies a solid background with a subtle border.
struct Surface: ViewModifier {
    let level: SurfaceLevel
    let cornerRadius: CGFloat

    init(level: SurfaceLevel = .standard, cornerRadius: CGFloat = 12) {
        self.level = level
        self.cornerRadius = cornerRadius
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // The system's own Liquid Glass. The opaque plate this replaced was a deliberate
            // detour; on a macOS that has the material, the app belongs to the platform.
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(level.strokeColor, lineWidth: 1)
                )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(level.backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(level.material)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(level.strokeColor, lineWidth: 1)
                )
        }
    }
}

// MARK: - Card Modifier

/// Card with translucent material, shadow, hover lift (2px), and focus glow.
/// Apple HIG: cards lift on hover — they do NOT scale.
struct CardSurface: ViewModifier {
    let isHovering: Bool
    let isFocused: Bool
    let cornerRadius: CGFloat

    init(isHovering: Bool = false, isFocused: Bool = false, cornerRadius: CGFloat = 12) {
        self.isHovering = isHovering
        self.isFocused = isFocused
        self.cornerRadius = cornerRadius
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            glassCard(content)
        } else {
            opaqueCard(content)
        }
    }

    @available(macOS 26.0, *)
    private func glassCard(_ content: Content) -> some View {
        content
            .glassEffect(.regular.interactive(),
                         in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isFocused
                            ? DS.Color.accent.opacity(0.35)
                            : Color.primary.opacity(isHovering ? 0.10 : 0.06),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .shadow(
                color: .black.opacity(isHovering || isFocused
                    ? DS.Card.hoverShadowOpacity
                    : DS.Card.normalShadowOpacity),
                radius: isHovering || isFocused
                    ? DS.Card.hoverShadowBlur
                    : DS.Card.normalShadowBlur,
                y: isHovering || isFocused
                    ? DS.Card.hoverShadowY
                    : DS.Card.normalShadowY
            )
            // Apple HIG: lift 2px on hover — do NOT scale.
            .offset(y: (isHovering || isFocused) ? -DS.Card.hoverLift : 0)
            .animation(DS.Animation.easeOut, value: isHovering)
            .animation(DS.Animation.easeOut, value: isFocused)
    }

    private func opaqueCard(_ content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isFocused
                            ? DS.Color.accent.opacity(0.35)
                            : Color.primary.opacity(isHovering ? 0.10 : 0.06),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .offset(y: (isHovering || isFocused) ? -DS.Card.hoverLift : 0)
            .animation(DS.Animation.easeOut, value: isHovering)
            .animation(DS.Animation.easeOut, value: isFocused)
    }
}

// MARK: - Input Field Modifier

/// Text field with solid container styling.
struct InputField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
    }
}

// MARK: - Ambient Glow Modifier

/// Subtle colored glow behind an element — used for brand accents.
struct AmbientGlow: ViewModifier {
    let color: Color
    let radius: CGFloat

    init(color: Color = Color(red: 0.60, green: 0.47, blue: 0.98), radius: CGFloat = 40) {
        self.color = color
        self.radius = radius
    }

    func body(content: Content) -> some View {
        content
            .background(
                Circle()
                    .fill(color.opacity(0.06))
                    .frame(width: radius * 2, height: radius * 2)
                    .blur(radius: radius * 0.5)
            )
    }
}

// MARK: - Accent Glow Modifier

/// Radial gradient glow for active/selected elements.
/// Apple-style subtle highlight rather than a hard border.
struct AccentGlow: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RadialGradient(
                    colors: [
                        DS.Color.accent.opacity(isActive ? 0.10 : 0.0),
                        DS.Color.accent.opacity(0.0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 60
                )
            )
            .animation(DS.Animation.easeOut, value: isActive)
    }
}

// MARK: - View Extensions

extension View {

    /// Apply solid surface background.
    func surface(level: SurfaceLevel = .standard, cornerRadius: CGFloat = 12) -> some View {
        modifier(Surface(level: level, cornerRadius: cornerRadius))
    }

    /// Apply solid card with hover/focus states.
    func cardSurface(isHovering: Bool = false, isFocused: Bool = false, cornerRadius: CGFloat = 12) -> some View {
        modifier(CardSurface(isHovering: isHovering, isFocused: isFocused, cornerRadius: cornerRadius))
    }

    /// Apply solid input field styling.
    func inputField() -> some View {
        modifier(InputField())
    }

    /// Apply ambient glow background.
    func ambientGlow(color: Color = Color(red: 0.60, green: 0.47, blue: 0.98), radius: CGFloat = 40) -> some View {
        modifier(AmbientGlow(color: color, radius: radius))
    }

    /// Apply radial accent glow for active/selected elements.
    func accentGlow(isActive: Bool = true) -> some View {
        modifier(AccentGlow(isActive: isActive))
    }
}
