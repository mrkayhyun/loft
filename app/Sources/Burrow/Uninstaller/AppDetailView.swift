import BurrowKit
import SwiftUI

struct AppDetailView: View {
    let app: AppInfo
    @Environment(AppModel.self) private var model
    @State private var confirming = false

    var body: some View {
        let uninstaller = model.uninstaller
        Group {
            switch uninstaller.phase {
            case .finished(let freed, let problems):
                UninstallDone(app: app, freed: freed, problems: problems)
            default:
                content
            }
        }
        .animation(.smooth, value: uninstaller.phase)
        .confirmationDialog("Uninstall \(app.name)?", isPresented: $confirming) {
            Button("Move to Trash", role: .destructive) { uninstaller.uninstall() }
        } message: {
            Text("\(app.name) and \(uninstaller.leftoverSelection.count) related items (\(ByteFormat.string(uninstaller.totalSelectedBytes))) will be moved to the Trash.")
        }
    }

    private var content: some View {
        let uninstaller = model.uninstaller
        return VStack(alignment: .leading, spacing: 20) {
            header
            banners
            Text("RELATED FILES")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.5))
            LeftoverList()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total to remove").caption()
                    Text(ByteFormat.string(uninstaller.totalSelectedBytes))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer()
                if case .failed(let message) = uninstaller.phase {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .frame(maxWidth: 260, alignment: .trailing)
                }
                Button {
                    confirming = true
                } label: {
                    HStack(spacing: 8) {
                        if uninstaller.phase == .working {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text("Uninstall")
                    }
                    .frame(minWidth: 110)
                }
                .buttonStyle(.prominentCapsule(.uninstaller))
                .disabled(!canUninstall)
                .opacity(canUninstall ? 1 : 0.45)
            }
        }
        .foregroundStyle(.white)
        .padding(28)
    }

    private var canUninstall: Bool {
        let uninstaller = model.uninstaller
        return app.isRemovable && !uninstaller.isRunning(app) && uninstaller.phase != .working
    }

    private var header: some View {
        let uninstaller = model.uninstaller
        return HStack(spacing: 18) {
            Image(nsImage: uninstaller.icon(for: app))
                .resizable()
                .frame(width: 84, height: 84)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text([app.version, app.bundleId].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .textSelection(.enabled)
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.uninstaller.primary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(uninstaller.sizes[app.path].map(ByteFormat.string) ?? "—")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("app size").caption()
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        let uninstaller = model.uninstaller
        if let reason = app.protected {
            Banner(symbol: "lock.shield.fill", text: EngineText.reason(reason), tint: .yellow)
        } else if uninstaller.isRunning(app) {
            Banner(symbol: "play.circle.fill", text: String(localized: "\(app.name) is running. Quit it before uninstalling."), tint: .green) {
                Button("Quit \(app.name)") { uninstaller.quit(app) }
                    .buttonStyle(.glassCapsule)
            }
        }
    }
}

private struct LeftoverList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let uninstaller = model.uninstaller
        ScrollView {
            VStack(spacing: 2) {
                if uninstaller.loadingLeftovers {
                    HStack(spacing: 10) {
                        SpinningArc(theme: .uninstaller, lineWidth: 2.5).frame(width: 16, height: 16)
                        Text("Looking for related files…").caption()
                    }
                    .padding(20)
                } else if uninstaller.leftovers.isEmpty {
                    Text("No related files found outside the app bundle.")
                        .caption()
                        .padding(20)
                } else {
                    ForEach(uninstaller.leftovers) { leftover in
                        LeftoverRow(leftover: leftover, selected: uninstaller.leftoverSelection.contains(leftover.path))
                            .onTapGesture { uninstaller.toggle(leftover) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(6)
        }
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct LeftoverRow: View {
    let leftover: Leftover
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            SelectionMark(state: selected ? .on : .off, theme: .uninstaller)
                .scaleEffect(0.85)
            Text(EngineText.leftoverKind(leftover.kind))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 118, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(leftover.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if leftover.evidence == .name {
                    Text("Matched by name — review before removing")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow.opacity(0.8))
                }
            }
            Spacer()
            Text(ByteFormat.string(leftover.bytes))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: leftover.path)])
            }
        }
    }
}

private struct Banner<Accessory: View>: View {
    let symbol: String
    let text: String
    let tint: Color
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.system(size: 12.5, weight: .medium))
            Spacer()
            accessory()
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension Banner where Accessory == EmptyView {
    init(symbol: String, text: String, tint: Color) {
        self.init(symbol: symbol, text: text, tint: tint) { EmptyView() }
    }
}

private struct UninstallDone: View {
    let app: AppInfo
    let freed: UInt64
    let problems: Int
    @Environment(AppModel.self) private var model
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.uninstaller.gradient)
                .symbolEffect(.bounce, value: appeared)
            Text("\(app.name) was removed")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            BytesDisplay(bytes: freed, size: 44)
            if problems > 0 {
                Text("\(problems) related items could not be removed.").caption()
            }
            Button("Done") {
                model.uninstaller.acknowledgeResult()
                model.refreshVolume()
            }
            .buttonStyle(.prominentCapsule(.uninstaller))
            .keyboardShortcut(.defaultAction)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { appeared = true }
    }
}
