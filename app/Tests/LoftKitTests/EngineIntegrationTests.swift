import Foundation
import Testing
@testable import LoftKit

/// Runs against the locally built engine; skipped when it has not been built.
@Suite("Engine integration", .enabled(if: EngineClient.locate() != nil))
struct EngineIntegrationTests {
    private let engine = EngineClient.locate()!

    @Test func analyzeStreamsChildrenThenReport() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "loft-it-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: "big"), withIntermediateDirectories: true)
        try Data(count: 200_000).write(to: folder.appending(path: "big/blob"))
        try Data(count: 1_000).write(to: folder.appending(path: "small"))
        defer { try? FileManager.default.removeItem(at: folder) }

        var children: [DiskNode] = []
        var report: DirReport?
        for try await event in engine.stream(["analyze", folder.path]) {
            switch event {
            case .analyzeChild(let node): children.append(node)
            case .analyzeReport(let r): report = r
            default: break
            }
        }
        #expect(children.count == 2)
        #expect(report?.children.first?.name == "big")
    }

    @Test func engineErrorsSurfaceAsThrownErrors() async {
        await #expect(throws: EngineError.self) {
            _ = try await engine.events(["analyze", "/definitely/not/a/folder"])
        }
    }

    @Test func statusSnapshotDecodes() async throws {
        let events = try await engine.events(["status"])
        let statuses = events.compactMap { if case .status(let s) = $0 { s } else { nil } }
        #expect(statuses.count == 1)
        #expect((statuses.first?.memory.total ?? 0) > 0)
    }
}
