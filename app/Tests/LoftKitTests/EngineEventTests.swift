import Foundation
import Testing
@testable import LoftKit

@Suite("Engine protocol decoding")
struct EngineEventTests {
    private func decode(_ json: String) throws -> EngineEvent {
        try EngineEvent.decode(line: Data(json.utf8))
    }

    @Test func decodesScanProgress() throws {
        let event = try decode(#"{"type":"progress","done":3,"total":10,"category":"user-caches","bytes":4096}"#)
        guard case .scanProgress(let done, let total, let category, let bytes) = event else {
            Issue.record("unexpected \(event)"); return
        }
        #expect(done == 3 && total == 10 && category == "user-caches" && bytes == 4096)
    }

    @Test func distinguishesScanAndAnalyzeStartedEvents() throws {
        guard case .scanStarted(let candidates) = try decode(#"{"type":"started","candidates":4}"#) else {
            Issue.record("not scan started"); return
        }
        #expect(candidates == 4)
        guard case .analyzeStarted(let path, let children) = try decode(#"{"type":"started","path":"/a","children":2}"#) else {
            Issue.record("not analyze started"); return
        }
        #expect(path == "/a" && children == 2)
    }

    @Test func decodesScanReportWithSnakeCaseKeys() throws {
        let json = #"""
        {"type":"scan_report","report":{"home":"/Users/a","generated_at":1,"duration_ms":20,"total_bytes":8192,
         "categories":[{"id":"user-caches","group":"system","name":"App Caches","summary":"s","symbol":"internaldrive",
         "action":"trash","selected":true,"held_by":["Xcode"],"bytes":8192,"files":2,"errors":0,"partial":false,
         "items":[{"path":"/Users/a/Library/Caches/x","bytes":8192,"files":2,"dev":1,"ino":2,"modified":3,"partial":false}]}]}}
        """#
        guard case .scanReport(let report) = try decode(json) else {
            Issue.record("not a scan report"); return
        }
        #expect(report.totalBytes == 8192)
        #expect(report.categories.first?.heldBy == ["Xcode"])
        #expect(report.categories.first?.items.first?.name == "x")
    }

    @Test func decodesCleanItemOutcomes() throws {
        let json = #"{"type":"item","result":{"category":"trash","path":"/a/b","status":"would_remove","bytes":10}}"#
        guard case .cleanItem(let result) = try decode(json) else {
            Issue.record("not an item"); return
        }
        #expect(result.status == .wouldRemove)
        #expect(result.bytes == 10)
    }

    @Test func decodesErrorAndUnknownEvents() throws {
        guard case .error(let message) = try decode(#"{"type":"error","message":"boom"}"#) else {
            Issue.record("not an error"); return
        }
        #expect(message == "boom")
        guard case .unknown(let type) = try decode(#"{"type":"future_thing"}"#) else {
            Issue.record("not unknown"); return
        }
        #expect(type == "future_thing")
    }

    @Test func planEncodesIdentity() throws {
        let item = CleanItem(path: "/p", bytes: 1, files: 1, dev: 7, ino: 9, modified: 0, partial: false)
        let data = try JSONEncoder().encode(CleanPlan(items: [PlanItem(category: "c", item: item)]))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""dev":7"#) && text.contains(#""ino":9"#))
    }
}
