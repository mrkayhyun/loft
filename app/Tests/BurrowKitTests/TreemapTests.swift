import CoreGraphics
import Testing
@testable import BurrowKit

@Suite("Squarified treemap")
struct TreemapTests {
    private let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)

    @Test func tilesCoverTheBoundsProportionally() {
        let items: [(id: String, value: Double)] = [("a", 6), ("b", 6), ("c", 4), ("d", 3), ("e", 2), ("f", 2), ("g", 1)]
        let tiles = Treemap.layout(items, in: bounds)
        #expect(tiles.count == items.count)
        let area = tiles.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        #expect(abs(area - Double(bounds.width * bounds.height)) < 0.5)
        let a = tiles.first { $0.id == "a" }!.rect
        let g = tiles.first { $0.id == "g" }!.rect
        #expect(abs(Double(a.width * a.height) / Double(g.width * g.height) - 6) < 0.01)
    }

    @Test func tilesStayInsideBounds() {
        let items = (1...40).map { (id: $0, value: Double($0 * $0)) }
        for tile in Treemap.layout(items, in: bounds) {
            #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(tile.rect))
        }
    }

    @Test func dropsEmptyValuesAndHandlesDegenerateBounds() {
        #expect(Treemap.layout([(id: "x", value: 0)], in: bounds).isEmpty)
        #expect(Treemap.layout([(id: "x", value: 5)], in: .zero).isEmpty)
    }

    @Test func formatsBytesInDecimalUnits() {
        let parts = ByteFormat.parts(2_300_000_000)
        #expect(parts.unit == "GB")
        #expect(parts.value.hasPrefix("2"))
    }
}
