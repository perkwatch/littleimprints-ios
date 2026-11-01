// Decorations.swift — stamps, frames, text, the date stamp, and the
// footprint-butterfly template (spec §4). All layers are
// non-destructive and sit beside/around the print by default —
// nothing covers the print unless the parent drags it there.

import SwiftUI

public enum StampCatalog {
    /// SF Symbol stamps (name, symbol).
    public static let symbols: [(name: String, symbol: String)] = [
        ("Heart", "heart.fill"),
        ("Star", "star.fill"),
        ("Moon", "moon.fill"),
        ("Crown", "crown.fill"),
        ("Sparkles", "sparkles"),
        ("Leaf", "leaf.fill"),
        ("Paw", "pawprint.fill"),
        ("Sun", "sun.max.fill"),
    ]
    /// Hand-drawn stamps (no SF Symbol does them justice).
    public static let drawn: [(name: String, symbol: String)] = [
        ("Butterfly", "drawn-butterfly"),
        ("Bow", "drawn-bow"),
        ("Flower", "drawn-flower"),
        ("Bee", "drawn-bee"),
    ]
    public static let frameStyles: [(name: String, symbol: String)] = [
        ("Thin line", "thin"),
        ("Stitched", "stitched"),
        ("Scalloped", "scalloped"),
    ]
}

/// A butterfly drawn from two wing ellipses and a body — also the
/// shape the butterfly template adds over a footprint.
struct ButterflyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX, cy = rect.midY
        let wingW = rect.width * 0.34, wingH = rect.height * 0.30
        // Upper + lower wings, both sides.
        for side in [-1.0, 1.0] {
            let upper = CGRect(x: cx + side * wingW * 0.85 - wingW / 2,
                               y: cy - wingH - rect.height * 0.04,
                               width: wingW, height: wingH)
            let lower = CGRect(x: cx + side * wingW * 0.80 - wingW / 2,
                               y: cy + rect.height * 0.03,
                               width: wingW * 0.86, height: wingH * 0.82)
            p.addEllipse(in: upper)
            p.addEllipse(in: lower)
        }
        // Body.
        p.addEllipse(in: CGRect(x: cx - rect.width * 0.045, y: cy - rect.height * 0.30,
                                width: rect.width * 0.09, height: rect.height * 0.60))
        // Antennae.
        var a = Path()
        a.move(to: CGPoint(x: cx, y: cy - rect.height * 0.28))
        a.addQuadCurve(to: CGPoint(x: cx - rect.width * 0.20, y: cy - rect.height * 0.52),
                       control: CGPoint(x: cx - rect.width * 0.16, y: cy - rect.height * 0.48))
        a.move(to: CGPoint(x: cx, y: cy - rect.height * 0.28))
        a.addQuadCurve(to: CGPoint(x: cx + rect.width * 0.20, y: cy - rect.height * 0.52),
                       control: CGPoint(x: cx + rect.width * 0.16, y: cy - rect.height * 0.48))
        return p.union(a.strokedPath(StrokeStyle(lineWidth: max(1.5, rect.width * 0.02),
                                                 lineCap: .round)))
    }
}

/// A simple bow: two loops and a knot.
struct BowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX, cy = rect.midY
        let loopW = rect.width * 0.34, loopH = rect.height * 0.52
        p.addEllipse(in: CGRect(x: cx - loopW - rect.width * 0.03, y: cy - loopH / 2,
                                width: loopW, height: loopH))
        p.addEllipse(in: CGRect(x: cx + rect.width * 0.03, y: cy - loopH / 2,
                                width: loopW, height: loopH))
        p.addEllipse(in: CGRect(x: cx - rect.width * 0.09, y: cy - rect.height * 0.13,
                                width: rect.width * 0.18, height: rect.height * 0.26))
        return p
    }
}

/// A five-petal flower with a round heart.
struct FlowerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX, cy = rect.midY
        let petalR = rect.width * 0.20
        for k in 0..<5 {
            let ang = Double(k) / 5 * 2 * Double.pi - Double.pi / 2
            let px = cx + CGFloat(cos(ang)) * rect.width * 0.24
            let py = cy + CGFloat(sin(ang)) * rect.height * 0.24
            p.addEllipse(in: CGRect(x: px - petalR / 2, y: py - petalR / 2,
                                    width: petalR, height: petalR))
        }
        p.addEllipse(in: CGRect(x: cx - petalR * 0.38, y: cy - petalR * 0.38,
                                width: petalR * 0.76, height: petalR * 0.76))
        return p
    }
}

