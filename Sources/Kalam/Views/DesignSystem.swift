import SwiftUI

// Design System
// Retro-inspired but modern color palette and typography

struct DesignSystem {
    // MARK: - Colors

    struct Colors {
        // Primary
        static let primary = Color(hex: "6B7280")
        static let accent = Color(hex: "8B7FA8")
        // Deeper "ink" purple — enough contrast to carry white button text
        static let ink = Color(hex: "6E5F92")

        // Backgrounds
        static let backgroundLight = Color(hex: "FAFAF9")
        static let backgroundDark = Color(hex: "1C1C1E")
        static let cardLight = Color.white
        static let cardDark = Color(hex: "2C2C2E")

        // Text
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary

        // Status
        static let success = Color(hex: "34C759")
        static let warning = Color(hex: "FF9500")
        static let error = Color(hex: "FF3B30")

        // Recording indicator
        static let recordingRed = Color(hex: "FF3B30")

        // Subtle accents
        static let subtleBlue = Color(hex: "5B8EF4")
        static let subtlePurple = Color(hex: "8B7FA8")
    }

    // MARK: - Typography

    struct Typography {
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .default)
        static let title1 = Font.system(size: 28, weight: .bold, design: .default)
        static let title2 = Font.system(size: 22, weight: .bold, design: .default)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .default)
        static let headline = Font.system(size: 17, weight: .semibold, design: .default)
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let callout = Font.system(size: 16, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
        static let footnote = Font.system(size: 13, weight: .regular, design: .default)
        static let caption = Font.system(size: 12, weight: .regular, design: .default)

        // Transcript text. Must stay the default system design: SF Pro and the
        // system Devanagari face are metrically harmonized, so mixed
        // Hindi+English reads as one voice. Monospace has no Devanagari and
        // splices in a mismatched fallback — never use it here.
        static let transcription = Font.system(size: 17, weight: .regular, design: .default)
    }

    // MARK: - Spacing

    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius

    struct CornerRadius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: - Animations

    struct Animation {
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.5)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Custom Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = DesignSystem.Colors.ink
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.headline)
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(tint)
            .cornerRadius(DesignSystem.CornerRadius.md)
            .opacity(isEnabled ? 1.0 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.headline)
            .foregroundColor(DesignSystem.Colors.primary)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(DesignSystem.CornerRadius.md)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18))
            .foregroundColor(DesignSystem.Colors.primary)
            .frame(width: 36, height: 36)
            .background(Color.gray.opacity(configuration.isPressed ? 0.2 : 0.1))
            .cornerRadius(DesignSystem.CornerRadius.sm)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
    }
}
