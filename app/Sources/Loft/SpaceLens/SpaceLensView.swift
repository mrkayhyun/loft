import AppKit
import LoftKit
import SwiftUI

struct SpaceLensView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var space = model.space
        VStack(spacing: 16) {
            SectionHeader(section: .spaceLens) {
                HStack(spacing: 8) {
                    Button("Choose Folder…", systemImage: "folder") { chooseFolder() }
                    Button("Refresh", systemImage: "arrow.clockwise") { space.refresh() }
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glassCapsule)
            }
            PathBar()
            HStack(spacing: 16) {
                ZStack {
                    TreemapView(nodes: space.nodes, hovered: $space.hovered) { node in
                        space.open(node.path)
                    }
                    .padding(10)
                    if space.nodes.isEmpty {
                        LoadingOrError(loading: space.loading, error: space.error)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassPanel(radius: 22)

                SizeList()
                    .frame(width: 300)
            }
            HoverStatus()
        }
        .padding(.horizontal, 32)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .onAppear { space.start() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Analyze")
        if panel.runModal() == .OK, let url = panel.url {
            model.space.choose(url)
        }
    }
}

private struct PathBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let space = model.space
        HStack(spacing: 6) {
            Button { space.up() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!space.canGoUp)
            .glassPanel(radius: 8, interactive: true)

            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array(space.breadcrumbs.enumerated()), id: \.element.id) { index, crumb in
                        if index > 0 {
                            Image(systemName: "chevron.compact.right")
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        Button(crumb.name) { space.open(crumb.path) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12.5, weight: crumb.path == space.current ? .bold : .medium))
                            .foregroundStyle(.white.opacity(crumb.path == space.current ? 1 : 0.65))
                    }
                }
            }
            .scrollIndicators(.never)
            Spacer()
            if space.loading {
                SpinningArc(theme: .spaceLens, lineWidth: 2.5).frame(width: 14, height: 14)
            }
            Text(ByteFormat.string(space.total))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassPanel(radius: 14)
    }
}

private struct SizeList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let space = model.space
        let total = max(Double(space.total), 1)
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(space.nodes.prefix(200)) { node in
                    Button {
                        if node.isDir { space.open(node.path) }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Image(systemName: node.isDir ? "folder.fill" : "doc.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(node.isDir ? Theme.spaceLens.primary : .white.opacity(0.5))
                                Text(node.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                Text(ByteFormat.string(node.bytes))
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(Theme.spaceLens.gradient)
                                    .frame(width: max(proxy.size.width * Double(node.bytes) / total, 2))
                            }
                            .frame(height: 3)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(.white.opacity(space.hovered?.path == node.path ? 0.08 : 0))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in space.hovered = inside ? node : nil }
                }
            }
            .padding(6)
        }
        .scrollIndicators(.never)
        .foregroundStyle(.white)
        .glassPanel(radius: 22)
    }
}

private struct HoverStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let space = model.space
        HStack(spacing: 10) {
            if let node = space.hovered {
                Image(systemName: node.isDir ? "folder.fill" : "doc.fill")
                    .foregroundStyle(Theme.spaceLens.primary)
                Text(node.name).font(.system(size: 12, weight: .semibold))
                Text(ByteFormat.string(node.bytes)).caption()
                if space.total > 0 {
                    Text("\((Double(node.bytes) / Double(space.total)).formatted(.percent.precision(.fractionLength(1)))) of this folder").caption()
                }
                if node.files > 0 {
                    Text("\(node.files.formatted()) files").caption()
                }
                Spacer()
                if node.isDir {
                    Text("Click to open").caption()
                }
            } else {
                Text("Hover a tile for details · click a folder to open it · right-click to reveal in Finder")
                    .caption()
                Spacer()
            }
        }
        .foregroundStyle(.white)
        .frame(height: 18)
        .animation(.easeOut(duration: 0.12), value: space.hovered)
    }
}

private struct LoadingOrError: View {
    let loading: Bool
    let error: String?

    var body: some View {
        VStack(spacing: 12) {
            if let error {
                Image(systemName: "lock.fill").font(.system(size: 30)).foregroundStyle(.orange)
                Text(error).caption().multilineTextAlignment(.center)
            } else if loading {
                SpinningArc(theme: .spaceLens).frame(width: 46, height: 46)
                Text("Measuring…").caption()
            } else {
                Text("This folder is empty").caption()
            }
        }
        .padding(30)
    }
}
