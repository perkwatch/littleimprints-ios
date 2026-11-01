// Export.swift — share & export (spec §6, §7.1).
// PNG/JPEG through the standard share sheet; a true-size PDF for
// the fridge; wallpaper renders at the device's exact pixel size.
// Honest note kept in the UI: iOS does not let an app set the
// wallpaper — we save the picture and walk the parent through it.

import SwiftUI
import UIKit

struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

public enum Exporter {

    // MARK: Print images

    /// The print on paper, ready for the share sheet.
    public static func shareImage(for record: PrintRecord) -> UIImage? {
        PrintRenderer.image(for: record, background: .cream, longEdgePx: 2048)
    }

    /// The print alone, transparent background (spec §6).
    public static func transparentImage(for record: PrintRecord) -> UIImage? {
        PrintRenderer.image(for: record, background: nil, longEdgePx: 2048)
    }

    // MARK: True-size PDF

    /// A page carrying the print at its REAL size — the number one
    /// keepsake export. Points are 1/72 inch, so the print's stored
    /// millimetres convert exactly. The image drawn is cropped to
    /// the print's own bounding box (the earlier version drew the
    /// whole padded canvas into the print's box — the ink landed
    /// ~10% small and stretched; review finding, fixed). The print
    /// is drawn as pressed: kept rotation/nudge are presentation
    /// adjustments, and the stored millimetres describe the
    /// as-pressed ink exactly.
    public static func pdfData(for record: PrintRecord, childName: String,
                               a4: Bool = false) -> Data? {
        let page = a4 ? CGRect(x: 0, y: 0, width: 595, height: 842)
                      : CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        guard let img = PrintRenderer.exactCroppedImage(for: record) else { return nil }
        return renderer.pdfData { ctx in
            ctx.beginPage()
            UIColor.white.setFill()
            ctx.fill(page)
            let ptPerMM = 72.0 / 25.4
            let wPT = CGFloat(record.shape.widthMM * ptPerMM)
            let hPT = CGFloat(record.shape.heightMM * ptPerMM)
            let x = (page.width - wPT) / 2
            // Captions ride below the print when they fit, above
            // it when the print is tall.
            let captionsBelow = hPT + 190 < page.height
            let y = captionsBelow ? max(84, (page.height - hPT) * 0.36)
                                  : page.height - 70 - hPT
            img.draw(in: CGRect(x: x, y: y, width: wPT, height: hPT))
            let center = NSMutableParagraphStyle()
            center.alignment = .center
            let titleFont = roundedFont(19, .semibold)
            let subFont = roundedFont(12.5, .regular)
            let name = childName.isEmpty ? "Baby" : childName
            let capY = captionsBelow ? y + hPT + 26 : y - 108
            drawText("\(name) — \(record.ageLabel)",
                     in: CGRect(x: 40, y: capY, width: page.width - 80, height: 28),
                     font: titleFont, color: .darkText, style: center)
            let dateFmt = DateFormatter()
            dateFmt.dateStyle = .long
            drawText("\(record.kind.label) print · \(dateFmt.string(from: record.createdAt))",
                     in: CGRect(x: 40, y: capY + 30, width: page.width - 80, height: 22),
                     font: subFont, color: .gray, style: center)
            drawText(String(format: "Actual size — %.1f × %.1f mm",
                            record.shape.widthMM, record.shape.heightMM),
                     in: CGRect(x: 40, y: capY + 52, width: page.width - 80, height: 22),
                     font: subFont, color: .gray, style: center)
            drawText("Print at 100% — no scaling, no “fit to page.” This is the real size of the print.",
                     in: CGRect(x: 40, y: page.height - 54, width: page.width - 80, height: 20),
                     font: subFont, color: .gray, style: center)
        }
    }

    /// The print on paper as a JPEG file (spec §6: PNG and JPEG) —
    /// some family apps and printers prefer it.
    public static func jpegFile(for record: PrintRecord) -> URL? {
        guard let img = shareImage(for: record),
              let data = img.jpegData(compressionQuality: 0.92) else { return nil }
        return tempFile(data: data, name: "little-imprints-print.jpg")
    }

    static func roundedFont(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        styledFont("rounded", size, weight)
    }

