// TEMPORARY DEBUG PROBE — bisect PrintBuild.build's stages.
import Foundation

func probe() {
    let mmpt = 0.1657
    // Rebuild the harness's full-foot press (same recipe as main.swift).
    let prior = shapePrior(kind: .foot, ageMonths: 3.5)
    let lengthPT = typicalFootLengthMM(ageMonths: 3.5) / mmpt
    var rng = SplitMix64(seed: 11)
    var samples: [ContactSample] = []
    var gx = 4.0
    while gx < lengthPT {
        var gy = 4.0
        while gy < lengthPT {
            let p = Point2(gx / lengthPT, gy / lengthPT)
            if pointInPolygon(p, prior.outline) {
                let t = rng.nextDouble() * 0.8
                samples.append(ContactSample(x: gx + rng.nextJitter() * 1.5 + t * 2.0,
                                             y: gy + rng.nextJitter() * 1.5 + t * 0.8,
                                             radius: 11 + rng.nextJitter() * 2.5, t: t))
            }
            gy += 9.0
        }
        gx += 9.0
    }
    print("samples:", samples.count)
    let cl = PrintBuild.largestCluster(samples)
    print("cluster:", cl.count)
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
    print("lattice:", nx, "x", ny, "=", nx * ny)
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
    print("field max:", field.max() ?? -1)
    var mask = field.map { $0 >= PrintBuild.isoLevel }
    print("mask raw:", mask.filter { $0 }.count)
    mask = PrintBuild.erode(PrintBuild.dilate(mask, nx, ny), nx, ny)
    print("mask after close:", mask.filter { $0 }.count)
    mask = PrintBuild.dilate(PrintBuild.erode(mask, nx, ny), nx, ny)
    print("mask after open:", mask.filter { $0 }.count)
    mask = PrintBuild.keepComponents(mask, nx, ny, minNodes: 10)
    let mc = mask.filter { $0 }.count
    print("mask after components:", mc, "area mm2:", Double(mc) * h * h * mmpt * mmpt)
    var contourField = field
    for idx in 0..<field.count where !mask[idx] { contourField[idx] = 0 }
    if let loop = PrintBuild.marchingSquares(field: contourField, nx: nx, ny: ny,
                                             h: h, origin: Point2(minX, minY),
                                             iso: PrintBuild.isoLevel) {
        print("loop raw:", loop.count)
        let dp = PrintBuild.douglasPeucker(loop, epsilon: 1.1)
        print("loop after DP:", dp.count)
        let ch = PrintBuild.chaikin(dp, passes: 2)
        print("loop after chaikin:", ch.count)
        var pMinX = Double.greatestFiniteMagnitude, pMinY = pMinX
        var pMaxX = -pMinX, pMaxY = -pMinX
        for p in ch {
            pMinX = min(pMinX, p.x); pMaxX = max(pMaxX, p.x)
            pMinY = min(pMinY, p.y); pMaxY = max(pMaxY, p.y)
        }
        print("print mm: w", (pMaxX - pMinX) * mmpt, "h", (pMaxY - pMinY) * mmpt)
    } else {
        print("marchingSquares returned NIL")
    }
    let real = PrintBuild.build(samples: samples, kind: .foot, ageMonths: 3.5,
                                pureContact: false, mmPerPoint: mmpt)
    print("real build:", real == nil ? "nil" : "ok")
}
probe()
