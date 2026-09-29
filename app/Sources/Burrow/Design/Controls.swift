import SwiftUI

/// The big round call-to-action (Scan, Clean) with a pulsing halo.
struct HeroButton: View {
    let title: LocalizedStringKey
    let theme: Theme
    var diameter: CGFloat = 132
    var disabled = false
    let action: () -> Void

    @State private var hovering = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(theme.primary.opacity(0.25))
                    .frame(width: diameter * 1.35, height: diameter * 1.35)
                    .scaleEffect(pulse ? 1.08 : 0.94)
                    .opacity(pulse ? 0.2 : 0.55)
                    .blur(radius: 6)
                Circle()
                    .fill(theme.gradient)
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
                    .overlay(
                        Circle()
                            .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                            .padding(6)
                    )
                    .shadow(color: theme.primary.opacity(0.7), radius: hovering ? 34 : 22, y: 8)
                    .frame(width: diameter, height: diameter)
                Text(title)
                    .font(.system(size: diameter * 0.17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .scaleEffect(hovering && !disabled ? 1.04 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: hovering)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// Capsule button on glass, used for secondary actions.
struct GlassCapsuleStyle: ButtonStyle {
    var prominent = false
    var theme: Theme = .cleanup

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .background {
                if prominent {
                    Capsule().fill(theme.gradient)
                        .shadow(color: theme.primary.opacity(0.5), radius: 10, y: 3)
                }
            }
            .modifier(CapsuleGlassIfNeeded(enabled: !prominent))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct CapsuleGlassIfNeeded: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular.interactive(), in: Capsule())
            } else {
                content.background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
            }
        } else {
            content
        }
    }
}

extension ButtonStyle where Self == GlassCapsuleStyle {
    static var glassCapsule: GlassCapsuleStyle { GlassCapsuleStyle() }
    static func prominentCapsule(_ theme: Theme) -> GlassCapsuleStyle {
        GlassCapsuleStyle(prominent: true, theme: theme)
    }
}

/// SF Symbol inside a gradient squircle, like a miniature app icon.
struct SymbolTile: View {
    let symbol: String
    let theme: Theme
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(theme.gradient)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.8)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            )
            .frame(width: size, height: size)
            .shadow(color: theme.primary.opacity(0.35), radius: 6, y: 2)
    }
}

/// Tri-state checkbox that matches the glass aesthetic.
struct SelectionMark: View {
    let state: TriState
    let theme: Theme

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(state == .off ? 0.35 : 0), lineWidth: 1.5)
            if state != .off {
                Circle().fill(theme.gradient)
                Image(systemName: state == .on ? "checkmark" : "minus")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 20, height: 20)
        .contentTransition(.symbolEffect(.replace))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: state)
    }
}
