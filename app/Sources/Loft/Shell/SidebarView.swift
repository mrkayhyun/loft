import LoftKit
import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppSection
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: optionalSelection) {
            Section {
                ForEach(AppSection.allCases) { section in
                    SidebarRow(section: section, badge: badge(for: section))
                        .tag(section)
                }
            } header: {
                BrandHeader()
                    .padding(.bottom, 10)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if let volume = model.volume {
                DiskFooter(volume: volume)
                    .padding(12)
            }
        }
    }

    private var optionalSelection: Binding<AppSection?> {
        Binding(get: { selection }, set: { if let value = $0 { selection = value } })
    }

    private func badge(for section: AppSection) -> String? {
        switch section {
        case .cleanup:
            model.cleanup.report.map { ByteFormat.string($0.totalBytes) }
        case .uninstaller:
            model.uninstaller.apps.isEmpty ? nil : "\(model.uninstaller.apps.count)"
        default:
            nil
        }
    }
}

private struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.overview.gradient)
                LoftMark()
                    .padding(5)
            }
            .frame(width: 30, height: 30)
            .shadow(color: Theme.overview.primary.opacity(0.5), radius: 6, y: 2)
            Text("Loft")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .textCase(nil)
        .padding(.top, 6)
    }
}

private struct SidebarRow: View {
    let section: AppSection
    let badge: String?

    var body: some View {
        HStack(spacing: 10) {
            SymbolTile(symbol: section.symbol, theme: section.theme, size: 26)
            Text(section.title)
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 4)
            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct DiskFooter: View {
    let volume: VolumeInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "internaldrive.fill")
                    .foregroundStyle(.secondary)
                Text(volume.name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule()
                        .fill(Theme.overview.gradient)
                        .frame(width: proxy.size.width * volume.fraction)
                }
            }
            .frame(height: 6)
            Text("\(ByteFormat.string(volume.available)) available of \(ByteFormat.string(volume.total))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .glassPanel(radius: 14)
    }
}
