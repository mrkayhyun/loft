import Foundation

/// One line of the engine's NDJSON protocol.
public enum EngineEvent: Sendable {
    case scanStarted(candidates: Int)
    case scanProgress(done: Int, total: Int, category: String, bytes: UInt64)
    case scanReport(ScanReport)
    case cleanItem(ItemResult)
    case cleanReport(CleanReport)
    case apps([AppInfo])
    case appSize(path: String, bytes: UInt64)
    case leftovers([Leftover])
    case uninstallReport(UninstallReport)
    case analyzeStarted(path: String, children: Int)
    case analyzeChild(DiskNode)
    case analyzeReport(DirReport)
    case status(SystemStatus)
    case done
    case error(String)
    case unknown(String)
}

extension EngineEvent {
    private struct Envelope: Decodable { let type: String }
    private struct Report<T: Decodable>: Decodable { let report: T }
    private struct ScanStarted: Decodable { let candidates: Int }
    private struct ScanProgress: Decodable {
        let done: Int
        let total: Int
        let category: String
        let bytes: UInt64
    }
    private struct Item: Decodable { let result: ItemResult }
    private struct Apps: Decodable { let apps: [AppInfo] }
    private struct AppSize: Decodable {
        let path: String
        let bytes: UInt64
    }
    private struct Leftovers: Decodable { let items: [Leftover] }
    private struct AnalyzeStarted: Decodable {
        let path: String
        let children: Int
    }
    private struct AnalyzeChild: Decodable { let node: DiskNode }
    private struct Status: Decodable { let status: SystemStatus }
    private struct Failure: Decodable { let message: String }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    public static func decode(line: Data) throws -> EngineEvent {
        let d = decoder
        let type = try d.decode(Envelope.self, from: line).type
        switch type {
        case "started":
            // Scan and analyze share the tag; their payloads differ.
            if let scan = try? d.decode(ScanStarted.self, from: line) {
                return .scanStarted(candidates: scan.candidates)
            }
            let analyze = try d.decode(AnalyzeStarted.self, from: line)
            return .analyzeStarted(path: analyze.path, children: analyze.children)
        case "progress":
            let p = try d.decode(ScanProgress.self, from: line)
            return .scanProgress(done: p.done, total: p.total, category: p.category, bytes: p.bytes)
        case "scan_report":
            return .scanReport(try d.decode(Report<ScanReport>.self, from: line).report)
        case "item":
            return .cleanItem(try d.decode(Item.self, from: line).result)
        case "clean_report":
            return .cleanReport(try d.decode(Report<CleanReport>.self, from: line).report)
        case "apps":
            return .apps(try d.decode(Apps.self, from: line).apps)
        case "app_size":
            let s = try d.decode(AppSize.self, from: line)
            return .appSize(path: s.path, bytes: s.bytes)
        case "leftovers":
            return .leftovers(try d.decode(Leftovers.self, from: line).items)
        case "uninstall_report":
            return .uninstallReport(try d.decode(Report<UninstallReport>.self, from: line).report)
        case "child":
            return .analyzeChild(try d.decode(AnalyzeChild.self, from: line).node)
        case "analyze_report":
            return .analyzeReport(try d.decode(Report<DirReport>.self, from: line).report)
        case "status":
            return .status(try d.decode(Status.self, from: line).status)
        case "done":
            return .done
        case "error":
            return .error(try d.decode(Failure.self, from: line).message)
        default:
            return .unknown(type)
        }
    }
}
