// TEMPORARY DEBUG PROBE 3 — normalized coverage for the big-toe case.
import Foundation

func synthPress(missingDigit: Int?, seed: UInt64) -> [ContactSample] {
    let prior = shapePrior(kind: .foot, ageMonths: 3.5)
    let mmpt = 0.1657
    let lengthPT = typicalFootLengthMM(ageMonths: 3.5) / mmpt
    var rng = SplitMix64(seed: seed)
    var samples: [ContactSample] = []
    var gx = 4.0
    while gx < lengthPT {
        var gy = 4.0
        while gy < lengthPT {
            let u = gx / lengthPT, v = gy / lengthPT
            if pointInPolygon(Point2(u, v), prior.outline) {
                var excluded = false
                if let md = missingDigit {
                    let spot = prior.digits[md]
                    let dx = (u - spot.center.x) / spot.radii.x
                    let dy = (v - spot.center.y) / spot.radii.y
                    if dx * dx + dy * dy < 0.95 { excluded = true }
                }
                if !excluded {
                    let t = rng.nextDouble() * 0.8
                    samples.append(ContactSample(x: gx + rng.nextJitter() * 1.5 + t * 2.0,
                                                 y: gy + rng.nextJitter() * 1.5 + t * 0.8,
                                                 radius: 11 + rng.nextJitter() * 2.5, t: t))
                }
            }
            gy += 9.0
        }
        gx += 9.0
    }
    return samples
}

func probe(_ label: String, _ samples: [ContactSample]) {
    let cl = PrintBuild.largestCluster(samples)
    let h = 2.0
    var minX = Double.greatestFiniteMagnitude, minY = minX
    var maxX = -minX, maxY = -minX
    for s in cl {
        minX = min(minX, s.x - s.radius); maxX = max(maxX, s.x + s.radius)
        minY = min(minY, s.y - s.radius); maxY = max(maxY, s.y + s.radius)
    }
    minX -= 6; minY -= 6; maxX += 6; maxY += 6
    let nx = max(4, Int(((maxX - minX) / h).rounded()) + 1)
    let ny = max(4, Int(((maxY - minY) / h).rounded()) + 1)
    var field = [Double](repeating: 0, count: nx * ny)
    for s in cl {
        let r = max(s.radius, 2)
        let i0 = max(0, Int(((s.x - r - minX) / h).rounded(.down)))
        let i1 = min(nx - 1, Int(((s.x + r - minX) / h).rounded(.up)))
        let j0 = max(0, Int(((s.y - r - minY) / h).rounded(.down)))
        let j1 = min(ny - 1, Int(((s.y + r - minY) / h).rounded(.up)))
        for j in j0...j1 {
            let py = minY + Double(j) * h
            for i in i0...i1 {
                let px = minX + Double(i) * h
                let d = ((px - s.x) * (px - s.x) + (py - s.y) * (py - s.y)).squareRoot() / r
                if d < 1 {
                    let v = 1 - d * d
                    let idx = j * nx + i
                    if v > field[idx] { field[idx] = v }
                }
            }
        }
    }
    var mask = field.map { $0 >= PrintBuild.isoLevel }
    mask = PrintBuild.erode(PrintBuild.dilate(mask, nx, ny), nx, ny)
    mask = PrintBuild.dilate(PrintBuild.erode(mask, nx, ny), nx, ny)
    mask = PrintBuild.keepComponents(mask, nx, ny, minNodes: 10)
    var fMinI = nx, fMinJ = ny, fMaxI = -1, fMaxJ = -1
    for j in 0..<ny {
        for i in 0..<nx where mask[j * nx + i] {
            fMinI = min(fMinI, i); fMaxI = max(fMaxI, i)
            fMinJ = min(fMinJ, j); fMaxJ = max(fMaxJ, j)
        }
    }
    let frameOrigin = Point2(Double(fMinI) * h, Double(fMinJ) * h)
    let frameW = Double(fMaxI - fMinI) * h
    let frameH = Double(fMaxJ - fMinJ) * h
    let prior = shapePrior(kind: .foot, ageMonths: 3.5)
    var oMinX = Double.greatestFiniteMagnitude, oMinY = oMinX
    var oMaxX = -oMinX, oMaxY = -oMinX
    for p in prior.outline {
        oMinX = min(oMinX, p.x); oMaxX = max(oMaxX, p.x)
        oMinY = min(oMinY, p.y); oMaxY = max(oMaxY, p.y)
    }
    let oW = oMaxX - oMinX, oH = oMaxY - oMinY
    func norm(_ spot: DigitSpot) -> DigitSpot {
        DigitSpot(center: Point2((spot.center.x - oMinX) / oW, (spot.center.y - oMinY) / oH),
                  radii: Point2(spot.radii.x / oW, spot.radii.y / oH), angleDeg: spot.angleDeg)
    }
    print("== \(label): frame", frameW, "x", frameH)
    for mirror in [false, true] {
        for extFrac in [0.0, 0.06, 0.12, 0.18, 0.24] {
            let ext = frameH * extFrac
            let o = Point2(frameOrigin.x, frameOrigin.y - ext)
            let fh = frameH + ext
            let palm = PrintBuild.ellipseCoverage(mask: mask, nx: nx, ny: ny, h: h,
                                                  frameOrigin: o, frameW: frameW, frameH: fh,
                                                  spot: norm(prior.palm), mirrorX: mirror)
            var covs: [String] = []
            for d in prior.digits {
                let c = PrintBuild.ellipseCoverage(mask: mask, nx: nx, ny: ny, h: h,
                                                   frameOrigin: o, frameW: frameW, frameH: fh,
                                                   spot: norm(d), mirrorX: mirror)
                covs.append(String(format: "%.2f", c))
            }
            print("  mirror", mirror, "ext", extFrac, "palm", String(format: "%.2f", palm),
                  "digits", covs.joined(separator: " "))
        }
    }
    var f2 = field, m2 = mask
    let filled = PrintBuild.tryFillMissingDigit(field: &f2, mask: &m2, nx: nx, ny: ny, h: h,
                                                kind: .foot, ageMonths: 3.5)
    print("  tryFill ->", filled)
}
probe("full foot", synthPress(missingDigit: nil, seed: 11))
probe("no big toe (idx 0)", synthPress(missingDigit: 0, seed: 13))
