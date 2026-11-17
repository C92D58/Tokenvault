import SwiftUI
import AppKit

// MARK: - Design System Tokens
// Centralized design parameters for the macOS 26 glass redesign.
// All views reference these tokens instead of hardcoding values.
//
// NOTE: When building with macOS 26 SDK, swap DS.Material.glassMaterial
// to use `.glass` with @available(macOS 26, *).

enum DS {

    // MARK: - Brand Colors

    enum Color {
        /// Resolves per appearance: the bright cyan only works on the dark ground, so the light
        /// appearance gets a deeper teal that keeps its contrast on paper.
        static func adaptive(_ light: NSColor, _ dark: NSColor) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            })
        }

        /// Primary accent — bright cyan, on a neutral dark ground
        static let accent = adaptive(
            NSColor(srgbRed: 0.043, green: 0.478, blue: 0.447, alpha: 1),   // #0B7A72
            NSColor(srgbRed: 0.208, green: 0.882, blue: 0.815, alpha: 1))   // #35E1D0
        /// Light accent variant
        static let accentLight = adaptive(
            NSColor(srgbRed: 0.071, green: 0.655, blue: 0.600, alpha: 1),   // #12A79A
            NSColor(srgbRed: 0.490, green: 0.953, blue: 0.902, alpha: 1))   // #7DF3E6
        /// Dark accent variant
        static let accentDark = adaptive(
            NSColor(srgbRed: 0.031, green: 0.388, blue: 0.361, alpha: 1),   // #08635C
            NSColor(srgbRed: 0.059, green: 0.635, blue: 0.592, alpha: 1))   // #0FA297

        /// The literal brand cyan — glows and blooms that never sit on paper.
        static let accentBright = SwiftUI.Color(red: 0.208, green: 0.882, blue: 0.815)   // #35E1D0

        /// Ink that sits ON the bright gradient — white disappears on cyan, petrol does not.
        static let onAccent = SwiftUI.Color(red: 0.016, green: 0.075, blue: 0.071)        // #041312

        /// Accent gradient used across the app
        static let accentGradient = LinearGradient(
            colors: [accentLight, accentDark],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        /// Subtle accent gradient for backgrounds
        static let accentGradientSubtle = LinearGradient(
            colors: [accentLight.opacity(0.3), accentDark.opacity(0.15)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: - Materials
    // When macOS 26 SDK is available, replace glassMaterial with:
    //   if #available(macOS 26, *) { return .glass } else { return .ultraThinMaterial }

    enum Material {
        /// Primary glass surface — ultraThinMaterial for translucency.
        /// On macOS 26+ this should become `.glass`.
        static let glassMaterial: SwiftUI.Material = .ultraThinMaterial

        /// Elevated surface for cards and prominent panels
        static let elevated: SwiftUI.Material = .regularMaterial

        /// Base surface for backgrounds
        static let base: SwiftUI.Material = .ultraThinMaterial

        /// Subtle surface for secondary areas
        static let subtle: SwiftUI.Material = .ultraThinMaterial

        /// Thick glass for lock screen and modal surfaces
        static let thick: SwiftUI.Material = .regularMaterial

        /// Chrome-level translucency for title bars
        static let chrome: SwiftUI.Material = .ultraThinMaterial
    }

    // MARK: - Typography

    enum Typography {
        static let largeTitle: Font = .system(size: 26, weight: .bold, design: .default)
        static let title: Font = .system(size: 22, weight: .bold, design: .default)
        static let titleMedium: Font = .system(size: 16, weight: .semibold)
        static let headline: Font = .system(size: 14, weight: .semibold)
        static let body: Font = .system(size: 13, weight: .regular)
        static let bodyMedium: Font = .system(size: 13, weight: .medium)
        static let callout: Font = .system(size: 12, weight: .regular)
        static let caption: Font = .system(size: 11, weight: .regular)
        static let captionBold: Font = .system(size: 11, weight: .semibold)
        static let tiny: Font = .system(size: 10, weight: .regular)
        static let monospaced: Font = .system(size: 11, design: .monospaced)
        static let monospacedSmall: Font = .system(size: 10, design: .monospaced)
        static let monospacedTiny: Font = .system(size: 10, design: .monospaced)
    }

    // MARK: - Corner Radius

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let full: CGFloat = 999
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Shadows
    // Apple HIG-aligned: shadows should barely suggest elevation.
    // In dark mode these naturally render darker — verify both appearances.

    enum Shadow {
        /// Subtle card shadow — normal state
        static let card = (color: SwiftUI.Color.black.opacity(0.08), radius: CGFloat(12), y: CGFloat(4))
        /// Elevated card shadow — hover / focused state
        static let cardElevated = (color: SwiftUI.Color.black.opacity(0.15), radius: CGFloat(24), y: CGFloat(10))
        /// Popover / floating panel shadow
        static let floating = (color: SwiftUI.Color.black.opacity(0.12), radius: CGFloat(20), y: CGFloat(8))
        /// Window-level shadow (minimal)
        static let window = (color: SwiftUI.Color.black.opacity(0.02), radius: CGFloat(4), y: CGFloat(1))
    }

    // MARK: - Animation
    // Apple HIG-aligned: response=0.35 damping=0.7 for standard transitions.
    // Hover micro-interactions use easeOut 0.18s, not spring.

    enum Animation {
        /// Standard spring for UI transitions (response 0.35, damping 0.7)
        static let spring = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.7)
        /// Snappy spring for micro-interactions / quick state changes
        static let snappy = SwiftUI.Animation.spring(response: 0.25, dampingFraction: 0.65)
        /// Bouncy spring for prominent entrance transitions
        static let bouncy = SwiftUI.Animation.spring(response: 0.50, dampingFraction: 0.55)
        /// Gentle ease for opacity fades and content transitions
        static let fade = SwiftUI.Animation.easeOut(duration: 0.25)
        /// Fast ease-out for hover state transitions (Apple-style 180ms)
        static let easeOut = SwiftUI.Animation.easeOut(duration: 0.18)
        /// Standard ease-out for button hover feedback
        static let buttonHover = SwiftUI.Animation.easeOut(duration: 0.18)

        /// Standard transition: scale + opacity (sheets, modals)
        static let appear = AnyTransition.scale(scale: 0.95).combined(with: .opacity)
        /// Slide-up transition for toasts
        static let slideUp = AnyTransition.move(edge: .bottom).combined(with: .opacity)
    }

    // MARK: - Card

    enum Card {
        static let height: CGFloat = 64
        static let accentBarWidth: CGFloat = 4
        static let iconSize: CGFloat = 38
        static let cornerRadius: CGFloat = Radius.md

        // Elevation — Apple HIG: cards lift 2px on hover, do NOT scale.
        static let hoverLift: CGFloat = 2
        static let hoverShadowY: CGFloat = Shadow.cardElevated.y
        static let hoverShadowBlur: CGFloat = Shadow.cardElevated.radius
        static let hoverShadowOpacity: Double = 0.15
        static let normalShadowY: CGFloat = Shadow.card.y
        static let normalShadowBlur: CGFloat = Shadow.card.radius
        static let normalShadowOpacity: Double = 0.08

        // Entrance animation
        static let staggerDelay: Double = 0.04
        static let entranceResponse: Double = 0.35
        static let entranceDamping: Double = 0.7
    }
}

