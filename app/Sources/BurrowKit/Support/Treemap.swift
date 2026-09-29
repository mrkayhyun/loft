import CoreGraphics

/// Squarified treemap layout (Bruls, Huizing & van Wijk, 2000).
public enum Treemap {
    public struct Tile<ID: Hashable & Sendable>: Hashable, Sendable {
        public let id: ID
        public let rect: CGRect
    }

    /// Lay out `items` proportionally inside `bounds`. Items with non-positive
    /// values are dropped; output order follows descending value.
    public static func layout<ID: Hashable & Sendable>(
        _ items: [(id: ID, value: Double)],
        in bounds: CGRect
    ) -> [Tile<ID>] {
        let positive = items.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let total = positive.reduce(0) { $0 + $1.value }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        let scale = Double(bounds.width * bounds.height) / total
        let areas = positive.map { (id: $0.id, area: $0.value * scale) }

        var tiles: [Tile<ID>] = []
        var remaining = bounds
        var row: [(id: ID, area: Double)] = []
        var index = 0
        while index < areas.count {
            let next = areas[index]
            let side = Double(min(remaining.width, remaining.height))
            if row.isEmpty || worst(row + [next], side: side) <= worst(row, side: side) {
                row.append(next)
                index += 1
            } else {
                remaining = place(row, in: remaining, into: &tiles)
                row.removeAll()
            }
        }
        if !row.isEmpty {
            _ = place(row, in: remaining, into: &tiles)
        }
        return tiles
    }

    /// Worst aspect ratio in a row laid along a side of length `side`.
    private static func worst<ID>(_ row: [(id: ID, area: Double)], side: Double) -> Double {
        let sum = row.reduce(0) { $0 + $1.area }
        guard sum > 0, side > 0 else { return .infinity }
        let largest = row.map(\.area).max() ?? 0
        let smallest = row.map(\.area).min() ?? 0
        let sideSquared = side * side
        let sumSquared = sum * sum
        return max(sideSquared * largest / sumSquared, sumSquared / (sideSquared * smallest))
    }

    /// Place a finished row along the shorter side; return the leftover rect.
    private static func place<ID>(
        _ row: [(id: ID, area: Double)],
        in rect: CGRect,
        into tiles: inout [Tile<ID>]
    ) -> CGRect {
        let sum = row.reduce(0) { $0 + $1.area }
        if rect.width >= rect.height {
            let width = CGFloat(sum) / rect.height
            var y = rect.minY
            for entry in row {
                let height = CGFloat(entry.area) / width
                tiles.append(Tile(id: entry.id, rect: CGRect(x: rect.minX, y: y, width: width, height: height)))
                y += height
            }
            return CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height)
        } else {
            let height = CGFloat(sum) / rect.width
            var x = rect.minX
            for entry in row {
                let width = CGFloat(entry.area) / height
                tiles.append(Tile(id: entry.id, rect: CGRect(x: x, y: rect.minY, width: width, height: height)))
                x += width
            }
            return CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height)
        }
    }
}
