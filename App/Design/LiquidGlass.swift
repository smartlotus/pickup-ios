import SwiftUI

/// Provides native iOS 26 Liquid Glass containers and surfaces with rich multi-layer frosted fallback on iOS 18.
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
        fallbackSurface: Color? = nil,
        fallbackStroke: Color = Color.white.opacity(0.22)
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
            let resolvedSurface = fallbackSurface ?? (tint?.opacity(0.92) ?? Color.white.opacity(0.06))
            self
                .background(.ultraThinMaterial, in: Capsule())
                .background(resolvedSurface, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [fallbackStroke, Color.primary.opacity(0.08)],
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
        fallbackSurface: Color? = nil,
        fallbackStroke: Color = Color.white.opacity(0.20)
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
            let resolvedSurface = fallbackSurface ?? (tint?.opacity(0.92) ?? Color.white.opacity(0.05))
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            self
                .background(.ultraThinMaterial, in: shape)
                .background(resolvedSurface, in: shape)
                .overlay(
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [fallbackStroke, Color.primary.opacity(0.08)],
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
        fallbackSurface: Color? = nil,
        fallbackStroke: Color = Color.white.opacity(0.22)
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
            let resolvedSurface = fallbackSurface ?? (tint?.opacity(0.92) ?? Color.white.opacity(0.06))
            self
                .background(.ultraThinMaterial, in: Circle())
                .background(resolvedSurface, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [fallbackStroke, Color.primary.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
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

/// Translucent frosted glass editorial card with 1px specular border and monochrome depth.
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
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content()
            .padding(padding)
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(palette.glassFill))
            }
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                isPinned ? palette.accent.opacity(0.45) : palette.specularTop,
                                palette.specularBottom,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: palette.isDark ? Color.black.opacity(0.32) : Color.black.opacity(0.06),
                radius: palette.isDark ? 16 : 12,
                x: 0,
                y: palette.isDark ? 8 : 6
            )
    }
}
