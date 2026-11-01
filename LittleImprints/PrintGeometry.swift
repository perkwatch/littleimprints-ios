// PrintGeometry.swift — from touch contact to a print shape.
// Foundation only; exercised hard by tools/check-pure.swift.
//
// The method (spec §2.2):
//  1. A press arrives as contact samples (center + major radius over
//     time). Samples are clustered; far outliers (a parent's resting
//     palm) are dropped.
//  2. The samples are splatted into a pressure field — the rolling
//     union of contact ellipses, so a wiggle widens the print the way
//     a real press does.
//  3. The field is cleaned (close small gaps, cut 1-cell bridges),
//     then the print outline is extracted with marching squares and
//     smoothed (Douglas–Peucker + Chaikin) — no jagged pixel edges.
//  4. The shape prior may fill exactly ONE missing digit, only when
//     the palm and every other digit are unmistakably present, in
//     whichever orientation (left/right) matches better. Two or more
//     missing digits are never guessed. "Pure contact" disables this.
//  5. Scale is true: sizes come from the caller's mm-per-point, and
//     implausible sizes are rejected (the caller shows the kind
//     "that was just a tap" message instead of saving a dot).

import Foundation

public struct ContactSample: Codable, Equatable {
    public var x: Double
    public var y: Double
    /// UITouch major radius, points — grows with contact pressure.
    public var radius: Double
    /// Seconds since the first sample of the press.
    public var t: Double
    public init(x: Double, y: Double, radius: Double, t: Double) {
        self.x = x; self.y = y; self.radius = radius; self.t = t
    }
}

public struct PrintShape: Codable, Equatable {
    /// Smoothed outline in canvas space (points). Canvas space is the
    /// pressure field's bounding box; the outline sits inside it.
    public var outline: [Point2]
    /// Canvas size in points (field bounding box).
    public var canvasW: Double
    public var canvasH: Double
    /// The print's own size — outline bounding box, in points and mm.
    public var printW: Double
    public var printH: Double
    public var printOrigin: Point2 // outline bbox min, canvas space
    public var widthMM: Double
    public var heightMM: Double
    public var areaMM2: Double
    /// Pressure field, downsampled: row-major UInt8 0…255, base64.
    public var gridW: Int
    public var gridH: Int
    public var gridB64: String
    /// Enclosed voids (where skin texture broke contact), canvas-
    /// normalized 0…1 positions. The renderer punches them softly.
    public var voids: [Point2]
    /// Centroid drift during the press, points (the micro-smudge).
    public var motion: Point2
    /// True when the prior filled one missing digit.
    public var digitFilled: Bool
}

public enum PrintBuild {

    public static let isoLevel = 0.12
    public static let minAreaMM2 = 140.0

