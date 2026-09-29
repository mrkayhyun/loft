import LoftKit
import Foundation

/// Localises text that originates in the engine (category names, leftover
/// kinds, skip reasons). The engine speaks English; translations live in the
/// `Engine.strings` table. Unknown text falls back to the engine's wording.
enum EngineText {
    private static let table = "Engine"
    private static let missing = "\u{1}"

    private static func lookup(_ key: String) -> String? {
        let value = Bundle.main.localizedString(forKey: key, value: missing, table: table)
        return value == missing ? nil : value
    }

    static func categoryName(_ category: CleanCategory) -> String {
        lookup("category.\(category.id).name") ?? category.name
    }

    /// Name for an id seen during scanning, before the report arrives.
    static func categoryName(id: String) -> String {
        guard !id.isEmpty else { return String(localized: "Preparing") }
        return lookup("category.\(id).name")
            ?? id.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    static func categorySummary(_ category: CleanCategory) -> String {
        lookup("category.\(category.id).summary") ?? category.summary
    }

    static func leftoverKind(_ kind: String) -> String {
        lookup("kind.\(kind)") ?? kind
    }

    /// Skip / failure / protection reasons, including the two templated ones.
    static func reason(_ message: String?) -> String {
        guard let message, !message.isEmpty else { return "" }
        if let exact = lookup("reason.\(message)") { return exact }
        if let apps = message.strip(suffix: " is running") {
            return String(localized: "\(apps) is running")
        }
        if let name = message.strip(prefix: "Quit ", suffix: " before uninstalling") {
            return String(localized: "Quit \(name) before uninstalling")
        }
        return message
    }
}

private extension String {
    func strip(prefix: String = "", suffix: String) -> String? {
        guard hasPrefix(prefix), hasSuffix(suffix), count > prefix.count + suffix.count else { return nil }
        return String(dropFirst(prefix.count).dropLast(suffix.count))
    }
}
