import SwiftUI

/// Circular gauge with a gradient stroke and a soft glow at the leading edge.
struct RingGauge<Label: View>: View {
    var value: Double
    var theme: Theme
    var lineWidth: CGFloat = 14
    @ViewBuilder var label: () -> Label

    private var clamped: Double { min(max(value, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(theme.angular, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: theme.primary.opacity(0.6), radius: lineWidth * 0.8)
            label()
        }
        .animation(.spring(response: 0.8, dampingFraction: 0.85), value: clamped)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("\(Int(clamped * 100)) percent"))
    }
}

/// Indeterminate spinning arc used while work has no measurable progress.
struct SpinningArc: View {
    var theme: Theme
    var lineWidth: CGFloat = 6
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(theme.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}