    public static func build(samples raw: [ContactSample],
                             kind: PrintKind,
                             ageMonths: Double,
                             pureContact: Bool,
                             mmPerPoint: Double) -> PrintShape? {
        guard raw.count >= 6, mmPerPoint > 0 else { return nil }
        let t0 = raw.map(\.t).min() ?? 0
        let t1 = raw.map(\.t).max() ?? 0
        let duration = t1 - t0

        // 1. Cluster: single-linkage over sample centers; keep the
        //    cluster carrying the most contact weight.
        let samples = largestCluster(raw)
        guard samples.count >= 5 else { return nil }
        if duration < 0.10 && samples.count < 12 { return nil } // a tap, not a press

        // 2. Pressure field over the cluster's bounding box.
        let h = 2.0 // lattice spacing, points
        var minX = Double.greatestFiniteMagnitude, minY = minX
        var maxX = -minX, maxY = -minX
        for s in samples {
            minX = min(minX, s.x - s.radius); maxX = max(maxX, s.x + s.radius)
            minY = min(minY, s.y - s.radius); maxY = max(maxY, s.y + s.radius)
        }
        minX -= 6; minY -= 6; maxX += 6; maxY += 6
        let nx = max(4, Int(((maxX - minX) / h).rounded()) + 1)
        let ny = max(4, Int(((maxY - minY) / h).rounded()) + 1)
        guard nx * ny <= 400_000 else { return nil }
        var field = [Double](repeating: 0, count: nx * ny)
        for s in samples {
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

        var mask = field.map { $0 >= isoLevel }
        // 3. Clean: close (dilate→erode) fills 1-cell gaps; open
        //    (erode→dilate) cuts 1-cell bridges.
        mask = erode(dilate(mask, nx, ny), nx, ny)
        mask = dilate(erode(mask, nx, ny), nx, ny)
        // Drop specks: keep components of ≥ 10 nodes.
        mask = keepComponents(mask, nx, ny, minNodes: 10)
        guard mask.contains(true) else { return nil }

        // 4. Prior: fill at most one clearly-missing digit.
        var digitFilled = false
        if !pureContact {
            digitFilled = tryFillMissingDigit(field: &field, mask: &mask,
                                              nx: nx, ny: ny, h: h,
                                              kind: kind, ageMonths: ageMonths)
            if digitFilled {
                mask = field.map { $0 >= isoLevel }
                mask = keepComponents(mask, nx, ny, minNodes: 10)
            }
        }

        // Area + plausibility, in real millimetres.
        let maskCount = mask.reduce(0) { $0 + ($1 ? 1 : 0) }
        let areaMM2 = Double(maskCount) * h * h * mmPerPoint * mmPerPoint
        guard areaMM2 >= minAreaMM2 else { return nil }

        // 5. Outline via marching squares on the cleaned field
        //    (recompute the field's mask alignment: marching squares
        //    reads the field itself; where morphology removed mask
        //    nodes, suppress the field so the contour follows).
        var contourField = field
        for idx in 0..<field.count where !mask[idx] { contourField[idx] = 0 }
        guard var loop = marchingSquares(field: contourField, nx: nx, ny: ny,
                                         h: h, origin: Point2(minX, minY),
                                         iso: isoLevel),
              loop.count >= 16 else { return nil }
        loop = douglasPeucker(loop, epsilon: 1.1)
        guard loop.count >= 10 else { return nil }
        loop = chaikin(loop, passes: 2)
        guard loop.count >= 12 else { return nil }

        // Print bbox in canvas space.
        var pMinX = Double.greatestFiniteMagnitude, pMinY = pMinX
        var pMaxX = -pMinX, pMaxY = -pMinX
        for p in loop {
            pMinX = min(pMinX, p.x); pMaxX = max(pMaxX, p.x)
            pMinY = min(pMinY, p.y); pMaxY = max(pMaxY, p.y)
        }
        let printW = pMaxX - pMinX, printH = pMaxY - pMinY
        let widthMM = printW * mmPerPoint, heightMM = printH * mmPerPoint
        switch kind {
        case .foot:
            guard heightMM >= 30, heightMM <= 230, widthMM >= 20 else { return nil }
        case .hand:
            guard heightMM >= 30, heightMM <= 260, widthMM >= 26 else { return nil }
        }

        // Voids: enclosed empty pockets inside the mask.
        let voids = enclosedVoids(mask, nx, ny, origin: Point2(minX, minY),
                                  canvasW: Double(nx - 1) * h, canvasH: Double(ny - 1) * h)

        // Motion: early vs late weighted centroid.
        let motion = centroidDrift(samples, t0: t0, t1: t1)

        // Pressure grid for the record (normalized, ≤112 per side).
        let (gw, gh, gb64) = downsampledGrid(field, nx, ny)

        return PrintShape(
            outline: loop,
            canvasW: Double(nx - 1) * h, canvasH: Double(ny - 1) * h,
            printW: printW, printH: printH,
            printOrigin: Point2(pMinX, pMinY),
            widthMM: widthMM, heightMM: heightMM, areaMM2: areaMM2,
            gridW: gw, gridH: gh, gridB64: gb64,
            voids: voids, motion: motion, digitFilled: digitFilled)
    }

    // MARK: - Clustering

    static func largestCluster(_ samples: [ContactSample]) -> [ContactSample] {
        let n = samples.count
        var parent = Array(0..<n)
        func find(_ a: Int) -> Int {
            var r = a
            while parent[r] != r { r = parent[r] }
            return r
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }
        for i in 0..<n {
            for j in (i + 1)..<n {
                let a = samples[i], b = samples[j]
                let d = ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
                if d < a.radius + b.radius + 12 { union(i, j) }
            }
        }
        var weight: [Int: Double] = [:]
        var members: [Int: [Int]] = [:]
        for i in 0..<n {
            let r = find(i)
            weight[r, default: 0] += samples[i].radius * samples[i].radius
            members[r, default: []].append(i)
        }
        guard let best = weight.max(by: { $0.value < $1.value })?.key,
              let idxs = members[best] else { return [] }
        return idxs.map { samples[$0] }
    }

    // MARK: - Morphology + components on the node lattice

    static func dilate(_ m: [Bool], _ nx: Int, _ ny: Int) -> [Bool] {
        var out = m
        for j in 0..<ny {
            for i in 0..<nx where m[j * nx + i] {
                for dj in -1...1 {
                    for di in -1...1 {
                        let ii = i + di, jj = j + dj
                        if ii >= 0, ii < nx, jj >= 0, jj < ny { out[jj * nx + ii] = true }
                    }
                }
            }
        }
        return out
    }

    static func erode(_ m: [Bool], _ nx: Int, _ ny: Int) -> [Bool] {
        var out = [Bool](repeating: false, count: nx * ny)
        for j in 0..<ny {
            for i in 0..<nx {
                var all = true
                for dj in -1...1 {
                    for di in -1...1 {
                        let ii = i + di, jj = j + dj
                        if ii < 0 || ii >= nx || jj < 0 || jj >= ny || !m[jj * nx + ii] {
                            all = false; break
                        }
                    }
                    if !all { break }
                }
                out[j * nx + i] = all
            }
        }
        return out
    }

    static func components(_ m: [Bool], _ nx: Int, _ ny: Int) -> [[Int]] {
        var seen = [Bool](repeating: false, count: nx * ny)
        var comps: [[Int]] = []
        for start in 0..<(nx * ny) where m[start] && !seen[start] {
            var stack = [start]
            seen[start] = true
            var comp: [Int] = []
            while let cur = stack.popLast() {
                comp.append(cur)
                let cx = cur % nx, cy = cur / nx
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let ix = cx + dx, iy = cy + dy
                    if ix >= 0, ix < nx, iy >= 0, iy < ny {
                        let nidx = iy * nx + ix
                        if m[nidx] && !seen[nidx] {
                            seen[nidx] = true
                            stack.append(nidx)
                        }
                    }
                }
            }
            comps.append(comp)
        }
        return comps
    }

