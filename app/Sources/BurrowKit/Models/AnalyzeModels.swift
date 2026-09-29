import Foundation

public struct DiskNode: Decodable, Sendable, Identifiable, Hashable {
    public let name: String
    public let path: String
    public let bytes: UInt64
    public let files: UInt64
    public let isDir: Bool
    public let partial: Bool
    public let errors: UInt64

    public var id: String { path }
}

public struct DirReport: Decodable, Sendable {
    public let path: String
    public let bytes: UInt64
    public let files: UInt64
    public let errors: UInt64
    public let durationMs: UInt64
    public let children: [DiskNode]
}
