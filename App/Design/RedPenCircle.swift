import SwiftUI

/// Organic hand-drawn red pen circle (#F46862) matching Pickup's signature mark on "拾" and recorded calendar days.
public struct RedPenCircleShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let rx = rect.width * 0.46
        let ry = rect.height * 0.44

        path.move(to: CGPoint(x: cx + rx * 0.85, y: cy - ry * 0.55))
        path.addCurve(
            to: CGPoint(x: cx - rx * 0.92, y: cy - ry * 0.25),
            control1: CGPoint(x: cx + rx * 0.2, y: cy - ry * 1.15),
            control2: CGPoint(x: cx - rx * 0.85, y: cy - ry * 0.95)
        )
        path.addCurve(
            to: CGPoint(x: cx + rx * 0.15, y: cy + ry * 0.96),
            control1: CGPoint(x: cx - rx * 1.05, y: cy + ry * 0.52),
            control2: CGPoint(x: cx - rx * 0.35, y: cy + ry * 1.02)
        )
        path.addCurve(
            to: CGPoint(x: cx + rx * 0.98, y: cy - ry * 0.12),
            control1: CGPoint(x: cx + rx * 0.72, y: cy + ry * 0.88),
            control2: CGPoint(x: cx + rx * 1.08, y: cy + ry * 0.35)
        )
        path.addCurve(
            to: CGPoint(x: cx + rx * 0.55, y: cy - ry * 0.74),
            control1: CGPoint(x: cx + rx * 0.95, y: cy - ry * 0.45),
            control2: CGPoint(x: cx + rx * 0.78, y: cy - ry * 0.68)
        )
        return path
    }
}

public struct AnimatedRedPenMark: View {
    let color: Color
    var lineWidth: CGFloat = 2.1
    var animate: Bool = true
    @State private var trimEnd: CGFloat = 0

    public init(color: Color = Color(hex: 0xF46862), lineWidth: CGFloat = 2.1, animate: Bool = true) {
        self.color = color
        self.lineWidth = lineWidth
        self.animate = animate
    }

    public var body: some View {
        RedPenCircleShape()
            .trim(from: 0, to: animate ? trimEnd : 1)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .rotationEffect(.degrees(-10))
            .onAppear {
                if animate {
                    trimEnd = 0
                    withAnimation(.easeOut(duration: 0.75)) {
                        trimEnd = 1
                    }
                } else {
                    trimEnd = 1
                }
            }
    }
}