    static func keepComponents(_ m: [Bool], _ nx: Int, _ ny: Int, minNodes: Int) -> [Bool] {
        var out = [Bool](repeating: false, count: nx * ny)
        for comp in components(m, nx, ny) where comp.count >= minNodes {
            for idx in comp { out[idx] = true }
        }
        return out
    }

    // MARK: - Prior digit fill

    /// Coverage of a prior ellipse by mask nodes. The prior is mapped
    /// into the MASK's bounding box (the measured contact patch),
    /// not the raw field box, so the ellipses land on the real toes.
    static func ellipseCoverage(mask: [Bool], nx: Int, ny: Int, h: Double,
                                frameOrigin: Point2, frameW: Double, frameH: Double,
                                spot: DigitSpot, mirrorX: Bool) -> Double {
        let cx = frameOrigin.x + (mirrorX ? 1 - spot.center.x : spot.center.x) * frameW
        let cy = frameOrigin.y + spot.center.y * frameH
        let rx = max(spot.radii.x * frameW, 1)
        let ry = max(spot.radii.y * frameH, 1)
        let ang = spot.angleDeg * Double.pi / 180 * (mirrorX ? -1 : 1)
        let cosA = cos(ang), sinA = sin(ang)
        var inside = 0, covered = 0
        let steps = 14
        for a in 0...steps {
            for b in 0...steps {
                let rr = Double(a) / Double(steps)
                let th = Double(b) / Double(steps) * 2 * Double.pi
                let lx = cos(th) * rr * rx, ly = sin(th) * rr * ry
                let px = cx + lx * cosA - ly * sinA
                let py = cy + lx * sinA + ly * cosA
                let ii = Int((px / h).rounded())
                let jj = Int((py / h).rounded())
                if ii >= 0, ii < nx, jj >= 0, jj < ny {
                    inside += 1
                    if mask[jj * nx + ii] { covered += 1 }
                }
            }
        }
        guard inside > 0 else { return 0 }
        return Double(covered) / Double(inside)
    }

