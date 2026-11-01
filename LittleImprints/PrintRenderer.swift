// PrintRenderer.swift — bakes a PrintShape into a print-quality
// image with the physics of real ink/paint (spec §2.3):
//   pressure falloff from the measured contact field,
//   a darker pooling rim where ink collects at the edge,
//   seeded grain (denser at the edges), small organic voids where
//   skin texture broke contact, and a directional micro-smudge
//   along the press's own drift.
// Ink: thinner, sharper, translucent. Paint: thicker, softer, opaque.
// Rendering is deterministic per print (seeded), so a keepsake
// re-renders identically forever.

import UIKit
import CoreGraphics

public enum PrintRenderer {

    // MARK: - Public entry points

    /// The print alone (transparent background unless `background`
    /// is given), with the record's kept rotation applied.
    public static func image(for record: PrintRecord,
                             background: InkColor? = nil,
                             longEdgePx: Int = 2048) -> UIImage? {
        guard let layer = makeLayer(shape: record.shape, color: record.color,
                                    material: record.material, seed: record.seed,
                                    longEdgePx: longEdgePx) else { return nil }
        return compose(layer: layer, shape: record.shape,
                       rotationDeg: record.rotationDeg, background: background,
                       offset: record.offset)
    }

    public static func pngData(for record: PrintRecord, transparent: Bool) -> Data? {
        image(for: record, background: transparent ? nil : InkColor(hex: "#FFFFFF"))?
            .pngData()
    }

