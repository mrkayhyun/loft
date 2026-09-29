import BurrowKit
import SwiftUI

/// Idle state: explain what will be scanned and offer the big Scan button.
struct ScanIntroView: View {
    @Environment(AppModel.self) private var model

    private let coverage: [(symbol: String, title: LocalizedStringKey, theme: Theme)] = [
        ("internaldrive", "App caches & logs", .cleanup),
        ("hammer", "Xcode & simulators", .overview),
        ("shippingbox", "Package managers", .uninstaller),
        ("globe", "Browser caches", .spaceLens),
    ]

    var body: some View {
        VStack(spacing: 34) {
            Spacer()
            VStack(spacing: 12) {
                Text("Find space you can safely reclaim")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("A read-only scan. Nothing is removed until you review it.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)

            HeroButton(title: "Scan", theme: .cleanup, diameter: 150) {
                model.cleanup.scan()
            }

            HStack(spacing: 14) {
                ForEach(coverage, id: \.symbol) { entry in
                    HStack(spacing: 10) {
                        SymbolTile(symbol: entry.symbol, theme: entry.theme, size: 28)
                        Text(entry.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassPanel(radius: 14)
                }
            }
            Spacer()
            Label("Protected: documents, iCloud, keychains, password managers and running apps.", systemImage: "lock.shield")
                .caption()
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
    }
}

/// Scanning state: progress ring with a live byte counter.
struct ScanningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cleanup = model.cleanup
        VStack(spacing: 30) {
            Spacer()
            RingGauge(value: cleanup.progress, theme: .cleanup, lineWidth: 16) {
                VStack(spacing: 6) {
                    BytesDisplay(bytes: cleanup.foundBytes, size: 44)
                    Text("found so far").caption()
                }
            }
            .frame(width: 270, height: 270)

            VStack(spacing: 6) {
                Text("Scanning…")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(EngineText.categoryName(id: cleanup.currentCategory))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: cleanup.currentCategory)
            }
            .foregroundStyle(.white)

            Button("Stop") { cleanup.cancelScan() }
                .buttonStyle(.glassCapsule)
            Spacer()
        }
    }
}

/// Cleaning state: item-level progress and bytes freed.
struct CleaningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cleanup = model.cleanup
        let fraction = cleanup.cleanTotal == 0 ? 0 : Double(cleanup.cleanedCount) / Double(cleanup.cleanTotal)
        VStack(spacing: 30) {
            Spacer()
            RingGauge(value: fraction, theme: .cleanup, lineWidth: 16) {
                VStack(spacing: 6) {
                    BytesDisplay(bytes: cleanup.freedSoFar, size: 44)
                    Text("freed").caption()
                }
            }
            .frame(width: 270, height: 270)
            VStack(spacing: 6) {
                Text("Cleaning \(cleanup.cleanedCount) of \(cleanup.cleanTotal)")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(cleanup.currentItem)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            Spacer()
        }
    }
}
