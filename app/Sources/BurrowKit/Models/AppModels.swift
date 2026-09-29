import Foundation

public struct AppInfo: Decodable, Sendable, Identifiable, Hashable {
    public let path: String
    public let name: String
    public let bundleId: String
    public let version: String
    public let executable: String
    public let running: Bool
    public let protected: String?

    public var id: String { path }
    public var isRemovable: Bool { protected == nil }
}

public struct Leftover: Decodable, Sendable, Identifiable, Hashable {
    public enum Evidence: String, Decodable, Sendable {
        case bundleId = "bundle_id"
        case name
    }

    public let path: String
    public let kind: String
    public let evidence: Evidence
    public let bytes: UInt64
    public let files: UInt64

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    /// Only exact bundle-identifier matches are pre-selected.
    public var selectedByDefault: Bool { evidence == .bundleId }
}

public struct UninstallReport: Decodable, Sendable {
    public let dryRun: Bool
    public let freedBytes: UInt64
    public let results: [ItemResult]
}
