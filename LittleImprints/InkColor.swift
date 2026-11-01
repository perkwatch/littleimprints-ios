// InkColor.swift — color storage + palettes. Foundation only.
// Colors live as plain RGB doubles so records stay portable and the
// pure harness can verify the math; SwiftUI/CoreGraphics colors are
// derived at the view/render layer.

import Foundation

public struct InkColor: Codable, Equatable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(r: Double, g: Double, b: Double) {
        self.r = clampD(r, 0, 1)
        self.g = clampD(g, 0, 1)
        self.b = clampD(b, 0, 1)
    }

    public init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count == 6 {
            self.init(r: Double((v >> 16) & 0xFF) / 255,
                      g: Double((v >> 8) & 0xFF) / 255,
                      b: Double(v & 0xFF) / 255)
        } else {
            self.init(r: 0.16, g: 0.21, b: 0.36) // midnight fallback
        }
    }

    public var hexString: String {
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }

    public func darkened(by f: Double) -> InkColor {
        InkColor(r: r * (1 - f), g: g * (1 - f), b: b * (1 - f))
    }

    public func lightened(by f: Double) -> InkColor {
        InkColor(r: r + (1 - r) * f, g: g + (1 - g) * f, b: b + (1 - b) * f)
    }

    /// Perceived luminance (sRGB weights) — used to keep text legible
    /// on colored paper and to pick a caption ink.
    public var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
}

public struct PaletteSwatch: Codable, Equatable {
    public let name: String
    public let hex: String
    public var color: InkColor { InkColor(hex: hex) }
    public init(name: String, hex: String) { self.name = name; self.hex = hex }
}

public enum InkPalette {
    /// Ink-pad classics (spec §3).
    public static let classics: [PaletteSwatch] = [
        PaletteSwatch(name: "Midnight Blue", hex: "#26355D"),
        PaletteSwatch(name: "Crimson", hex: "#9E2A2B"),
        PaletteSwatch(name: "Plum", hex: "#5E2750"),
        PaletteSwatch(name: "Forest", hex: "#2E5339"),
        PaletteSwatch(name: "Charcoal", hex: "#2B2B2B"),
        PaletteSwatch(name: "Gold", hex: "#B98A2F"),
    ]
    /// Baby-gentle pastels (spec §3).
    public static let pastels: [PaletteSwatch] = [
        PaletteSwatch(name: "Blush", hex: "#E2A2B4"),
        PaletteSwatch(name: "Baby Blue", hex: "#A8C3E8"),
        PaletteSwatch(name: "Mint", hex: "#A9D6B5"),
        PaletteSwatch(name: "Lilac", hex: "#C3A6D9"),
        PaletteSwatch(name: "Peach", hex: "#F2C29B"),
        PaletteSwatch(name: "Butter", hex: "#EBD88A"),
    ]
    public static var all: [PaletteSwatch] { classics + pastels }
}

public enum PaperPalette {
    public static let papers: [PaletteSwatch] = [
        PaletteSwatch(name: "White", hex: "#FFFFFF"),
        PaletteSwatch(name: "Cream", hex: "#FAF3E3"),
        PaletteSwatch(name: "Kraft", hex: "#D9B98A"),
        PaletteSwatch(name: "Soft Pink", hex: "#F7E1E3"),
        PaletteSwatch(name: "Soft Blue", hex: "#E2EBF5"),
        PaletteSwatch(name: "Sage", hex: "#DCE5D8"),
    ]
}
