import SwiftUI

/// Colour identity of a section: a two-hue gradient over a deep base.
struct Theme: Sendable {
    let primary: Color
    let secondary: Color
    let base: Color

    var gradient: LinearGradient {
        LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var angular: AngularGradient {
        AngularGradient(colors: [secondary, primary, secondary], center: .center)
    }

    /// Nine mesh colours, darkest at the edges, brightest near the top centre.
    var mesh: [Color] {
        [
            base, primary.mix(with: base, by: 0.55), base,
            secondary.mix(with: base, by: 0.45), primary.mix(with: base, by: 0.25), secondary.mix(with: base, by: 0.6),
            base, secondary.mix(with: base, by: 0.7), base,
        ]
    }

    static let overview = Theme(primary: Color(red: 0.49, green: 0.42, blue: 1.0), secondary: Color(red: 0.87, green: 0.36, blue: 0.96), base: Color(red: 0.07, green: 0.05, blue: 0.16))
    static let cleanup = Theme(primary: Color(red: 0.13, green: 0.84, blue: 0.84), secondary: Color(red: 0.2, green: 0.45, blue: 1.0), base: Color(red: 0.03, green: 0.08, blue: 0.16))
    static let uninstaller = Theme(primary: Color(red: 1.0, green: 0.36, blue: 0.6), secondary: Color(red: 0.62, green: 0.3, blue: 1.0), base: Color(red: 0.12, green: 0.04, blue: 0.14))
    static let spaceLens = Theme(primary: Color(red: 1.0, green: 0.72, blue: 0.2), secondary: Color(red: 1.0, green: 0.4, blue: 0.25), base: Color(red: 0.14, green: 0.07, blue: 0.03))
    static let monitor = Theme(primary: Color(red: 0.3, green: 0.9, blue: 0.5), secondary: Color(red: 0.1, green: 0.7, blue: 0.75), base: Color(red: 0.03, green: 0.11, blue: 0.09))
}

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview, cleanup, uninstaller, spaceLens, monitor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .cleanup: String(localized: "Smart Clean")
        case .uninstaller: String(localized: "Uninstaller")
        case .spaceLens: String(localized: "Space Lens")
        case .monitor: String(localized: "Monitor")
        }
    }

    var subtitle: String {
        switch self {
        case .overview: String(localized: "Your Mac at a glance")
        case .cleanup: String(localized: "Caches, logs and leftovers")
        case .uninstaller: String(localized: "Remove apps completely")
        case .spaceLens: String(localized: "See what takes up space")
        case .monitor: String(localized: "Live system health")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "sparkles"
        case .cleanup: "wand.and.stars"
        case .uninstaller: "shippingbox.and.arrow.backward"
        case .spaceLens: "square.grid.3x3.square"
        case .monitor: "waveform.path.ecg"
        }
    }

    var theme: Theme {
        switch self {
        case .overview: .overview
        case .cleanup: .cleanup
        case .uninstaller: .uninstaller
        case .spaceLens: .spaceLens
        case .monitor: .monitor
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .overview: "1"
        case .cleanup: "2"
        case .uninstaller: "3"
        case .spaceLens: "4"
        case .monitor: "5"
        }
    }
}
