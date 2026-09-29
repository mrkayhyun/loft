import SwiftUI

private let panelRadius: CGFloat = 20

/// Frosted panel: Liquid Glass on macOS 26+, material with a hairline before.
struct GlassPanel: ViewModifier {
    var radius: CGFloat = panelRadius
    var interactive = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
    }
}

extension View {
    func glassPanel(radius: CGFloat = panelRadius, interactive: Bool = false) -> some View {
        modifier(GlassPanel(radius: radius, interactive: interactive))
    }

    /// Standard padded card used across sections.
    func card(padding: CGFloat = 20, radius: CGFloat = panelRadius) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(radius: radius)
    }
}
