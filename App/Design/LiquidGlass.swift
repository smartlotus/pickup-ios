import SwiftUI

/// Provides native iOS 26 Liquid Glass containers and surfaces with rich multi-layer fallback on iOS 18.
public struct PickupGlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    public init(spacing: CGFloat = 14, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

public extension View {
    @ViewBuilder
    func pickupGlassCapsule(
        tint: Color? = nil,
        interactive: Bool = true,
        fallbackSurface: Color = Color.white.opacity(0.08),
        fallbackStroke: Color = Color.white.opacity(0.18)
    ) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                self.glassEffect(
                    interactive ? .regular.tint(tint).interactive() : .regular.tint(tint),
                    in: Capsule()
                )
            } else {
                self.glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: Capsule()
                )
            }
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .background(fallbackSurface, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [fallbackStroke.opacity(1.2), fallbackStroke.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        }
    }

    @ViewBuilder
    func pickupGlassRect(
        cornerRadius: CGFloat = 22,
        tint: Color? = nil,
        interactive: Bool = false,
        fallbackSurface: Color = Color.white.opacity(0.06),
        fallbackStroke: Color = Color.white.opacity(0.14)
    ) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                self.glassEffect(
                    interactive ? .regular.tint(tint).interactive() : .regular.tint(tint),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
            } else {
                self.glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
            }
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background(fallbackSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [fallbackStroke.opacity(1.1), fallbackStroke.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        }
    }

    @ViewBuilder
    func pickupGlassCircle(
        tint: Color? = nil,
        interactive: Bool = true,
        fallbackStroke: Color = Color.white.opacity(0.2)
    ) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                self.glassEffect(
                    interactive ? .regular.tint(tint).interactive() : .regular.tint(tint),
                    in: Circle()
                )
            } else {
                self.glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: Circle()
                )
            }
        } else {
            self
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(fallbackStroke, lineWidth: 1))
        }
    }

    @ViewBuilder
    func pickupGlassIdentity(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func pickupMinimizeTabBarOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

/// Content card with tactile glass rim lighting without over-applying glass to long scrolling prose.
public struct PickupEditorialCard<Content: View>: View {
    let palette: PickupPalette
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 18
    var isPinned: Bool = false
    @ViewBuilder let content: () -> Content

    public init(
        palette: PickupPalette,
        cornerRadius: CGFloat = 22,
        padding: CGFloat = 18,
        isPinned: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.palette = palette
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.isPinned = isPinned
        self.content = content
    }

    public var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.cardSurface.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                (isPinned ? palette.gold.opacity(0.55) : Color.white.opacity(0.16)),
                                palette.hairline.opacity(0.4),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 8)
    }
}