/// A bee: round body, head, two wings, a small stinger —
/// a single-color silhouette that still reads as a bee.
struct BeeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX, cy = rect.midY + rect.height * 0.08
        // Wings (behind the body, poking up both sides).
        for side in [-1.0, 1.0] {
            p.addEllipse(in: CGRect(x: cx + side * rect.width * 0.20 - rect.width * 0.14,
                                    y: cy - rect.height * 0.46,
                                    width: rect.width * 0.28, height: rect.height * 0.30))
        }
        // Body + head.
        p.addEllipse(in: CGRect(x: cx - rect.width * 0.30, y: cy - rect.height * 0.24,
                                width: rect.width * 0.60, height: rect.height * 0.52))
        p.addEllipse(in: CGRect(x: cx - rect.width * 0.13, y: cy - rect.height * 0.44,
                                width: rect.width * 0.26, height: rect.height * 0.26))
        // Stinger.
        var s = Path()
        s.move(to: CGPoint(x: cx - rect.width * 0.07, y: cy + rect.height * 0.24))
        s.addLine(to: CGPoint(x: cx + rect.width * 0.07, y: cy + rect.height * 0.24))
        s.addLine(to: CGPoint(x: cx, y: cy + rect.height * 0.42))
        s.closeSubpath()
        return p.union(s)
    }
}

extension DecorationLayer {
    /// The SwiftUI design matching fontStyle (kept here, not in
    /// Models, so the model layer stays Foundation-only).
    var fontDesign: Font.Design {
        switch fontStyle {
        case "serif": return .serif
        case "typewriter": return .monospaced
        default: return .rounded
        }
    }
}

/// One decoration layer rendered on the page canvas.
struct DecorationView: View {
    let layer: DecorationLayer
    let pageSize: CGSize

    var body: some View {
        let w = pageSize.width * layer.scale
        Group {
            switch layer.kind {
            case .stamp:
                stampBody
                    .frame(width: w, height: w)
            case .text:
                Text(layer.text)
                    .font(.system(size: max(13, w / max(6, Double(layer.text.count) * 0.62)),
                                  design: layer.fontDesign).weight(.semibold))
                    .foregroundColor(Color(layer.color))
                    .lineLimit(1)
                    .frame(width: w * 1.9)
            case .dateStamp:
                dateStampBody(w)
            case .frame:
                EmptyView() // frames render as a page overlay, not a layer body
            case .butterfly:
                ButterflyShape()
                    .fill(Color(layer.color))
                    .frame(width: w * 1.7, height: w * 1.7)
            }
        }
        .rotationEffect(.degrees(layer.rotationDeg))
    }

    @ViewBuilder
    private var stampBody: some View {
        switch layer.symbol {
        case "drawn-butterfly":
            ButterflyShape().fill(Color(layer.color))
        case "drawn-bow":
            BowShape().fill(Color(layer.color))
        case "drawn-flower":
            FlowerShape().fill(Color(layer.color))
        case "drawn-bee":
            BeeShape().fill(Color(layer.color))
        default:
            Image(systemName: layer.symbol)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color(layer.color))
        }
    }

    private func dateStampBody(_ w: Double) -> some View {
        Text(layer.text.uppercased())
            .font(.system(size: max(10, w * 0.16), weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundColor(Color(layer.color))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(layer.color), lineWidth: 1.6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color(layer.color), lineWidth: 1)
                    .padding(-3)
            )
            .frame(width: w * 1.8)
    }
}

/// The page frame, drawn over the whole page (spec §4).
struct PageFrameView: View {
    let style: String
    let color: InkColor
    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(x: 10, y: 10,
                              width: geo.size.width - 20, height: geo.size.height - 20)
            switch style {
            case "stitched":
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(color),
                                  style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .padding(10)
            case "scalloped":
                ScallopRect(rect: rect)
                    .stroke(Color(color), lineWidth: 2)
            default: // thin
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(color), lineWidth: 2)
                    .padding(10)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A rectangle whose edges ripple in scallops.
struct ScallopRect: Shape {
    let rect: CGRect
    func path(in rectIgnored: CGRect) -> Path {
        let r = rect
        let bump = 14.0
        var p = Path()
        // Walk each edge placing semicircle bumps.
        func edge(from a: CGPoint, to b: CGPoint) {
            let len = hypot(b.x - a.x, b.y - a.y)
            let n = max(2, Int(len / bump))
            let step = len / Double(n)
            let dir = CGPoint(x: (b.x - a.x) / len, y: (b.y - a.y) / len)
            let normal = CGPoint(x: -dir.y, y: dir.x)
            var cur = a
            p.move(to: cur)
            for i in 1...n {
                let end = CGPoint(x: a.x + dir.x * step * Double(i),
                                  y: a.y + dir.y * step * Double(i))
                let mid = CGPoint(x: (cur.x + end.x) / 2 + normal.x * step * 0.32,
                                  y: (cur.y + end.y) / 2 + normal.y * step * 0.32)
                p.addQuadCurve(to: end, control: mid)
                cur = end
            }
        }
        let tl = CGPoint(x: r.minX, y: r.minY), tr = CGPoint(x: r.maxX, y: r.minY)
        let br = CGPoint(x: r.maxX, y: r.maxY), bl = CGPoint(x: r.minX, y: r.maxY)
        edge(from: tl, to: tr)
        edge(from: tr, to: br)
        edge(from: br, to: bl)
        edge(from: bl, to: tl)
        p.closeSubpath()
        return p
    }
}