    /// Crops a baked canvas image to the print's own bounding box —
    /// what the timeline's true-size frames and the book grid show,
    /// so displayed size equals the print's stored size exactly.
    public static func cropped(_ image: UIImage, shape: PrintShape) -> UIImage? {
        guard let cg = image.cgImage, shape.canvasW > 0, shape.canvasH > 0 else { return image }
        let sx = Double(cg.width) / shape.canvasW
        let sy = Double(cg.height) / shape.canvasH
        let rect = CGRect(x: shape.printOrigin.x * sx, y: shape.printOrigin.y * sy,
                          width: shape.printW * sx, height: shape.printH * sy)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard rect.width > 2, rect.height > 2,
              let cut = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cut, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Convenience: bake + crop in one call.
    public static func croppedImage(for record: PrintRecord,
                                    longEdgePx: Int = 900) -> UIImage? {
        guard let img = image(for: record, longEdgePx: longEdgePx) else { return nil }
        return cropped(img, shape: record.shape)
    }

    /// Crops a baked image to its actual ink by scanning the alpha
    /// channel — exact regardless of the rotation/nudge adjustments
    /// baked into the image (the shape-rect crop above is only exact
    /// for the as-pressed render). Used for display crops.
    public static func contentCropped(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return image }
        let maxSide = 220
        let f = Double(maxSide) / Double(max(cg.width, cg.height))
        let w = max(1, Int(Double(cg.width) * f)), h = max(1, Int(Double(cg.height) * f))
        var px = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &px, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
        else { return image }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minI = w, minJ = h, maxI = -1, maxJ = -1
        for j in 0..<h {
            for i in 0..<w where px[j * w + i] > 8 {
                minI = min(minI, i); maxI = max(maxI, i)
                minJ = min(minJ, j); maxJ = max(maxJ, j)
            }
        }
        guard maxI >= 0 else { return image }
        let cellW = Double(cg.width) / Double(w), cellH = Double(cg.height) / Double(h)
        let rect = CGRect(x: Double(minI) * cellW - cellW, y: Double(minJ) * cellH - cellH,
                          width: Double(maxI - minI + 1) * cellW + 2 * cellW,
                          height: Double(maxJ - minJ + 1) * cellH + 2 * cellH)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard rect.width > 2, rect.height > 2,
              let cut = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cut, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Display crop of a kept print (adjustments included, ink-exact).
    public static func displayCroppedImage(for record: PrintRecord,
                                           background: InkColor? = nil,
                                           longEdgePx: Int = 900) -> UIImage? {
        guard let img = image(for: record, background: background,
                              longEdgePx: longEdgePx) else { return nil }
        return contentCropped(img)
    }

    /// The print exactly as pressed — kept rotation/nudge are
    /// presentation adjustments, and size-claiming exports (the
    /// true-size PDF) use this as-pressed geometry so the stored
    /// millimetres describe the ink exactly.
    public static func asPressed(_ record: PrintRecord) -> PrintRecord {
        var r = record
        r.rotationDeg = 0
        r.offset = Point2(0, 0)
        return r
    }

    /// As-pressed render cropped by the shape's own geometry —
    /// dimensionally exact (this is what the PDF draws).
    public static func exactCroppedImage(for record: PrintRecord,
                                         longEdgePx: Int = 2048) -> UIImage? {
        let pressed = asPressed(record)
        guard let img = image(for: pressed, background: nil,
                              longEdgePx: longEdgePx) else { return nil }
        return cropped(img, shape: pressed.shape)
    }

    /// A print rendered straight from a shape (silhouette previews,
    /// the Nightstand Walk's placeholder prints).
    public static func image(shape: PrintShape, color: InkColor,
                             material: PrintMaterial, seed: UInt64,
                             background: InkColor? = nil,
                             longEdgePx: Int = 1600) -> UIImage? {
        guard let layer = makeLayer(shape: shape, color: color, material: material,
                                    seed: seed, longEdgePx: longEdgePx) else { return nil }
        return compose(layer: layer, shape: shape, rotationDeg: 0, background: background)
    }

    /// Builds a PrintShape from the age prior's outline — only for
    /// gentle placeholder art (Nightstand Walk before the first real
    /// capture). Never stored as a keepsake print.
    public static func silhouetteShape(kind: PrintKind, ageMonths: Double,
                                       lengthMM: Double, mmPerPoint: Double) -> PrintShape {
        let prior = shapePrior(kind: kind, ageMonths: ageMonths)
        let lengthPT = lengthMM / mmPerPoint
        let mapped = prior.outline.map { Point2($0.x * lengthPT, $0.y * lengthPT) }
        var minX = Double.greatestFiniteMagnitude, minY = minX
        var maxX = -minX, maxY = -minX
        for p in mapped {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let outline = mapped.map { Point2($0.x - minX, $0.y - minY) }
        let w = maxX - minX, h = maxY - minY
        // Pressure: rasterize the outline, then soften with box blurs.
        let gw = 96, gh = 96
        var grid = [Double](repeating: 0, count: gw * gh)
        for j in 0..<gh {
            for i in 0..<gw {
                let p = Point2((Double(i) + 0.5) / Double(gw) * w,
                               (Double(j) + 0.5) / Double(gh) * h)
                if pointInPolygon(p, outline) { grid[j * gw + i] = 1 }
            }
        }
        for _ in 0..<3 { grid = boxBlur(grid, gw, gh) }
        var bytes = [UInt8](repeating: 0, count: gw * gh)
        for idx in 0..<grid.count {
            bytes[idx] = UInt8(clampD(grid[idx], 0, 1) * 235)
        }
        return PrintShape(
            outline: outline, canvasW: w, canvasH: h,
            printW: w, printH: h, printOrigin: .zero,
            widthMM: w * mmPerPoint, heightMM: h * mmPerPoint,
            areaMM2: polygonArea(outline) * mmPerPoint * mmPerPoint,
            gridW: gw, gridH: gh, gridB64: Data(bytes).base64EncodedString(),
            voids: [], motion: .zero, digitFilled: false)
    }

    // MARK: - Layer bake

    private static func cgColor(_ c: InkColor, alpha: Double = 1) -> CGColor {
        CGColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b),
                alpha: CGFloat(alpha))
    }

    private static func pathFromOutline(_ outline: [Point2], scale s: Double) -> CGMutablePath {
        let path = CGMutablePath()
        guard let first = outline.first else { return path }
        path.move(to: CGPoint(x: first.x * s, y: first.y * s))
        for p in outline.dropFirst() {
            path.addLine(to: CGPoint(x: p.x * s, y: p.y * s))
        }
        path.closeSubpath()
        return path
    }

