import SwiftUI

/// Slowly breathing mesh gradient that gives each section its colour.
struct SectionBackground: View {
    let theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period: Double = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.points(at: timeline.date.timeIntervalSinceReferenceDate),
                colors: theme.mesh
            )
        }
        .overlay {
            RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: 200, endRadius: 900)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: theme.primary)
    }

    /// Control points drift gently around a 3×3 grid; corners stay pinned.
    private static func points(at time: TimeInterval) -> [SIMD2<Float>] {
        let phase = Float(sin(time * 2 * .pi / period))
        let drift = Float(cos(time * 2 * .pi / (period * 1.3)))
        let top = SIMD2<Float>(0.5 + 0.08 * drift, 0)
        let left = SIMD2<Float>(0, 0.5 + 0.06 * phase)
        let center = SIMD2<Float>(0.5 + 0.1 * phase, 0.45 + 0.08 * drift)
        let right = SIMD2<Float>(1, 0.5 - 0.06 * phase)
        let bottom = SIMD2<Float>(0.5 - 0.08 * drift, 1)
        return [
            SIMD2(0, 0), top, SIMD2(1, 0),
            left, center, right,
            SIMD2(0, 1), bottom, SIMD2(1, 1),
        ]
    }
}
