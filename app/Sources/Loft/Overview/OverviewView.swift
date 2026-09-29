import LoftKit
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                greeting
                hero
                LazyVGrid(columns: columns, spacing: 16) {
                    reclaimableCard
                    memoryCard
                    cpuCard
                    lifetimeCard
                }
            }
            .padding(32)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .onAppear {
            model.monitor.acquire()
            model.refreshVolume()
        }
        .onDisappear { model.monitor.release() }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.greetingText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text(Host.current().localizedName ?? "Your Mac")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var hero: some View {
        HStack(spacing: 40) {
            RingGauge(value: model.volume?.fraction ?? 0, theme: .overview, lineWidth: 18) {
                VStack(spacing: 4) {
                    BytesDisplay(bytes: model.volume?.available ?? 0, size: 40)
                    Text("available").caption()
                }
            }
            .frame(width: 230, height: 230)

            VStack(alignment: .leading, spacing: 14) {
                Text("Keep your Mac feeling new")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Smart Clean finds caches, logs and developer leftovers that are safe to remove. Everything is checked twice and goes to the Trash first.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                if let volume = model.volume {
                    Label("\(ByteFormat.string(volume.used)) used of \(ByteFormat.string(volume.total)) on \(volume.name)", systemImage: "internaldrive")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)

            HeroButton(title: "Scan", theme: .cleanup, diameter: 116) {
                model.startSmartScan()
            }
            .padding(.trailing, 12)
        }
        .card(padding: 32, radius: 28)
    }

    private var reclaimableCard: some View {
        StatCard(
            title: "Reclaimable",
            value: model.cleanup.report.map { ByteFormat.string($0.totalBytes) } ?? "—",
            detail: model.cleanup.report == nil ? String(localized: "Run a scan to find out") : String(localized: "Found by the last scan"),
            symbol: "wand.and.stars",
            theme: .cleanup
        )
    }

    private var memoryCard: some View {
        let memory = model.monitor.latest?.memory
        return StatCard(
            title: "Memory",
            value: memory.map { "\(Int(($0.fraction * 100).rounded()))%" } ?? "—",
            detail: memory.map { String(localized: "\(ByteFormat.string($0.used)) of \(ByteFormat.string($0.total))") } ?? String(localized: "Measuring…"),
            symbol: "memorychip",
            theme: .monitor
        )
    }

    private var cpuCard: some View {
        let cpu = model.monitor.latest?.cpu
        return StatCard(
            title: "Processor",
            value: cpu.map { "\(Int($0.usage.rounded()))%" } ?? "—",
            detail: cpu.map { String(localized: "\($0.cores.count) cores") } ?? String(localized: "Measuring…"),
            symbol: "cpu",
            theme: .uninstaller
        )
    }

    private var lifetimeCard: some View {
        StatCard(
            title: "Cleaned so far",
            value: ByteFormat.string(model.cleanup.lifetimeFreed),
            detail: String(localized: "Across all Loft cleans"),
            symbol: "leaf",
            theme: .spaceLens
        )
    }

    private static var greetingText: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: String(localized: "Good morning")
        case 12..<18: String(localized: "Good afternoon")
        default: String(localized: "Good evening")
        }
    }
}

struct StatCard: View {
    let title: LocalizedStringKey
    let value: String
    let detail: String
    let symbol: String
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SymbolTile(symbol: symbol, theme: theme, size: 30)
                Spacer()
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail).caption()
                .lineLimit(1)
        }
        .animation(.snappy, value: value)
        .card(padding: 18)
    }
}
