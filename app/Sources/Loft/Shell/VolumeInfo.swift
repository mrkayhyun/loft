import Foundation

/// Capacity of the volume holding the home folder. "Available" includes
/// purgeable space, matching what Finder reports.
struct VolumeInfo: Sendable, Equatable {
    let name: String
    let total: UInt64
    let available: UInt64

    var used: UInt64 { total > available ? total - available : 0 }
    var fraction: Double { total == 0 ? 0 : Double(used) / Double(total) }

    static func current() -> VolumeInfo? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard
            let values = try? url.resourceValues(forKeys: keys),
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return VolumeInfo(
            name: values.volumeLocalizedName ?? "Macintosh HD",
            total: UInt64(max(total, 0)),
            available: UInt64(max(available, 0))
        )
    }
}
