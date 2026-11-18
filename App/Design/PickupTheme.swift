import PickupCore
import SwiftUI

public struct PickupPalette: Sendable {
    public let style: PickupThemeStyle
    public let background: Color
    public let secondaryBackground: Color
    public let cardSurface: Color
    public let elevatedSurface: Color
    public let glassFill: Color
    public let accent: Color
    public let secondaryAccent: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let tertiaryText: Color
    public let hairline: Color
    public let specularTop: Color
    public let specularBottom: Color
    public let redPen: Color
    public let highlight: Color
    public let tintButtonForeground: Color
    public let isDark: Bool

    public static func palette(for style: PickupThemeStyle) -> PickupPalette {
        switch style {
        case .monochrome:
            return PickupPalette(
                style: .monochrome,
                background: Color(hex: 0x080808),
                secondaryBackground: Color(hex: 0x0E0E0E),
                cardSurface: Color(hex: 0x121212),
                elevatedSurface: Color.white.opacity(0.07),
                glassFill: Color.white.opacity(0.048),
                accent: Color(hex: 0xF4F3ED),
                secondaryAccent: Color.white.opacity(0.72),
                primaryText: Color(hex: 0xF4F3ED),
                secondaryText: Color(hex: 0xA2A19A),
                tertiaryText: Color(hex: 0x6E6D68),
                hairline: Color.white.opacity(0.11),
                specularTop: Color.white.opacity(0.24),
                specularBottom: Color.white.opacity(0.04),
                redPen: Color(hex: 0xF46862),
                highlight: Color(hex: 0xDCDCD5),
                tintButtonForeground: Color(hex: 0x0A0A0A),
                isDark: true
            )
        case .monochromeLight:
            return PickupPalette(
                style: .monochromeLight,
                background: Color(hex: 0xF5F4EF),
                secondaryBackground: Color(hex: 0xECEBE4),
                cardSurface: Color(hex: 0xFFFFFF),
                elevatedSurface: Color.black.opacity(0.045),
                glassFill: Color.white.opacity(0.68),
                accent: Color(hex: 0x111111),
                secondaryAccent: Color.black.opacity(0.72),
                primaryText: Color(hex: 0x111111),
                secondaryText: Color(hex: 0x5C5B55),
                tertiaryText: Color(hex: 0x8A8982),
                hairline: Color.black.opacity(0.10),
                specularTop: Color.white.opacity(0.95),
                specularBottom: Color.black.opacity(0.07),
                redPen: Color(hex: 0xD94E48),
                highlight: Color(hex: 0x3D3D38),
                tintButtonForeground: Color(hex: 0xF5F4EF),
                isDark: false
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
            if palette.isDark {
                // Soft silver & alabaster light beams over obsidian #080808 for frosted glass refraction
                RadialGradient(
                    colors: [
                        Color(hex: 0xF4F3ED).opacity(0.11),
                        Color.white.opacity(0.035),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 16,
                    endRadius: 460
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: [
                        Color(hex: 0xDCDCD5).opacity(0.08),
                        Color.white.opacity(0.02),
                        .clear
                    ],
                    center: UnitPoint(x: 0.88, y: 0.24),
                    startRadius: 12,
                    endRadius: 380
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: [
                        Color.white.opacity(0.045),
                        .clear
                    ],
                    center: .bottomLeading,
                    startRadius: 10,
                    endRadius: 360
                )
                .ignoresSafeArea()
            } else {
                // Crisp luminous pearl-white mist & subtle stone gradient over warm paper #F5F4EF
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        Color.white.opacity(0.45),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 16,
                    endRadius: 480
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: [
                        Color(hex: 0xDCDCD5).opacity(0.42),
                        Color(hex: 0xE6E5DE).opacity(0.16),
                        .clear
                    ],
                    center: UnitPoint(x: 0.86, y: 0.34),
                    startRadius: 20,
                    endRadius: 420
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: [
                        Color.white.opacity(0.75),
                        .clear
                    ],
                    center: .bottomLeading,
                    startRadius: 10,
                    endRadius: 380
                )
                .ignoresSafeArea()
            }
        }
    }
}
