import Foundation

public enum CategoryGroup: String, Decodable, Sendable, CaseIterable {
    case browser, developer, apps, system

    public var title: String {
        switch self {
        case .system: String(localized: "System")
        case .browser: String(localized: "Browsers")
        case .developer: String(localized: "Developer")
        case .apps: String(localized: "Apps")
        }
    }
}

public enum CleanAction: String, Decodable, Sendable {
    case trash, delete
}

public struct CleanItem: Decodable, Sendable, Hashable, Identifiable {
    public let path: String
    public let bytes: UInt64
    public let files: UInt64
    public let dev: UInt64
    public let ino: UInt64
    public let modified: UInt64
    public let partial: Bool

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var modifiedDate: Date { Date(timeIntervalSince1970: TimeInterval(modified)) }
}

public struct CleanCategory: Decodable, Sendable, Identifiable {
    public let id: String
    public let group: CategoryGroup
    public let name: String
    public let summary: String
    public let symbol: String
    public let action: CleanAction
    public let selected: Bool
    public let heldBy: [String]
    public let bytes: UInt64
    public let files: UInt64
    public let errors: UInt64
    public let partial: Bool
    public let items: [CleanItem]

    public var isHeld: Bool { !heldBy.isEmpty }
}

public struct ScanReport: Decodable, Sendable {
    public let home: String
    public let generatedAt: UInt64
    public let durationMs: UInt64
    public let totalBytes: UInt64
    public let categories: [CleanCategory]

    public var totalErrors: UInt64 { categories.reduce(0) { $0 + $1.errors } }
}

// MARK: - Clean

public struct PlanItem: Encodable, Sendable {
    public let category: String
    public let path: String
    public let dev: UInt64
    public let ino: UInt64

    public init(category: String, item: CleanItem) {
        self.category = category
        self.path = item.path
        self.dev = item.dev
        self.ino = item.ino
    }
}

public struct CleanPlan: Encodable, Sendable {
    public let items: [PlanItem]
    public init(items: [PlanItem]) { self.items = items }
}

public struct ItemResult: Decodable, Sendable, Identifiable {
    public enum Status: String, Decodable, Sendable {
        case removed, wouldRemove = "would_remove", skipped, failed
    }

    public let category: String
    public let path: String
    public let status: Status
    public let bytes: UInt64?
    public let reason: String?
    public let error: String?

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var message: String? { reason ?? error }
}

public struct CleanReport: Decodable, Sendable {
    public let dryRun: Bool
    public let freedBytes: UInt64
    public let removed: Int
    public let skipped: Int
    public let failed: Int
    public let durationMs: UInt64
    public let results: [ItemResult]

    public var problems: [ItemResult] {
        results.filter { $0.status == .skipped || $0.status == .failed }
    }
}