    private static func makeLayer(shape: PrintShape, color: InkColor,
                                  material: PrintMaterial, seed: UInt64,
                                  longEdgePx: Int) -> CGImage? {
        let longEdgePT = max(shape.canvasW, shape.canvasH)
        guard longEdgePT > 0 else { return nil }
        let s = Double(longEdgePx) / longEdgePT
        let W = max(2, Int((shape.canvasW * s).rounded()))
        let H = max(2, Int((shape.canvasH * s).rounded()))
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: W, height: H,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Work in y-down (screen) coordinates inside the layer.
        ctx.translateBy(x: 0, y: CGFloat(H))
        ctx.scaleBy(x: 1, y: -1)

        let path = pathFromOutline(shape.outline, scale: s)
        ctx.addPath(path)
        ctx.clip()

        let isInk = material == .ink
        // Base fill.
        ctx.setFillColor(cgColor(color, alpha: isInk ? 0.88 : 0.97))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        // Pressure falloff: multiply by a factor image built from
        // the measured contact field (centers full, edges washed).
        let values = PrintBuild.gridValues(shape)
        if values.count == shape.gridW * shape.gridH, shape.gridW > 0 {
            var bytes = [UInt8](repeating: 0, count: values.count)
            for i in 0..<values.count {
                let f = isInk ? 0.45 + 0.55 * values[i] : 0.62 + 0.38 * values[i]
                bytes[i] = UInt8(clampD(f, 0, 1) * 255)
            }
            if let img = grayImage(bytes: bytes, w: shape.gridW, h: shape.gridH) {
                ctx.saveGState()
                ctx.setBlendMode(.multiply)
                ctx.interpolationQuality = .high
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
                ctx.restoreGState()
            }
        }

        // Pooling rim: layered strokes, clipped inside the print.
        let rimBase = max(1.5, 0.016 * Double(min(W, H)))
        let rimColor = color.darkened(by: 0.22)
        for (mult, alpha) in [(1.0, 0.30), (2.2, 0.15), (4.0, 0.07)] {
            ctx.setStrokeColor(cgColor(rimColor, alpha: alpha))
            ctx.setLineWidth(CGFloat(rimBase * mult * (isInk ? 1.0 : 1.35)))
            ctx.addPath(path)
            ctx.strokePath()
        }

        // Grain: seeded speckle, biased toward the edges (where the
        // measured pressure was low), never outside the print.
        var rng = SplitMix64(seed: seed &+ 0x51AB)
        let dotCount = min(isInk ? 4200 : 2600, max(300, W * H / 650))
        let bbox = path.boundingBoxOfPath
        for _ in 0..<dotCount {
            let px = Double(bbox.minX) + rng.nextDouble() * Double(bbox.width)
            let py = Double(bbox.minY) + rng.nextDouble() * Double(bbox.height)
            let pt = CGPoint(x: px, y: py)
            if !path.contains(pt, using: .evenOdd) { continue }
            let u = px / Double(W), v = py / Double(H)
            let pressure = bilinear(values, shape.gridW, shape.gridH, u, v)
            if rng.nextDouble() < pressure * 0.75 { continue } // edges keep more grain
            let lighten = rng.nextDouble() > 0.5
            let dotColor = lighten ? color.lightened(by: 0.16) : color.darkened(by: 0.16)
            ctx.setFillColor(cgColor(dotColor, alpha: 0.05 + rng.nextDouble() * 0.08))
            let r = (isInk ? 0.9 : 1.6) + rng.nextDouble() * 1.3
            ctx.fillEllipse(in: CGRect(x: px - r / 2, y: py - r / 2, width: r, height: r))
        }

        // Voids: soft punches where skin texture broke contact.
        if !shape.voids.isEmpty {
            ctx.saveGState()
            ctx.setBlendMode(.destinationOut)
            var vrng = SplitMix64(seed: seed &+ 0x9E37)
            for v in shape.voids {
                let cx = v.x * Double(W), cy = v.y * Double(H)
                let r = (0.010 + vrng.nextDouble() * 0.016) * Double(min(W, H))
                let colors = [CGColor(gray: 1, alpha: 0.85), CGColor(gray: 1, alpha: 0)] as CFArray
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                                         colors: colors, locations: [0, 1]) {
                    ctx.drawRadialGradient(grad,
                                           startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                           endCenter: CGPoint(x: cx, y: cy), endRadius: CGFloat(r),
                                           options: [])
                }
            }
            ctx.restoreGState()
        }

