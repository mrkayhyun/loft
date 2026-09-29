import BurrowKit
import SwiftUI

/// Large animated byte count: number in display weight, unit smaller.
struct BytesDisplay: View {
    let bytes: UInt64
    var size: CGFloat = 64

    var body: some View {
        let parts = ByteFormat.parts(bytes)
        HStack(alignment: .firstTextBaseline, spacing: size * 0.08) {
            Text(parts.value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(bytes)))
            Text(parts.unit)
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .animation(.snappy, value: bytes)
    }
}

/// Section title block used at the top of every screen.
struct SectionHeader<Trailing: View>: View {
    let section: AppSection
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SymbolTile(symbol: section.symbol, theme: section.theme, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(section.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            trailing()
        }
        .foregroundStyle(.white)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(section: AppSection) {
        self.init(section: section) { EmptyView() }
    }
}

/// Secondary caption style on dark backgrounds.
extension View {
    func caption() -> some View {
        self.font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
    }
}
