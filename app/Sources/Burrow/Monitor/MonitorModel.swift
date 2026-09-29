import BurrowKit
import Observation

struct Sample: Identifiable, Equatable {
    let id: Int
    let value: Double
}

/// Live system status. Views `acquire()` while visible; the engine stream
/// runs only while at least one view holds it.
@Observable
@MainActor
final class MonitorModel {
    static let historyLength = 90

    private(set) var latest: SystemStatus?
    private(set) var cpu: [Sample] = []
    private(set) var memory: [Sample] = []
    private(set) var download: [Sample] = []
    private(set) var upload: [Sample] = []
    private(set) var battery: BatteryState?
    private(set) var error: String?

    @ObservationIgnored private var tick = 0
    @ObservationIgnored private var holders = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let engine: EngineClient?

    init(engine: EngineClient?) {
        self.engine = engine
    }

    func acquire() {
        holders += 1
        if task == nil { start() }
    }

    func release() {
        holders = max(holders - 1, 0)
        if holders == 0 {
            task?.cancel()
            task = nil
        }
    }

    private func start() {
        guard let engine else { return }
        error = nil
        task = Task { [weak self] in
            do {
                for try await event in engine.stream(["status", "--stream", "--interval-ms", "1000"]) {
                    if case .status(let status) = event { self?.ingest(status) }
                }
            } catch is CancellationError {
            } catch {
                self?.error = error.localizedDescription
            }
        }
    }

    private func ingest(_ status: SystemStatus) {
        tick += 1
        latest = status
        battery = BatteryState.read()
        Self.append(status.cpu.usage, to: &cpu, id: tick)
        Self.append(status.memory.fraction * 100, to: &memory, id: tick)
        Self.append(Double(status.network.rxBytesPerSec), to: &download, id: tick)
        Self.append(Double(status.network.txBytesPerSec), to: &upload, id: tick)
    }

    private static func append(_ value: Double, to series: inout [Sample], id: Int) {
        series.append(Sample(id: id, value: value))
        if series.count > historyLength {
            series.removeFirst(series.count - historyLength)
        }
    }
}