        return ctx.makeImage()
    }

    private static func grayImage(bytes: [UInt8], w: Int, h: Int) -> CGImage? {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    private static func bilinear(_ values: [Double], _ gw: Int, _ gh: Int,
                                 _ u: Double, _ v: Double) -> Double {
        guard gw > 1, gh > 1, values.count == gw * gh else { return 1 }
        let x = clampD(u, 0, 1) * Double(gw - 1)
        let y = clampD(v, 0, 1) * Double(gh - 1)
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let x1 = min(x0 + 1, gw - 1), y1 = min(y0 + 1, gh - 1)
        let fx = x - Double(x0), fy = y - Double(y0)
        let a = values[y0 * gw + x0], b = values[y0 * gw + x1]
        let c = values[y1 * gw + x0], d = values[y1 * gw + x1]
        return lerpD(lerpD(a, b, fx), lerpD(c, d, fx), fy)
    }

    private static func boxBlur(_ g: [Double], _ w: Int, _ h: Int) -> [Double] {
        var out = g
        for j in 0..<h {
            for i in 0..<w {
                var sum = 0.0, n = 0.0
                for dj in -1...1 {
                    for di in -1...1 {
                        let ii = i + di, jj = j + dj
                        if ii >= 0, ii < w, jj >= 0, jj < h {
                            sum += g[jj * w + ii]; n += 1
                        }
                    }
                }
                out[j * w + i] = sum / n
            }
        }
        return out
    }

    // MARK: - Composition (background, rotation, smudge)

    private static func compose(layer: CGImage, shape: PrintShape,
                                rotationDeg: Double, background: InkColor?,
                                offset: Point2 = .zero) -> UIImage? {
        if background == nil && rotationDeg == 0 && offset.length < 0.5 && shape.motion.length < 0.4 {
            return UIImage(cgImage: layer)
        }
        let W = layer.width, H = layer.height
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: W, height: H,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        if let bg = background {
            ctx.setFillColor(cgColor(bg))
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            // Paper grain (§2.3): a whisper of seeded speckle over
            // the sheet so exports sit on paper, not on flat color.
            // Deterministic per print (seeded from its geometry).
            var grain = SplitMix64(seed: UInt64(abs(shape.canvasW * 131 + shape.canvasH * 17)) &+ 0x6A17)
            let dots = max(300, (W * H) / 850)
            for _ in 0..<dots {
                let gx = grain.nextDouble() * Double(W)
                let gy = grain.nextDouble() * Double(H)
                let r = 0.5 + grain.nextDouble() * 1.1
                let dark = grain.nextDouble() > 0.42
                ctx.setFillColor(CGColor(red: dark ? 0.45 : 1.0,
                                         green: dark ? 0.38 : 0.99,
                                         blue: dark ? 0.30 : 0.94,
                                         alpha: CGFloat(0.028 + grain.nextDouble() * 0.03)))
                ctx.fillEllipse(in: CGRect(x: gx - r, y: gy - r, width: r * 2, height: r * 2))
            }
        }
        let cx = Double(W) / 2, cy = Double(H) / 2
        let s = Double(W) / shape.canvasW
        func drawLayer(alpha: Double, extraOffset: Point2) {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(alpha))
            ctx.translateBy(x: CGFloat(cx), y: CGFloat(cy))
            ctx.rotate(by: CGFloat(-rotationDeg * Double.pi / 180))
            ctx.translateBy(x: CGFloat(-cx + (offset.x + extraOffset.x) * s),
                            y: CGFloat(-cy - (offset.y + extraOffset.y) * s))
            ctx.draw(layer, in: CGRect(x: 0, y: 0, width: W, height: H))
            ctx.restoreGState()
        }
        // The micro-smudge: a faint ghost dragged along the drift.
        if shape.motion.length >= 0.4 {
            drawLayer(alpha: 0.16, extraOffset: shape.motion)
        }
        drawLayer(alpha: 1, extraOffset: .zero)
        guard let img = ctx.makeImage() else { return nil }
        return UIImage(cgImage: img)
    }
}