    static func tryFillMissingDigit(field: inout [Double], mask: inout [Bool],
                                    nx: Int, ny: Int, h: Double,
                                    kind: PrintKind, ageMonths: Double) -> Bool {
        // Frame = the mask's own bounding box, in canvas points.
        var fMinI = nx, fMinJ = ny, fMaxI = -1, fMaxJ = -1
        for j in 0..<ny {
            for i in 0..<nx where mask[j * nx + i] {
                fMinI = min(fMinI, i); fMaxI = max(fMaxI, i)
                fMinJ = min(fMinJ, j); fMaxJ = max(fMaxJ, j)
            }
        }
        guard fMaxI >= 0 else { return false }
        let frameOrigin = Point2(Double(fMinI) * h, Double(fMinJ) * h)
        let frameW = Double(fMaxI - fMinI) * h
        let frameH = Double(fMaxJ - fMinJ) * h
        guard frameW > 10, frameH > 10 else { return false }

        let prior = shapePrior(kind: kind, ageMonths: ageMonths)
        // Try both orientations; use whichever matches at all.
        var best: (missing: Int, mirror: Bool)? = nil
        for mirror in [false, true] {
            let palmCov = ellipseCoverage(mask: mask, nx: nx, ny: ny, h: h,
                                          frameOrigin: frameOrigin, frameW: frameW, frameH: frameH,
                                          spot: prior.palm, mirrorX: mirror)
            guard palmCov >= 0.45 else { continue }
            var missing: [Int] = []
            for (idx, d) in prior.digits.enumerated() {
                let cov = ellipseCoverage(mask: mask, nx: nx, ny: ny, h: h,
                                          frameOrigin: frameOrigin, frameW: frameW, frameH: frameH,
                                          spot: d, mirrorX: mirror)
                if cov <= 0.15 { missing.append(idx) }
                else if cov < 0.40 { missing.append(-1) } // ambiguous — blocks any fill
            }
            if missing.count == 1, missing[0] >= 0 {
                best = (missing[0], mirror)
                break
            }
        }
        guard let fill = best else { return false }
        let spot = prior.digits[fill.missing]
        let cx = frameOrigin.x + (fill.mirror ? 1 - spot.center.x : spot.center.x) * frameW
        let cy = frameOrigin.y + spot.center.y * frameH
        let rx = max(spot.radii.x * frameW * 0.92, 2)
        let ry = max(spot.radii.y * frameH * 0.92, 2)
        let ang = spot.angleDeg * Double.pi / 180 * (fill.mirror ? -1 : 1)
        let cosA = cos(ang), sinA = sin(ang)
        let reach = rx + ry
        let i0 = max(0, Int(((cx - reach) / h).rounded(.down)))
        let i1 = min(nx - 1, Int(((cx + reach) / h).rounded(.up)))
        let j0 = max(0, Int(((cy - reach) / h).rounded(.down)))
        let j1 = min(ny - 1, Int(((cy + reach) / h).rounded(.up)))
        for j in j0...j1 {
            for i in i0...i1 {
                let px = Double(i) * h - cx, py = Double(j) * h - cy
                let lx = px * cosA + py * sinA, ly = -px * sinA + py * cosA
                let d2 = (lx * lx) / (rx * rx) + (ly * ly) / (ry * ry)
                if d2 < 1 {
                    let v = 0.8 * (1 - d2)
                    let idx = j * nx + i
                    if v > field[idx] { field[idx] = v }
                }
            }
        }
        return true
    }

