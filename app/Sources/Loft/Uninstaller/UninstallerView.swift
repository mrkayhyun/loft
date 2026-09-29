import LoftKit
import SwiftUI

struct UninstallerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let uninstaller = model.uninstaller
        VStack(spacing: 18) {
            SectionHeader(section: .uninstaller) {
                if uninstaller.loading {
                    HStack(spacing: 8) {
                        SpinningArc(theme: .uninstaller, lineWidth: 2.5).frame(width: 14, height: 14)
                        Text("Measuring apps…").caption()
                    }
                } else if !uninstaller.apps.isEmpty {
                    Text("\(uninstaller.apps.count) apps · \(ByteFormat.string(uninstaller.totalAppBytes))")
                        .caption()
                }
            }
            HStack(alignment: .top, spacing: 18) {
                AppListPanel()
                    .frame(width: 330)
                Group {
                    if let app = uninstaller.selectedApp {
                        AppDetailView(app: app)
                            .id(app.id)
                    } else {
                        EmptyDetail(loading: uninstaller.loading, error: uninstaller.loadError)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassPanel(radius: 24)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 20)
        .padding(.bottom, 28)
        .onAppear { uninstaller.load() }
    }
}

private struct AppListPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var uninstaller = model.uninstaller
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                TextField("Search apps", text: $uninstaller.search)
                    .textFieldStyle(.plain)
                Picker("Sort", selection: $uninstaller.sort) {
                    ForEach(UninstallerModel.SortOrder.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassPanel(radius: 12)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(uninstaller.visibleApps) { app in
                        AppRow(app: app, selected: uninstaller.selectedID == app.id)
                            .onTapGesture { uninstaller.selectedID = app.id }
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.never)
            .glassPanel(radius: 18)
        }
    }
}

private struct AppRow: View {
    let app: AppInfo
    let selected: Bool
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        let uninstaller = model.uninstaller
        HStack(spacing: 11) {
            Image(nsImage: uninstaller.icon(for: app))
                .resizable()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if uninstaller.isRunning(app) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                    }
                    Text(app.version.isEmpty ? app.bundleId : app.version)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if !app.isRemovable {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Text(uninstaller.sizes[app.path].map(ByteFormat.string) ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(selected ? AnyShapeStyle(Theme.uninstaller.gradient.opacity(0.55)) : AnyShapeStyle(.white.opacity(hovering ? 0.06 : 0)))
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct EmptyDetail: View {
    let loading: Bool
    let error: String?

    var body: some View {
        VStack(spacing: 12) {
            if let error {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.orange)
                Text(error).caption().multilineTextAlignment(.center)
            } else if loading {
                SpinningArc(theme: .uninstaller).frame(width: 44, height: 44)
                Text("Finding your apps…").caption()
            } else {
                Image(systemName: "hand.point.left").font(.system(size: 36)).foregroundStyle(.white.opacity(0.4))
                Text("Choose an app to see everything it installed").caption()
            }
        }
        .padding(40)
    }
}