    /// The typeface for a text layer's fontStyle (§4's small set).
    static func styledFont(_ style: String, _ size: CGFloat,
                           _ weight: UIFont.Weight) -> UIFont {
        let design: UIFontDescriptor.SystemDesign
        switch style {
        case "serif": design = .serif
        case "typewriter": design = .monospaced
        default: design = .rounded
        }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let desc = base.fontDescriptor.withDesign(design) {
            return UIFont(descriptor: desc, size: size)
        }
        return base
    }

    private static func drawText(_ text: String, in rect: CGRect, font: UIFont,
                                 color: UIColor, style: NSParagraphStyle) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: style,
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    /// Writes data to a temporary file so the share sheet shows a
    /// proper filename.
    public static func tempFile(data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch { return nil }
    }

    // MARK: Wallpaper (spec §7.1)

    /// One print as a Lock Screen wallpaper, sized for the clock.
    public static func wallpaperImage(for record: PrintRecord, paper: InkColor) -> UIImage? {
        let size = ScreenMetrics.wallpaperPixelSize
        guard let img = transparentImage(for: record) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            UIColor(Color(paper)).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let w = size.width * 0.76
            let h = w * img.size.height / max(img.size.width, 1)
            img.draw(in: CGRect(x: (size.width - w) / 2, y: size.height * 0.60 - h / 2,
                                width: w, height: h))
        }
    }

    /// The footprint trail: her own footprints walking up the Lock
    /// Screen, alternating like real steps (spec §7.1).
    public static func trailWallpaperImage(for record: PrintRecord, paper: InkColor) -> UIImage? {
        let size = ScreenMetrics.wallpaperPixelSize
        guard record.kind == .foot,
              let img = transparentImage(for: record) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        var rng = SplitMix64(seed: record.seed &+ 0x77AA)
        return renderer.image { ctx in
            UIColor(Color(paper)).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            let steps = 7
            for i in 0..<steps {
                let t = Double(i) / Double(steps - 1)
                let cx = size.width * (0.5 + 0.24 * sin(t * 2.4 - 1.2))
                let cy = size.height * (0.33 + 0.57 * t)
                let w = size.width * (i % 2 == 0 ? 0.30 : 0.275)
                let h = w * img.size.height / max(img.size.width, 1)
                let rot = (i % 2 == 0 ? -11.0 : 11.0) + rng.nextJitter() * 3
                cg.saveGState()
                cg.setAlpha(CGFloat(1 - t * 0.22))
                cg.translateBy(x: cx, y: cy)
                cg.rotate(by: CGFloat(rot * Double.pi / 180))
                if i % 2 == 1 { cg.scaleBy(x: -1, y: 1) } // the other foot
                img.draw(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                cg.restoreGState()
            }
        }
    }
}

// MARK: - Page rendering for share-out

