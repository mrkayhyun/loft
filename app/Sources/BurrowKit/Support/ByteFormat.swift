import Foundation

public enum ByteFormat {
    /// Finder-style decimal size, e.g. "4.2 GB".
    public static func string(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false // "0 bytes", not "Zero KB"
        return formatter.string(fromByteCount: Int64(clamping: bytes))
    }

    /// Size split into number and unit for large typographic display.
    public static func parts(_ bytes: UInt64) -> (value: String, unit: String) {
        // Split at the last digit rather than a space: some locales ("ko")
        // write "293.02GB" with no separator.
        let text = string(bytes)
        guard let lastDigit = text.lastIndex(where: \.isNumber) else { return (text, "") }
        let splitAt = text.index(after: lastDigit)
        return (
            String(text[..<splitAt]).trimmingCharacters(in: .whitespaces),
            String(text[splitAt...]).trimmingCharacters(in: .whitespaces)
        )
    }

    public static func rate(_ bytesPerSecond: UInt64) -> String {
        "\(string(bytesPerSecond))/s"
    }
}
