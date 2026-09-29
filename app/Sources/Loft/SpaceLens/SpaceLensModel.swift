import LoftKit
import Foundation
import Observation

@Observable
@MainActor
final class SpaceLensModel {
    struct Crumb: Identifiable, Hashable {
        let name: String
        let path: String
        var id: String { path }
    }

    private(set) var root = NSHomeDirectory()
    private(set) var current = NSHomeDirectory()
    private(set) var nodes: [DiskNode] = []
    private(set) var loading = false
    private(set) var expectedChildren = 0
    private(set) var error: String?
    var hovered: DiskNode?

    @ObservationIgnored private var cache: [String: [DiskNode]] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let engine: EngineClient?

    init(engine: EngineClient?) {
        self.engine = engine
    }

    var total: UInt64 { nodes.reduce(0) { $0 + $1.bytes } }
    var canGoUp: Bool { current != "/" }

    var breadcrumbs: [Crumb] {
        let base = current.hasPrefix(root) ? root : "/"
        var crumbs = [Crumb(name: FileManager.default.displayName(atPath: base), path: base)]
        let rest = current.dropFirst(base.count).split(separator: "/")
        var path = base
        for component in rest {
            path = (path as NSString).appendingPathComponent(String(component))
            crumbs.append(Crumb(name: String(component), path: path))
        }
        return crumbs
    }

    func start() {
        if nodes.isEmpty && !loading { open(current) }
    }

    func open(_ path: String) {
        task?.cancel()
        current = path
        hovered = nil
        error = nil
        if let cached = cache[path] {
            nodes = cached
            loading = false
            return
        }
        guard let engine else { return }
        nodes = []
        loading = true
        expectedChildren = 0
        task = Task { [weak self] in
            do {
                for try await event in engine.stream(["analyze", path]) {
                    self?.handle(event, for: path)
                }
            } catch is CancellationError {
            } catch {
                self?.error = error.localizedDescription
                self?.loading = false
            }
        }
    }

    private func handle(_ event: EngineEvent, for path: String) {
        guard path == current else { return }
        switch event {
        case .analyzeStarted(_, let children):
            expectedChildren = children
        case .analyzeChild(let node):
            let index = nodes.firstIndex { $0.bytes < node.bytes } ?? nodes.endIndex
            nodes.insert(node, at: index)
        case .analyzeReport(let report):
            nodes = report.children
            cache[path] = report.children
            loading = false
        default:
            break
        }
    }

    func up() {
        guard canGoUp else { return }
        open((current as NSString).deletingLastPathComponent)
    }

    func choose(_ url: URL) {
        root = url.path
        open(url.path)
    }

    func refresh() {
        cache[current] = nil
        open(current)
    }
}