/// Draws a composed page to an image using the same layout the
/// canvas shows (page aspect 4:5, prints in order, then
/// decorations, then the frame on top).
public enum PageRenderer {
    public static func image(for page: PageRecord, store: LibraryStore,
                             widthPx: Int = 1800) -> UIImage? {
        let W = CGFloat(widthPx)
        let H = W * 5 / 4
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor(Color(page.paper)).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: W, height: H))
            for placed in page.prints {
                guard let record = store.printRecord(id: placed.printID),
                      let img = PrintRenderer.image(for: record, background: nil,
                                                    longEdgePx: 1100) else { continue }
                let w = W * CGFloat(placed.scale)
                let h = w * img.size.height / max(img.size.width, 1)
                let cx = W * CGFloat(placed.center.x)
                let cy = H * CGFloat(placed.center.y)
                cg.saveGState()
                cg.translateBy(x: cx, y: cy)
                cg.rotate(by: CGFloat(placed.rotationDeg * Double.pi / 180))
                img.draw(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                cg.restoreGState()
            }
            for layer in page.decorations where layer.kind != .frame {
                drawDecoration(layer, in: CGRect(x: 0, y: 0, width: W, height: H), cg: cg)
            }
            for layer in page.decorations where layer.kind == .frame {
                drawFrame(style: layer.symbol, color: layer.color,
                          in: CGRect(x: 0, y: 0, width: W, height: H), cg: cg)
            }
        }
    }

    private static func drawDecoration(_ layer: DecorationLayer, in page: CGRect, cg: CGContext) {
        let w = page.width * CGFloat(layer.scale)
        let cx = page.width * CGFloat(layer.center.x)
        let cy = page.height * CGFloat(layer.center.y)
        cg.saveGState()
        cg.translateBy(x: cx, y: cy)
        cg.rotate(by: CGFloat(layer.rotationDeg * Double.pi / 180))
        let uiColor = UIColor(Color(layer.color))
        switch layer.kind {
        case .stamp:
            switch layer.symbol {
            case "drawn-butterfly":
                let rect = CGRect(x: -w / 2, y: -w / 2, width: w, height: w)
                cg.addPath(ButterflyShape().path(in: rect).cgPath)
                uiColor.setFill(); cg.fillPath()
            case "drawn-bow":
                let rect = CGRect(x: -w / 2, y: -w / 2, width: w, height: w)
                cg.addPath(BowShape().path(in: rect).cgPath)
                uiColor.setFill(); cg.fillPath()
            case "drawn-flower":
                let rect = CGRect(x: -w / 2, y: -w / 2, width: w, height: w)
                cg.addPath(FlowerShape().path(in: rect).cgPath)
                uiColor.setFill(); cg.fillPath()
            case "drawn-bee":
                let rect = CGRect(x: -w / 2, y: -w / 2, width: w, height: w)
                cg.addPath(BeeShape().path(in: rect).cgPath)
                uiColor.setFill(); cg.fillPath()
            default:
                let cfg = UIImage.SymbolConfiguration(pointSize: w, weight: .semibold)
                if let img = UIImage(systemName: layer.symbol, withConfiguration: cfg)?
                    .withTintColor(uiColor, renderingMode: .alwaysOriginal) {
                    img.draw(in: CGRect(x: -w / 2, y: -w / 2, width: w, height: w))
                }
            }
        case .butterfly:
            let rect = CGRect(x: -w * 0.85, y: -w * 0.85, width: w * 1.7, height: w * 1.7)
            cg.addPath(ButterflyShape().path(in: rect).cgPath)
            uiColor.setFill(); cg.fillPath()
        case .text:
            let font = Exporter.styledFont(layer.fontStyle, max(12, w / CGFloat(max(6, Double(layer.text.count) * 0.62))), .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: uiColor]
            let s = layer.text as NSString
            let ts = s.size(withAttributes: attrs)
            s.draw(in: CGRect(x: -ts.width / 2, y: -ts.height / 2, width: ts.width, height: ts.height),
                   withAttributes: attrs)
        case .dateStamp:
            let font = UIFont.monospacedSystemFont(ofSize: max(10, w * 0.16), weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: uiColor]
            let s = layer.text.uppercased() as NSString
            let ts = s.size(withAttributes: attrs)
            let box = CGRect(x: -ts.width / 2 - 10, y: -ts.height / 2 - 5,
                             width: ts.width + 20, height: ts.height + 10)
            uiColor.setStroke()
            cg.setLineWidth(1.6)
            cg.addPath(RoundedRectPath(box, radius: 6))
            cg.strokePath()
            cg.setLineWidth(1)
            cg.addPath(RoundedRectPath(box.insetBy(dx: -3, dy: -3), radius: 9))
            cg.strokePath()
            s.draw(in: CGRect(x: -ts.width / 2, y: -ts.height / 2, width: ts.width, height: ts.height),
                   withAttributes: attrs)
        case .frame:
            break
        }
        cg.restoreGState()
    }

    private static func drawFrame(style: String, color: InkColor, in page: CGRect, cg: CGContext) {
        let rect = page.insetBy(dx: 26, dy: 26)
        UIColor(Color(color)).setStroke()
        switch style {
        case "stitched":
            cg.setLineDash(phase: 0, lengths: [16, 10])
            cg.setLineWidth(4)
            cg.addPath(RoundedRectPath(rect, radius: 30))
            cg.strokePath()
            cg.setLineDash(phase: 0, lengths: [])
        case "scalloped":
            cg.setLineWidth(4)
            cg.addPath(ScallopRect(rect: rect).path(in: rect).cgPath)
            cg.strokePath()
        default:
            cg.setLineWidth(4)
            cg.addPath(RoundedRectPath(rect, radius: 30))
            cg.strokePath()
        }
    }

    private static func RoundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}
