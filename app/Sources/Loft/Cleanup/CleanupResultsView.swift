import LoftKit
import SwiftUI

struct CleanupResultsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete = false

    var body: some View {
        let cleanup = model.cleanup
        VStack(spacing: 0) {
            summary
                .padding(.horizontal, 32)
                .padding(.top, 20)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22, pinnedViews: []) {
                    if let report = cleanup.report, report.totalErrors > 0 {
                        FullDiskAccessBanner(unreadable: report.totalErrors)
                    }
                    ForEach(CleanupModel.groupOrder, id: \.self) { group in
                        let categories = cleanup.categories(in: group)
                        if !categories.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.title.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(1.2)
                                    .foregroundStyle(.white.opacity(0.5))
                                    .padding(.leading, 4)
                                ForEach(categories) { category in
                                    CategoryCard(category: category)
                                }
                            }
                        }
                    }
                }
                .padding(32)
            }
            .scrollIndicators(.automatic)
        }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmDelete) {
            Button("Clean and Empty Trash", role: .destructive) { cleanup.clean() }
        } message: {
            Text("Items already in the Trash will be permanently deleted. Everything else is moved to the Trash.")
        }
    }

    private var summary: some View {
        let cleanup = model.cleanup
        let total = cleanup.report?.totalBytes ?? 0
        let categoryCount = cleanup.report?.categories.count ?? 0
        return HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Selected to clean")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                BytesDisplay(bytes: cleanup.selectedBytes, size: 54)
                Text("\(ByteFormat.string(total)) found in \(categoryCount) categories · scanned in \(Self.seconds(cleanup.report?.durationMs ?? 0))")
                    .caption()
            }
            Spacer()
            HeroButton(title: "Clean", theme: .cleanup, diameter: 108, disabled: cleanup.selectedBytes == 0) {
                if cleanup.selectionIncludesPermanentDelete {
                    confirmDelete = true
                } else {
                    cleanup.clean()
                }
            }
        }
        .card(padding: 26, radius: 26)
    }

    private static func seconds(_ milliseconds: UInt64) -> String {
        String(format: "%.1fs", Double(milliseconds) / 1000)
    }
}

private struct FullDiskAccessBanner: View {
    let unreadable: UInt64
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")

    var body: some View {
        HStack(spacing: 14) {
            SymbolTile(symbol: "lock.open", theme: .spaceLens, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Some folders couldn't be read")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(unreadable) items need Full Disk Access to be measured. Grant it for a deeper clean.")
                    .caption()
            }
            Spacer()
            Button("Open Settings") {
                if let url = Self.settingsURL { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(.glassCapsule)
        }
        .foregroundStyle(.white)
        .card(padding: 16, radius: 16)
    }
}
