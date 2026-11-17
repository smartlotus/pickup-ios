import SwiftUI

public struct PickupPalette: Sendable {
    public let style: PickupThemeStyle
    public let background: Color
    public let secondaryBackground: Color
    public let cardSurface: Color
    public let elevatedSurface: Color
    public let accent: Color
    public let secondaryAccent: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let tertiaryText: Color
    public let hairline: Color
    public let redPen: Color
    public let gold: Color
    public let tintButtonForeground: Color

    public static func palette(for style: PickupThemeStyle) -> PickupPalette {
        switch style {
        case .monochrome:
            return PickupPalette(
                style: .monochrome,
                background: Color(hex: 0x060606),
                secondaryBackground: Color(hex: 0x0C0C0C),
                cardSurface: Color(hex: 0x111111),
                elevatedSurface: Color(hex: 0x191919),
                accent: Color(hex: 0xF4F3ED),
                secondaryAccent: Color.white.opacity(0.75),
                primaryText: Color(hex: 0xF4F3ED),
                secondaryText: Color(hex: 0xA2A19A),
                tertiaryText: Color(hex: 0x6E6D68),
                hairline: Color.white.opacity(0.14),
                redPen: Color(hex: 0xF46862),
                gold: Color(hex: 0xC5A86A),
                tintButtonForeground: Color(hex: 0x0A0A0A)
            )
        case .purpleDark:
            return PickupPalette(
                style: .purpleDark,
                background: Color(hex: 0x0D0C12),
                secondaryBackground: Color(hex: 0x14121D),
                cardSurface: Color(hex: 0x1B1924),
                elevatedSurface: Color(hex: 0x242031),
                accent: Color(hex: 0xA78BFA),
                secondaryAccent: Color(hex: 0x7C4DFF),
                primaryText: Color(hex: 0xF4F3ED),
                secondaryText: Color(hex: 0xB3AFC0),
                tertiaryText: Color(hex: 0x7A758B),
                hairline: Color(hex: 0xA78BFA).opacity(0.18),
                redPen: Color(hex: 0xF46862),
                gold: Color(hex: 0xC5A86A),
                tintButtonForeground: Color(hex: 0x0D0B14)
            )
        }
    }

    public func editorialFont(size: CGFloat, weight: Font.Weight = .semibold, typography: PickupTypographyStyle) -> Font {
        switch typography {
        case .editorialSerif:
            return .system(size: size, weight: weight, design: .serif)
        case .cleanSans:
            return .system(size: size, weight: weight, design: .default)
        }
    }

    public func bodyFont(size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

public extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

public struct PickupAmbientBackdrop: View {
    let palette: PickupPalette

    public init(palette: PickupPalette) {
        self.palette = palette
    }

    public var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            if palette.style == .purpleDark {
                RadialGradient(
                    colors: [
                        Color(hex: 0x7C4DFF).opacity(0.22),
                        Color(hex: 0x673AB7).opacity(0.08),
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 460
                )
                .ignoresSafeArea()
                RadialGradient(
                    colors: [
                        palette.redPen.opacity(0.08),
                        .clear
                    ],
                    center: .bottomLeading,
                    startRadius: 10,
                    endRadius: 360
                )
                .ignoresSafeArea()
            } else {
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 420
                )
                .ignoresSafeArea()
            }
        }
    }
}
