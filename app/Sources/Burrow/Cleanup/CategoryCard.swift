import BurrowKit
import SwiftUI

private let visibleItemLimit = 60

extension CategoryGroup {
    var theme: Theme {
        switch self {
        case .system: .cleanup
        case .developer: .overview
        case .browser: .spaceLens
        case .apps: .uninstaller
        }
    }
}

struct CategoryCard: View {
    let category: CleanCategory
    @Environment(AppModel.self) private var model

    private var isExpanded: Bool { model.cleanup.expanded.contains(category.id) }

    var body: some View {
        let cleanup = model.cleanup
        let held = cleanup.isHeld(category)
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { cleanup.toggle(category) } label: {
                    SelectionMark(state: cleanup.state(of: category), theme: category.group.theme)
                }
                .buttonStyle(.plain)
                .disabled(held)

                SymbolTile(symbol: category.symbol, theme: category.group.theme, size: 38)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(EngineText.categoryName(category))
                            .font(.system(size: 14, weight: .semibold))
                        if category.action == .delete {
                            Tag(text: "Permanent", color: .orange)
                        }
                        if category.partial {
                            Tag(text: "Partial", color: .yellow)
                        }
                    }
                    Text(EngineText.categorySummary(category)).caption()
                        .lineLimit(1)
                }
                Spacer(minLength: 12)

                if held {
                    Button("Quit \(category.heldBy.joined(separator: ", "))") {
                        cleanup.quitOwners(of: category)
                    }
                    .buttonStyle(.glassCapsule)
                    .help("\(category.heldBy.joined(separator: ", ")) is running. Quit it to clean this safely.")
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteFormat.string(category.bytes))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("\(category.items.count) items").caption()
                }
                .opacity(held ? 0.5 : 1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture { toggleExpanded() }

            if isExpanded {
                Divider().overlay(.white.opacity(0.08))
                ItemList(category: category, disabled: held)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .foregroundStyle(.white)
        .glassPanel(radius: 18)
        .animation(.smooth(duration: 0.3), value: isExpanded)
    }

    private func toggleExpanded() {
        if isExpanded {
            model.cleanup.expanded.remove(category.id)
        } else {
            model.cleanup.expanded.insert(category.id)
        }
    }
}

private struct ItemList: View {
    let category: CleanCategory
    let disabled: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let cleanup = model.cleanup
        let home = cleanup.report?.home ?? NSHomeDirectory()
        VStack(spacing: 0) {
            ForEach(category.items.prefix(visibleItemLimit)) { item in
                HStack(spacing: 12) {
                    Button { cleanup.toggle(item) } label: {
                        SelectionMark(state: cleanup.selection.contains(item.path) && !disabled ? .on : .off, theme: category.group.theme)
                            .scaleEffect(0.85)
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(item.path.replacingOccurrences(of: home, with: "~"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(item.modifiedDate, format: .relative(presentation: .named))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(ByteFormat.string(item.bytes))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 76, alignment: .trailing)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .contextMenu {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                    }
                }
            }
            if category.items.count > visibleItemLimit {
                Text("+ \(category.items.count - visibleItemLimit) more items")
                    .caption()
                    .padding(10)
            }
        }
        .padding(.vertical, 6)
    }
}

struct Tag: View {
    let text: LocalizedStringKey
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold))
            .textCase(.uppercase)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.22), in: Capsule())
            .foregroundStyle(color)
    }
}
