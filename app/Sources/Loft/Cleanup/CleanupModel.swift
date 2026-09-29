import AppKit
import LoftKit
import Observation

enum TriState: Equatable { case on, off, mixed }

@Observable
@MainActor
final class CleanupModel {
    enum Phase: Equatable {
        case idle, scanning, results, cleaning, finished
        case failed(String)
    }

    /// Display order of category groups in the results list.
    static let groupOrder: [CategoryGroup] = [.system, .developer, .browser, .apps]
    private static let lifetimeKey = "lifetimeFreedBytes"

    private(set) var phase: Phase = .idle
    private(set) var report: ScanReport?
    private(set) var progress: Double = 0
    private(set) var foundBytes: UInt64 = 0
    private(set) var currentCategory = ""
    private(set) var cleanReport: CleanReport?
    private(set) var cleanedCount = 0
    private(set) var cleanTotal = 0
    private(set) var freedSoFar: UInt64 = 0
    private(set) var currentItem = ""
    private(set) var lifetimeFreed: UInt64
    var selection: Set<String> = []
    var expanded: Set<String> = []

    /// Categories whose owning app the user chose to quit from Loft.
    private var released: Set<String> = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let engine: EngineClient?

    init(engine: EngineClient?) {
        self.engine = engine
        lifetimeFreed = UInt64(max(UserDefaults.standard.integer(forKey: Self.lifetimeKey), 0))
    }

    // MARK: Scan

    func scan() {
        guard let engine else {
            phase = .failed(EngineError.notFound.localizedDescription)
            return
        }
        task?.cancel()
        phase = .scanning
        progress = 0
        foundBytes = 0
        currentCategory = ""
        task = Task { [weak self] in
            do {
                for try await event in engine.stream(["scan"]) {
                    self?.handleScan(event)
                }
            } catch is CancellationError {
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func handleScan(_ event: EngineEvent) {
        switch event {
        case .scanProgress(let done, let total, let category, let bytes):
            progress = total == 0 ? 1 : Double(done) / Double(total)
            foundBytes = bytes
            currentCategory = category
        case .scanReport(let report):
            apply(report)
        default:
            break
        }
    }

    private func apply(_ report: ScanReport) {
        self.report = report
        released = []
        expanded = []
        selection = Set(report.categories.filter(\.selected).flatMap { $0.items.map(\.path) })
        phase = .results
    }

    func cancelScan() {
        task?.cancel()
        task = nil
        phase = report == nil ? .idle : .results
    }

    // MARK: Selection

    func categories(in group: CategoryGroup) -> [CleanCategory] {
        (report?.categories ?? []).filter { $0.group == group }
    }

    func isHeld(_ category: CleanCategory) -> Bool {
        category.isHeld && !released.contains(category.id)
    }

    func state(of category: CleanCategory) -> TriState {
        guard !isHeld(category) else { return .off }
        let chosen = category.items.filter { selection.contains($0.path) }.count
        if chosen == 0 { return .off }
        return chosen == category.items.count ? .on : .mixed
    }

    func toggle(_ category: CleanCategory) {
        guard !isHeld(category) else { return }
        let paths = category.items.map(\.path)
        if state(of: category) == .on {
            selection.subtract(paths)
        } else {
            selection.formUnion(paths)
        }
    }

    func toggle(_ item: CleanItem) {
        if selection.contains(item.path) {
            selection.remove(item.path)
        } else {
            selection.insert(item.path)
        }
    }

    func selectedBytes(in category: CleanCategory) -> UInt64 {
        guard !isHeld(category) else { return 0 }
        return category.items.filter { selection.contains($0.path) }.reduce(0) { $0 + $1.bytes }
    }

    var selectedBytes: UInt64 {
        (report?.categories ?? []).reduce(0) { $0 + selectedBytes(in: $1) }
    }

    var selectionIncludesPermanentDelete: Bool {
        (report?.categories ?? []).contains { $0.action == .delete && state(of: $0) != .off }
    }

    /// Ask the apps holding a category to quit, then allow selecting it.
    func quitOwners(of category: CleanCategory) {
        let names = Set(category.heldBy.map { $0.lowercased() })
        for app in NSWorkspace.shared.runningApplications {
            let name = app.localizedName?.lowercased()
            let executable = app.executableURL?.lastPathComponent.lowercased()
            if names.contains(name ?? "") || names.contains(executable ?? "") {
                app.terminate()
            }
        }
        released.insert(category.id)
        selection.formUnion(category.items.map(\.path))
    }

    // MARK: Clean

    func clean() {
        guard let engine, let report else { return }
        let items = report.categories
            .filter { !isHeld($0) }
            .flatMap { category in
                category.items
                    .filter { selection.contains($0.path) }
                    .map { PlanItem(category: category.id, item: $0) }
            }
        guard !items.isEmpty, let input = try? JSONEncoder().encode(CleanPlan(items: items)) else { return }
        phase = .cleaning
        cleanTotal = items.count
        cleanedCount = 0
        freedSoFar = 0
        currentItem = ""
        task = Task { [weak self] in
            do {
                for try await event in engine.stream(["clean", "--plan", "-"], input: input) {
                    self?.handleClean(event)
                }
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func handleClean(_ event: EngineEvent) {
        switch event {
        case .cleanItem(let result):
            cleanedCount += 1
            currentItem = result.name
            if result.status == .removed { freedSoFar += result.bytes ?? 0 }
        case .cleanReport(let report):
            cleanReport = report
            lifetimeFreed += report.freedBytes
            UserDefaults.standard.set(Int(clamping: lifetimeFreed), forKey: Self.lifetimeKey)
            phase = .finished
        default:
            break
        }
    }

    func reset() {
        task?.cancel()
        phase = .idle
        report = nil
        cleanReport = nil
        selection = []
    }
}
