import LoftKit
import SwiftUI

struct CleanFinishedView: View {
    @Environment(AppModel.self) private var model
    @State private var appeared = false
    @State private var showProblems = false

    var body: some View {
        let report = model.cleanup.cleanReport
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.cleanup.gradient)
                    .frame(width: 128, height: 128)
                    .shadow(color: Theme.cleanup.primary.opacity(0.7), radius: 30)
                Image(systemName: "checkmark")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: appeared)
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 8) {
                Text("All clean")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                BytesDisplay(bytes: report?.freedBytes ?? 0, size: 64)
                Text("moved to the Trash").caption()
            }

            if let report {
                HStack(spacing: 12) {
                    Metric(value: report.removed, label: "Cleaned", color: .green)
                    Metric(value: report.skipped, label: "Skipped", color: .yellow)
                    Metric(value: report.failed, label: "Failed", color: .red)
                }
                if !report.problems.isEmpty {
                    Button(showProblems ? String(localized: "Hide details") : String(localized: "Why were some skipped?")) {
                        withAnimation(.smooth) { showProblems.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    if showProblems {
                        ProblemList(problems: report.problems)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Open Trash") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".Trash"))
                }
                .buttonStyle(.glassCapsule)
                Button("Done") {
                    model.cleanup.reset()
                    model.refreshVolume()
                }
                .buttonStyle(.prominentCapsule(.cleanup))
                .keyboardShortcut(.defaultAction)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .onAppear {
            model.refreshVolume()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { appeared = true }
        }
    }
}

private struct Metric: View {
    let value: Int
    let label: LocalizedStringKey
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label).caption()
            }
        }
        .frame(width: 110)
        .padding(.vertical, 12)
        .glassPanel(radius: 14)
    }
}

private struct ProblemList: View {
    let problems: [ItemResult]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(problems) { problem in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(problem.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text(EngineText.reason(problem.message))
                            .caption()
                            .lineLimit(1)
                    }
                }
            }
            .padding(14)
        }
        .frame(maxWidth: 560, maxHeight: 160)
        .glassPanel(radius: 14)
    }
}
