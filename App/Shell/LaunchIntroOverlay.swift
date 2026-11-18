import PickupCore
import SwiftUI

public struct LaunchIntroOverlay: View {
    let palette: PickupPalette
    let onComplete: () -> Void

    @State private var progress: CGFloat = 0
    @State private var fadeOut: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(palette: PickupPalette, onComplete: @escaping () -> Void) {
        self.palette = palette
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            Color(hex: 0x080808).ignoresSafeArea()

            RadialGradient(
                colors: [Color(hex: 0xF4F3ED).opacity(0.10), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 240
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    // Monochrome frosted glass watch face with crisp alabaster ring
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(0.06)))
                        .frame(width: 214, height: 214)
                        .shadow(color: Color.white.opacity(0.10), radius: 28)

                    Circle()
                        .strokeBorder(Color(hex: 0xF4F3ED).opacity(0.55), lineWidth: 2.0)
                        .frame(width: 202, height: 202)

                    ForEach(0..<12, id: \.self) { idx in
                        Capsule()
                            .fill(Color(hex: 0xF4F3ED).opacity(idx % 3 == 0 ? 0.88 : 0.36))
                            .frame(width: idx % 3 == 0 ? 2.5 : 1.5, height: idx % 3 == 0 ? 12 : 7)
                            .offset(y: -84)
                            .rotationEffect(.degrees(Double(idx) * 30))
                    }

                    // Hour hand
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: 0xF4F3ED))
                        .frame(width: 4, height: 48)
                        .offset(y: -20)
                        .rotationEffect(.degrees(-120 + Double(progress) * 180))

                    // Minute hand
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: 0xDCDCD5).opacity(0.86))
                        .frame(width: 2.5, height: 70)
                        .offset(y: -30)
                        .rotationEffect(.degrees(-45 + Double(progress) * 410))

                    // Red-pen second hand (#F46862)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hex: 0xF46862))
                        .frame(width: 1.5, height: 78)
                        .offset(y: -26)
                        .rotationEffect(.degrees(Double(progress) * 720))

                    Circle()
                        .fill(Color(hex: 0xF4F3ED))
                        .frame(width: 10, height: 10)
                }
                .scaleEffect(0.88 + 0.12 * progress)
                .rotationEffect(.degrees(Double(-6 * (1 - progress))))

                HStack(spacing: 4) {
                    Text("Pickup")
                        .font(.system(size: 38, weight: .semibold, design: .serif))
                        .foregroundStyle(Color(hex: 0xF4F3ED))
                    Text(".")
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .foregroundStyle(Color(hex: 0xF46862))
                }
                .opacity(max(0, min(1, (progress - 0.48) * 2.4)))
            }
        }
        .environment(\.colorScheme, .dark)
        .opacity(fadeOut)
        .onAppear {
            if reduceMotion {
                onComplete()
                return
            }
            withAnimation(.easeOut(duration: 1.65)) {
                progress = 1
            }
            Task {
                try? await Task.sleep(for: .milliseconds(1750))
                withAnimation(.easeInOut(duration: 0.42)) {
                    fadeOut = 0
                }
                try? await Task.sleep(for: .milliseconds(430))
                onComplete()
            }
        }
    }
}
