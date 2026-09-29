import Foundation

public struct SystemStatus: Decodable, Sendable {
    public struct CPU: Decodable, Sendable {
        public let usage: Double
        public let cores: [Double]
        public let brand: String
        public let load: [Double]
    }

    public struct Memory: Decodable, Sendable {
        public let total: UInt64
        public let used: UInt64
        public let available: UInt64
        public let swapTotal: UInt64
        public let swapUsed: UInt64

        public var fraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
    }

    public struct Disk: Decodable, Sendable {
        public let name: String
        public let mount: String
        public let total: UInt64
        public let available: UInt64

        public var used: UInt64 { total &- available }
        public var fraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
    }

    public struct Network: Decodable, Sendable {
        public let rxBytesPerSec: UInt64
        public let txBytesPerSec: UInt64
    }

    public struct TopProcess: Decodable, Sendable, Identifiable {
        public let pid: UInt32
        public let name: String
        public let cpu: Double
        public let memory: UInt64

        public var id: UInt32 { pid }
    }

    public let timestamp: UInt64
    public let hostname: String
    public let osVersion: String
    public let uptimeSecs: UInt64
    public let cpu: CPU
    public let memory: Memory
    public let disk: Disk?
    public let network: Network
    public let top: [TopProcess]
}
