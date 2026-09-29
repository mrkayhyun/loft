import LoftKit
import Charts
import SwiftUI

struct MonitorView: View {
    @Environment(AppModel.self) private var model

    private let gaugeColumns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        let monitor = model.monitor
        ScrollView {
            VStack(spacing: 16) {
                SectionHeader(section: .monitor) {
                    if let status = monitor.latest {
                        Text("\(status.hostname) · \(status.osVersion)").caption()
                    }
                }
                if let error = monitor.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .card(padding: 14)
                }
                LazyVGrid(columns: gaugeColumns, spacing: 16) {
                    cpuGauge
                    memoryGauge
                    diskGauge
                    batteryGauge
                }
                HStack(alignment: .top, spacing: 16) {
                    HistoryChart(title: String(localized: "Processor"), unit: "%", samples: monitor.cpu, theme: .uninstaller, maxValue: 100)
                    HistoryChart(title: String(localized: "Memory pressure"), unit: "%", samples: monitor.memory, theme: .monitor, maxValue: 100)
                }
                HStack(alignment: .top, spacing: 16) {
                    NetworkCard(download: monitor.download, upload: monitor.upload, status: monitor.latest)
                    TopProcessesCard(processes: monitor.latest?.top ?? [])
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.never)
        .onAppear { monitor.acquire() }
        .onDisappear { monitor.release() }
    }

    private var cpuGauge: some View {
        let cpu = model.monitor.latest?.cpu
        return GaugeCard(
            title: "CPU",
            value: (cpu?.usage ?? 0) / 100,
            primary: cpu.map { "\(Int($0.usage.rounded()))%" } ?? "—",
            detail: cpu.map { String(localized: "Load \(($0.load.first ?? 0).formatted(.number.precision(.fractionLength(2))))") } ?? " ",
            theme: .uninstaller
        )
    }

    private var memoryGauge: some View {
        let memory = model.monitor.latest?.memory
        return GaugeCard(
            title: "Memory",
            value: memory?.fraction ?? 0,
            primary: memory.map { ByteFormat.string($0.used) } ?? "—",
            detail: memory.map { String(localized: "of \(ByteFormat.string($0.total))") } ?? " ",
            theme: .monitor
        )
    }

    private var diskGauge: some View {
        let volume = model.volume
        return GaugeCard(
            title: "Disk",
            value: volume?.fraction ?? 0,
            primary: volume.map { ByteFormat.string($0.available) } ?? "—",
            detail: String(localized: "available"),
            theme: .overview
        )
    }

    private var batteryGauge: some View {
        let battery = model.monitor.battery
        let detail: String = {
            guard let battery else { return String(localized: "Power adapter") }
            if battery.isCharging { return String(localized: "Charging") }
            if let minutes = battery.minutesRemaining { return String(localized: "\(minutes / 60)h \(minutes % 60)m left") }
            return battery.isOnAC ? String(localized: "On power adapter") : String(localized: "On battery")
        }()
        return GaugeCard(
            title: "Battery",
            value: battery?.level ?? 1,
            primary: battery.map { "\(Int(($0.level * 100).rounded()))%" } ?? "AC",
            detail: detail,
            theme: .spaceLens
        )
    }
}

private struct GaugeCard: View {
    let title: LocalizedStringKey
    let value: Double
    let primary: String
    let detail: String
    let theme: Theme

    var body: some View {
        HStack(spacing: 16) {
            RingGauge(value: value, theme: theme, lineWidth: 8) {
                Text("\(Int((min(max(value, 0), 1) * 100).rounded()))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(width: 62, height: 62)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text(primary)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail).caption().lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .animation(.snappy, value: primary)
        .card(padding: 16)
    }
}

private struct HistoryChart: View {
    let title: String
    let unit: String
    let samples: [Sample]
    let theme: Theme
    let maxValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(samples.last.map { "\(Int($0.value.rounded()))\(unit)" } ?? "—")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Chart(samples) { sample in
                AreaMark(x: .value("t", sample.id), y: .value(title, sample.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(colors: [theme.primary.opacity(0.55), theme.primary.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                    )
                LineMark(x: .value("t", sample.id), y: .value(title, sample.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(theme.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .chartYScale(domain: 0...maxValue)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, maxValue / 2, maxValue]) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                }
            }
            .frame(height: 140)
        }
        .foregroundStyle(.white)
        .card(padding: 18)
    }
}

private struct NetworkCard: View {
    let download: [Sample]
    let upload: [Sample]
    let status: SystemStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Network").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 22) {
                rate(symbol: "arrow.down.circle.fill", label: "Download", value: status?.network.rxBytesPerSec ?? 0, color: Theme.monitor.primary)
                rate(symbol: "arrow.up.circle.fill", label: "Upload", value: status?.network.txBytesPerSec ?? 0, color: Theme.uninstaller.primary)
            }
            Chart {
                ForEach(download) { sample in
                    LineMark(x: .value("t", sample.id), y: .value("rate", sample.value), series: .value("dir", "down"))
                        .foregroundStyle(Theme.monitor.primary)
                        .interpolationMethod(.catmullRom)
                }
                ForEach(upload) { sample in
                    LineMark(x: .value("t", sample.id), y: .value("rate", sample.value), series: .value("dir", "up"))
                        .foregroundStyle(Theme.uninstaller.primary)
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 90)
            if let status {
                Text("Up \(Self.uptime(status.uptimeSecs)) · \(status.cpu.brand)").caption()
            }
        }
        .foregroundStyle(.white)
        .card(padding: 18)
    }

    private func rate(symbol: String, label: LocalizedStringKey, value: UInt64, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).caption()
                Text(ByteFormat.rate(value))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }

    private static func uptime(_ seconds: UInt64) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        return days > 0 ? String(localized: "\(days)d \(hours)h") : String(localized: "\(hours)h \(minutes)m")
    }
}

private struct TopProcessesCard: View {
    let processes: [SystemStatus.TopProcess]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top processes").font(.system(size: 13, weight: .semibold))
            ForEach(processes) { process in
                HStack(spacing: 10) {
                    Text(process.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text(ByteFormat.string(process.memory)).caption()
                    Text(String(format: "%.1f%%", process.cpu))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 58, alignment: .trailing)
                }
                .padding(.vertical, 3)
            }
            if processes.isEmpty {
                Text("Collecting…").caption()
            }
        }
        .foregroundStyle(.white)
        .card(padding: 18)
    }
}
