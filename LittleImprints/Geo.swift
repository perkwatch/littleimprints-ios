// Geo.swift — pure geometry + shared enums. Foundation only:
// this file is compiled and exercised by tools/check-pure.swift
// (the pure-logic harness) as well as by the app.

import Foundation

public enum PrintKind: String, Codable, CaseIterable {
    case hand
    case foot
    public var label: String { self == .hand ? "Hand" : "Foot" }
}

public enum PrintMaterial: String, Codable, CaseIterable {
    case ink
    case paint
    public var label: String { self == .ink ? "Ink" : "Paint" }
}

/// A 2D point. In capture space: UIKit points, y down.
/// In print space: points relative to the print outline's bounding box.
public struct Point2: Codable, Equatable, Hashable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static let zero = Point2(0, 0)
    public static func + (a: Point2, b: Point2) -> Point2 { Point2(a.x + b.x, a.y + b.y) }
    public static func - (a: Point2, b: Point2) -> Point2 { Point2(a.x - b.x, a.y - b.y) }
    public static func * (a: Point2, s: Double) -> Point2 { Point2(a.x * s, a.y * s) }
    public static func / (a: Point2, s: Double) -> Point2 { Point2(a.x / s, a.y / s) }
    public var length: Double { (x * x + y * y).squareRoot() }
    public func distance(to other: Point2) -> Double { (self - other).length }
    public func clampedLength(max m: Double) -> Point2 {
        let l = length
        if l <= m || l == 0 { return self }
        return self * (m / l)
    }
}

public func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    min(hi, max(lo, v))
}

public func lerpD(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

/// Even-odd point-in-polygon test. Polygon is a closed loop (last point
/// need not repeat the first).
public func pointInPolygon(_ p: Point2, _ poly: [Point2]) -> Bool {
    guard poly.count >= 3 else { return false }
    var inside = false
    var j = poly.count - 1
    for i in 0..<poly.count {
        let a = poly[i], b = poly[j]
        if (a.y > p.y) != (b.y > p.y) {
            let xAtY = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
            if p.x < xAtY { inside.toggle() }
        }
        j = i
    }
    return inside
}

/// Polygon area (shoelace), always positive.
public func polygonArea(_ poly: [Point2]) -> Double {
    guard poly.count >= 3 else { return 0 }
    var sum = 0.0
    for i in 0..<poly.count {
        let a = poly[i], b = poly[(i + 1) % poly.count]
        sum += a.x * b.y - b.x * a.y
    }
    return abs(sum) / 2
}
