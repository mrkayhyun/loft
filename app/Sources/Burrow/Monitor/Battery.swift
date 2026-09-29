import Foundation
import IOKit.ps

/// Internal battery state from IOKit power sources. Nil on desktops.
struct BatteryState: Sendable, Equatable {
    let level: Double
    let isCharging: Bool
    let isOnAC: Bool
    let minutesRemaining: Int?

    static func read() -> BatteryState? {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description["Type"] as? String == "InternalBattery",
                let current = description["Current Capacity"] as? Int,
                let maximum = description["Max Capacity"] as? Int,
                maximum > 0
            else { continue }
            let minutes = description["Time to Empty"] as? Int
            return BatteryState(
                level: Double(current) / Double(maximum),
                isCharging: description["Is Charging"] as? Bool ?? false,
                isOnAC: description["Power Source State"] as? String == "AC Power",
                minutesRemaining: (minutes ?? -1) > 0 ? minutes : nil
            )
        }
        return nil
    }
}
