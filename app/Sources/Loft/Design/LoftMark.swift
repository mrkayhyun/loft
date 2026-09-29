import SwiftUI

/// Loft's brand mark: a gable roof over a skylight. Drawn from primitives so it
/// can be used as a logo (SF Symbols may not be). Geometry matches
/// scripts/make-icon.swift, expressed in a unit square with y pointing down.
struct LoftMark: View {
    var color: Color = .white

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Roof()
                    .stroke(color, style: StrokeStyle(lineWidth: side * 0.12, lineCap: .round, lineJoin: .round))
                Circle()
                    .fill(color)
                    .frame(width: side * 0.2, height: side * 0.2)
                    .position(x: side * 0.5, y: side * 0.6)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private struct Roof: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.66))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.24))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.66))
            return path
        }
    }
}