    // MARK: - Voids + motion

    static func enclosedVoids(_ mask: [Bool], _ nx: Int, _ ny: Int,
                              origin: Point2, canvasW: Double, canvasH: Double) -> [Point2] {
        // Flood the empty region from the border; unvisited empty
        // nodes are enclosed pockets.
        var visited = [Bool](repeating: false, count: nx * ny)
        var stack: [Int] = []
        for i in 0..<nx {
            for idx in [i, (ny - 1) * nx + i] where !mask[idx] && !visited[idx] {
                visited[idx] = true; stack.append(idx)
            }
        }
        for j in 0..<ny {
            for idx in [j * nx, j * nx + (nx - 1)] where !mask[idx] && !visited[idx] {
                visited[idx] = true; stack.append(idx)
            }
        }
        while let cur = stack.popLast() {
            let cx = cur % nx, cy = cur / nx
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let ix = cx + dx, iy = cy + dy
                if ix >= 0, ix < nx, iy >= 0, iy < ny {
                    let nidx = iy * nx + ix
                    if !mask[nidx] && !visited[nidx] {
                        visited[nidx] = true
                        stack.append(nidx)
                    }
                }
            }
        }
        var pocket = [Bool](repeating: false, count: nx * ny)
        for idx in 0..<(nx * ny) where !mask[idx] && !visited[idx] { pocket[idx] = true }
        let comps = components(pocket, nx, ny)
            .filter { $0.count >= 2 && $0.count <= 60 }
            .sorted { $0.count > $1.count }
        var out: [Point2] = []
        for comp in comps.prefix(12) {
            var sx = 0.0, sy = 0.0
            for idx in comp { sx += Double(idx % nx); sy += Double(idx / nx) }
            let cx = sx / Double(comp.count), cy = sy / Double(comp.count)
            out.append(Point2(cx / Double(max(nx - 1, 1)), cy / Double(max(ny - 1, 1))))
        }
        _ = origin; _ = canvasW; _ = canvasH
        return out
    }

    static func centroidDrift(_ samples: [ContactSample], t0: Double, t1: Double) -> Point2 {
        let dur = max(t1 - t0, 0.0001)
        func centroid(_ lo: Double, _ hi: Double) -> Point2? {
            var w = 0.0, sx = 0.0, sy = 0.0
            for s in samples where s.t >= lo && s.t <= hi {
                let ww = s.radius * s.radius
                w += ww; sx += s.x * ww; sy += s.y * ww
            }
            guard w > 0 else { return nil }
            return Point2(sx / w, sy / w)
        }
        guard let a = centroid(t0, t0 + 0.3 * dur),
              let b = centroid(t1 - 0.3 * dur, t1) else { return .zero }
        return (b - a).clampedLength(max: 3)
    }

    // MARK: - Pressure grid for the record

    static func downsampledGrid(_ field: [Double], _ nx: Int, _ ny: Int) -> (Int, Int, String) {
        let maxSide = 112
        let gw = min(nx, maxSide), gh = min(ny, maxSide)
        let maxV = field.max() ?? 1
        let norm = maxV > 0 ? maxV : 1
        var bytes = [UInt8](repeating: 0, count: gw * gh)
        for j in 0..<gh {
            let srcJ = min(ny - 1, Int((Double(j) + 0.5) * Double(ny) / Double(gh)))
            for i in 0..<gw {
                let srcI = min(nx - 1, Int((Double(i) + 0.5) * Double(nx) / Double(gw)))
                let v = field[srcJ * nx + srcI] / norm
                bytes[j * gw + i] = UInt8(clampD(v, 0, 1) * 255)
            }
        }
        return (gw, gh, Data(bytes).base64EncodedString())
    }

    /// Inverse of downsampledGrid — the renderer reads the field back.
    public static func gridValues(_ shape: PrintShape) -> [Double] {
        guard let data = Data(base64Encoded: shape.gridB64),
              data.count == shape.gridW * shape.gridH else { return [] }
        return data.map { Double($0) / 255 }
    }

    // MARK: - Marching squares

    struct EdgeKey: Hashable {
        let horiz: Bool
        let i: Int
        let j: Int
    }

    static func marchingSquares(field: [Double], nx: Int, ny: Int, h: Double,
                                origin: Point2, iso: Double) -> [Point2]? {
        // Segment endpoints live on cell edges; identical edges
        // produce identical endpoints, which is how they chain.
        var segEnds: [(Point2, Point2)] = []

        func edgePoint(_ key: EdgeKey) -> Point2 {
            // Interpolate along the edge by the field values.
            if key.horiz {
                let a = field[key.j * nx + key.i]
                let b = field[key.j * nx + key.i + 1]
                let t = (b - a) != 0 ? (iso - a) / (b - a) : 0.5
                return Point2(origin.x + (Double(key.i) + clampD(t, 0, 1)) * h,
                              origin.y + Double(key.j) * h)
            } else {
                let a = field[key.j * nx + key.i]
                let b = field[(key.j + 1) * nx + key.i]
                let t = (b - a) != 0 ? (iso - a) / (b - a) : 0.5
                return Point2(origin.x + Double(key.i) * h,
                              origin.y + (Double(key.j) + clampD(t, 0, 1)) * h)
            }
        }

        func addSeg(_ e1: EdgeKey, _ e2: EdgeKey) {
            segEnds.append((edgePoint(e1), edgePoint(e2)))
        }

        for j in 0..<(ny - 1) {
            for i in 0..<(nx - 1) {
                let tl = field[j * nx + i], tr = field[j * nx + i + 1]
                let bl = field[(j + 1) * nx + i], br = field[(j + 1) * nx + i + 1]
                var caseIdx = 0
                if tl >= iso { caseIdx |= 8 }
                if tr >= iso { caseIdx |= 4 }
                if br >= iso { caseIdx |= 2 }
                if bl >= iso { caseIdx |= 1 }
                if caseIdx == 0 || caseIdx == 15 { continue }
                let top = EdgeKey(horiz: true, i: i, j: j)
                let right = EdgeKey(horiz: false, i: i + 1, j: j)
                let bottom = EdgeKey(horiz: true, i: i, j: j + 1)
                let left = EdgeKey(horiz: false, i: i, j: j)
                switch caseIdx {
                case 1, 14: addSeg(left, bottom)
                case 2, 13: addSeg(bottom, right)
                case 3, 12: addSeg(left, right)
                case 4, 11: addSeg(top, right)
                case 6, 9: addSeg(top, bottom)
                case 7, 8: addSeg(left, top)
                case 5:
                    let c = (tl + tr + bl + br) / 4
                    if c >= iso { addSeg(left, top); addSeg(bottom, right) }
                    else { addSeg(left, bottom); addSeg(top, right) }
                case 10:
                    let c = (tl + tr + bl + br) / 4
                    if c >= iso { addSeg(left, bottom); addSeg(top, right) }
                    else { addSeg(left, top); addSeg(bottom, right) }
                default: break
                }
            }
        }
        guard !segEnds.isEmpty else { return nil }

        // Chain segments into loops; keep the longest.
        var used = [Bool](repeating: false, count: segEnds.count)
        // Chain geometrically: two segments on the same cell edge
        // compute the identical interpolated endpoint.
        var pointToSegs: [String: [Int]] = [:]
        func key(_ p: Point2) -> String {
            "\(Int((p.x * 1000).rounded()))|\(Int((p.y * 1000).rounded()))"
        }
        for (idx, seg) in segEnds.enumerated() {
            pointToSegs[key(seg.0), default: []].append(idx)
            pointToSegs[key(seg.1), default: []].append(idx)
        }
        var bestLoop: [Point2] = []
        for start in 0..<segEnds.count where !used[start] {
            var loopPts: [Point2] = []
            var cur = start
            var curPoint = segEnds[start].0
            loopPts.append(segEnds[start].0)
            loopPts.append(segEnds[start].1)
            used[start] = true
            curPoint = segEnds[start].1
            var guardN = 0
            while guardN < segEnds.count + 2 {
                guardN += 1
                let candidates = pointToSegs[key(curPoint)] ?? []
                guard let next = candidates.first(where: { !used[$0] }) else { break }
                used[next] = true
                let seg = segEnds[next]
                let other = key(seg.0) == key(curPoint) ? seg.1 : seg.0
                loopPts.append(other)
                curPoint = other
                cur = next
                _ = cur
                if key(curPoint) == key(loopPts[0]) { break }
            }
            if loopPts.count > bestLoop.count { bestLoop = loopPts }
        }
        guard bestLoop.count >= 4 else { return nil }
        // Drop the duplicated closing point.
        if bestLoop.count > 1, key(bestLoop.first!) == key(bestLoop.last!) {
            bestLoop.removeLast()
        }
        // Convert from field coordinates to canvas coordinates.
        return bestLoop.map { Point2($0.x - origin.x, $0.y - origin.y) }
    }

    // MARK: - Polyline cleanup

    static func douglasPeucker(_ pts: [Point2], epsilon: Double) -> [Point2] {
        guard pts.count > 2 else { return pts }
        // Closed loop: anchor at the point farthest from centroid,
        // split the loop there, run the open-polyline algorithm.
        var cx = 0.0, cy = 0.0
        for p in pts { cx += p.x; cy += p.y }
        let c = Point2(cx / Double(pts.count), cy / Double(pts.count))
        var anchor = 0, bestD = -1.0
        for (i, p) in pts.enumerated() {
            let d = p.distance(to: c)
            if d > bestD { bestD = d; anchor = i }
        }
        var open = Array(pts[anchor...]) + Array(pts[..<anchor])
        open.append(open[0])
        var keep = [Bool](repeating: false, count: open.count)
        keep[0] = true; keep[open.count - 1] = true
        var stack: [(Int, Int)] = [(0, open.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            let pa = open[a], pb = open[b]
            let ab = pb - pa
            let len = max(ab.length, 0.0001)
            var maxD = 0.0, maxI = -1
            for i in (a + 1)..<b {
                let ap = open[i] - pa
                let cross = abs(ab.x * ap.y - ab.y * ap.x) / len
                if cross > maxD { maxD = cross; maxI = i }
            }
            if maxD > epsilon, maxI > 0 {
                keep[maxI] = true
                stack.append((a, maxI))
                stack.append((maxI, b))
            }
        }
        var out = open.enumerated().filter { keep[$0.offset] }.map(\.element)
        if out.count > 1, out.first == out.last { out.removeLast() }
        return out
    }

    static func chaikin(_ pts: [Point2], passes: Int) -> [Point2] {
        var cur = pts
        for _ in 0..<passes {
            guard cur.count >= 3 else { break }
            var out: [Point2] = []
            out.reserveCapacity(cur.count * 2)
            for i in 0..<cur.count {
                let a = cur[i], b = cur[(i + 1) % cur.count]
                out.append(a * 0.75 + b * 0.25)
                out.append(a * 0.25 + b * 0.75)
            }
            cur = out
        }
        return cur
    }
}