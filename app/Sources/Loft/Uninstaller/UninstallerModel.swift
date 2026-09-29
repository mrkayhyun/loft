import AppKit
import LoftKit
import Observation

@Observable
@MainActor
final class UninstallerModel {
    enum Phase: Equatable {
        case idle, working
        case finished(freed: UInt64, problems: Int)
        case failed(String)
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case size, name
        var id: String { rawValue }
        var title: String {
            switch self {
            case .size: String(localized: "Size")
            case .name: String(localized: "Name")
            }
        }
    }

    private(set) var apps: [AppInfo] = []
    private(set) var sizes: [String: UInt64] = [:]
    private(set) var loading = false
    private(set) var runningBundleIDs: Set<String> = []
    private(set) var leftovers: [Leftover] = []
    private(set) var loadingLeftovers = false
    private(set) var phase: Phase = .idle
    private(set) var loadError: String?
    var leftoverSelection: Set<String> = []
    var search = ""
    var sort: SortOrder = .size
    var selectedID: String? {
        didSet {
            if oldValue != selectedID { loadLeftovers() }
        }
    }

    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private var leftoverTask: Task<Void, Never>?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private let engine: EngineClient?

    init(engine: EngineClient?) {
        self.engine = engine
        observeWorkspace()
    }

    // MARK: Listing

    var visibleApps: [AppInfo] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = query.isEmpty ? apps : apps.filter {
            $0.name.lowercased().contains(query) || $0.bundleId.lowercased().contains(query)
        }
        switch sort {
        case .name:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            return filtered.sorted { (sizes[$0.path] ?? 0) > (sizes[$1.path] ?? 0) }
        }
    }

    var selectedApp: AppInfo? {
        apps.first { $0.id == selectedID }
    }

    var totalAppBytes: UInt64 { sizes.values.reduce(0, +) }

    func load() {
        guard apps.isEmpty, !loading, let engine else { return }
        loading = true
        loadError = nil
        refreshRunning()
        Task { [weak self] in
            do {
                for try await event in engine.stream(["apps", "--sizes"]) {
                    self?.handleListing(event)
                }
            } catch {
                self?.loadError = error.localizedDescription
            }
            self?.loading = false
        }
    }

    private func handleListing(_ event: EngineEvent) {
        switch event {
        case .apps(let list):
            apps = list
            if selectedID == nil { selectedID = list.first(where: \.isRemovable)?.id }
        case .appSize(let path, let bytes):
            sizes[path] = bytes
        default:
            break
        }
    }

    func icon(for app: AppInfo) -> NSImage {
        if let cached = icons[app.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: app.path)
        icons[app.path] = image
        return image
    }

    func isRunning(_ app: AppInfo) -> Bool {
        runningBundleIDs.contains(app.bundleId)
    }

    // MARK: Leftovers

    var selectedLeftoverBytes: UInt64 {
        leftovers.filter { leftoverSelection.contains($0.path) }.reduce(0) { $0 + $1.bytes }
    }

    var totalSelectedBytes: UInt64 {
        (selectedApp.flatMap { sizes[$0.path] } ?? 0) + selectedLeftoverBytes
    }

    func toggle(_ leftover: Leftover) {
        if leftoverSelection.contains(leftover.path) {
            leftoverSelection.remove(leftover.path)
        } else {
            leftoverSelection.insert(leftover.path)
        }
    }

    private func loadLeftovers() {
        leftoverTask?.cancel()
        leftovers = []
        leftoverSelection = []
        phase = .idle
        guard let app = selectedApp, let engine else { return }
        loadingLeftovers = true
        leftoverTask = Task { [weak self] in
            let events = (try? await engine.events(["leftovers", "--app", app.path])) ?? []
            guard !Task.isCancelled, let self else { return }
            for case .leftovers(let items) in events {
                self.leftovers = items
                self.leftoverSelection = Set(items.filter(\.selectedByDefault).map(\.path))
            }
            self.loadingLeftovers = false
        }
    }

    // MARK: Actions

    func quit(_ app: AppInfo) {
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleId).forEach { $0.terminate() }
    }

    func uninstall() {
        guard let app = selectedApp, let engine else { return }
        let include = leftoverSelection.sorted().flatMap { ["--include", $0] }
        phase = .working
        Task { [weak self] in
            do {
                let events = try await engine.events(["uninstall", "--app", app.path] + include)
                for case .uninstallReport(let report) in events {
                    self?.finishUninstall(app: app, report: report)
                }
            } catch {
                self?.phase = .failed(EngineText.reason(error.localizedDescription))
            }
        }
    }

    private func finishUninstall(app: AppInfo, report: UninstallReport) {
        let appRemoved = report.results.first?.status == .removed
        let problems = report.results.filter { $0.status == .failed || $0.status == .skipped }.count
        if appRemoved {
            apps.removeAll { $0.id == app.id }
            sizes[app.path] = nil
            phase = .finished(freed: report.freedBytes, problems: problems)
        } else {
            let reason = report.results.first?.message.map(EngineText.reason) ?? String(localized: "The app could not be moved to the Trash.")
            phase = .failed(reason)
        }
    }

    func acknowledgeResult() {
        phase = .idle
        if selectedApp == nil { selectedID = visibleApps.first(where: \.isRemovable)?.id }
    }

    // MARK: Running apps

    private func refreshRunning() {
        runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshRunning() }
            }
        }
    }
}
