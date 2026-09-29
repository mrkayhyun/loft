import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView(selection: $model.section)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 290)
        } detail: {
            ZStack {
                SectionBackground(theme: model.section.theme)
                detail
                    .id(model.section)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
            .animation(.smooth(duration: 0.35), value: model.section)
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if model.engine == nil {
            EngineMissingView()
        } else {
            switch model.section {
            case .overview: OverviewView()
            case .cleanup: CleanupView()
            case .uninstaller: UninstallerView()
            case .spaceLens: SpaceLensView()
            case .monitor: MonitorView()
            }
        }
    }
}

private struct EngineMissingView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)
            Text("Loft's engine is missing")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Reinstall Loft, or build it with scripts/build-app.sh.")
                .caption()
        }
        .foregroundStyle(.white)
        .card(padding: 40)
        .frame(maxWidth: 440)
    }
}
