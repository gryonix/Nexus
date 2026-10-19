import CoreGraphics
import Foundation
import SwiftUI

/// Country outlines from the bundled world-map.json, in map units.
struct WorldMap {
    struct Country {
        let path: CGPath
        /// The outline, built once
        let shape: Path
        let bounds: CGRect
        let center: CGPoint
        /// Distance from the center to the farthest outline corner
        let reach: CGFloat
        /// Too small for a shape, so drawn as a dot
        let isTiny: Bool
    }

    let size: CGSize
    let countries: [String: Country]
    /// Every shaped country in one path
    let land: Path
    let shaped: [String: Country]
    let dots: [String: Country]

    static let shared = WorldMap.load()
        ?? WorldMap(size: CGSize(width: 2, height: 1), countries: [:],
                    land: Path(), shaped: [:], dots: [:])

    static func load(from bundle: Bundle = .main) -> WorldMap? {
        guard let url = bundle.url(forResource: "world-map", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> WorldMap? {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        let countries = file.c.mapValues { country(from: $0) }
        let shaped = countries.filter { !$0.value.isTiny }
        var land = Path()
        for country in shaped.values { land.addPath(country.shape) }
        return WorldMap(size: CGSize(width: file.w, height: file.h), countries: countries,
                        land: land, shaped: shaped,
                        dots: countries.filter { $0.value.isTiny })
    }

    /// The country under a point, preferring real shapes
    func country(at point: CGPoint, tolerance: CGFloat) -> String? {
        if let hit = countries.first(where: { !$0.value.isTiny && $0.value.path.contains(point) }) {
            return hit.key
        }
        let near = countries
            .map { ($0.key, hypot($0.value.center.x - point.x, $0.value.center.y - point.y)) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }
        return near?.0
    }

    private struct File: Decodable {
        struct Entry: Decodable {
            let x: Int
            let y: Int
            let r: [[Int]]
        }
        let w: Int
        let h: Int
        let c: [String: Entry]
    }

    private static func country(from entry: File.Entry) -> Country {
        let path = CGMutablePath()
        for ring in entry.r {
            var x = 0, y = 0
            for index in stride(from: 0, to: ring.count - 1, by: 2) {
                x += ring[index]
                y += ring[index + 1]
                let point = CGPoint(x: x, y: y)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
        let center = CGPoint(x: entry.x, y: entry.y)
        let box = path.boundingBoxOfPath
        let reach = entry.r.isEmpty ? 0 : [box.minX, box.maxX].flatMap { x in
            [box.minY, box.maxY].map { y in hypot(x - center.x, y - center.y) }
        }.max() ?? 0
        let isTiny = entry.r.isEmpty || max(box.width, box.height) < 8
        return Country(path: path, shape: Path(path), bounds: box, center: center,
                       reach: reach, isTiny: isTiny)
    }
}
