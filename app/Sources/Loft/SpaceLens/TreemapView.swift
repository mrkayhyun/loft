import LoftKit
import SwiftUI

private let maxTiles = 120
private let tileGap: CGFloat = 3
private let labelMinWidth: CGFloat = 74
private let labelMinHeight: CGFloat = 38

/// Warm-to-cool palette for folders; files use a neutral slate.
private let folderPalette: [Color] = [
    Color(red: 1.0, green: 0.62, blue: 0.2),
    Color(red: 1.0, green: 0.42, blue: 0.32),
    Color(red: 0.95, green: 0.3, blue: 0.5),
    Color(red: 0.7, green: 0.35, blue: 0.95),
    Color(red: 0.36, green: 0.5, blue: 1.0),
    Color(red: 0.2, green: 0.75, blue: 0.85),
    Color(red: 0.3, green: 0.82, blue: 0.5),
    Color(red: 0.95, green: 0.8, blue: 0.3),
]
private let fileColor = Color(red: 0.42, green: 0.47, blue: 0.56)

struct TreemapView: View {
    let nodes: [DiskNode]
    @Binding var hovered: DiskNode?
    let open: (DiskNode) -> Void

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let shown = Array(nodes.prefix(maxTiles))
            let tiles = Treemap.layout(shown.map { (id: $0.path, value: Double($0.bytes)) }, in: bounds)
            let lookup = Dictionary(uniqueKeysWithValues: shown.enumerated().map { ($1.path, ($0, $1)) })
            ZStack(alignment: .topLeading) {
                ForEach(tiles, id: \.id) { tile in
                    if let (index, node) = lookup[tile.id] {
                        TreemapTile(node: node, color: color(for: node, index: index), isHovered: hovered?.path == node.path)
                            .frame(width: max(tile.rect.width - tileGap, 1), height: max(tile.rect.height - tileGap, 1))
                            .offset(x: tile.rect.minX, y: tile.rect.minY)
                            .onHover { inside in
                                if inside { hovered = node } else if hovered?.path == node.path { hovered = nil }
                            }
                            .onTapGesture { if node.isDir { open(node) } }
                            .contextMenu {
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
                                }
                            }
                    }
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: tiles)
        }
    }

    private func color(for node: DiskNode, index: Int) -> Color {
        node.isDir ? folderPalette[index % folderPalette.count] : fileColor
    }
}

private struct TreemapTile: View {
    let node: DiskNode
    let color: Color
    let isHovered: Bool

    var body: some View {
        GeometryReader { proxy in
            let shape = RoundedRectangle(cornerRadius: min(8, proxy.size.width / 4, proxy.size.height / 4), style: .continuous)
            ZStack(alignment: .topLeading) {
                shape
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(isHovered ? 0.95 : 0.78), color.opacity(isHovered ? 0.75 : 0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(shape.strokeBorder(.white.opacity(isHovered ? 0.6 : 0.14), lineWidth: isHovered ? 1.5 : 0.8))
                if proxy.size.width >= labelMinWidth && proxy.size.height >= labelMinHeight {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            if node.isDir {
                                Image(systemName: "folder.fill").font(.system(size: 10))
                            }
                            Text(node.name)
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        Text(ByteFormat.string(node.bytes))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .padding(8)
                }
            }
        }
        .scaleEffect(isHovered ? 1.0 : 0.995)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
