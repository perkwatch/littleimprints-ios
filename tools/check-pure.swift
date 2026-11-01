// check-pure.swift — the pure-logic laws of Little Imprints, pinned.
// Compiled and run WITHOUT the app target (Foundation only):
//   swiftc -O LittleImprints/{Geo,RNG,InkColor,AgeCalc,Silhouettes,PrintGeometry}.swift tools/check-pure.swift -o /tmp/check-pure && /tmp/check-pure
// Runs locally and as a CI step. Every failure prints and exits 1.

import Foundation
#if os(Linux)
import Glibc
#endif

var failures = 0
var passes = 0
func check(_ cond: Bool, _ name: String) {
    if cond { passes += 1; print("PASS  \(name)") }
    else { failures += 1; print("FAIL  \(name)") }
}
func checkClose(_ a: Double, _ b: Double, _ tol: Double, _ name: String) {
    check(abs(a - b) <= tol, "\(name) (got \(a), want \(b) ±\(tol))")
}

// MARK: - InkColor

check(InkColor(hex: "#26355D").hexString == "#26355D", "hex round-trips")
check(InkColor(hex: "FAF3E3").hexString == "#FAF3E3", "hex without # parses")
check(InkColor(hex: "#FFFFFF").darkened(by: 0.2).hexString == "#CCCCCC", "darkened white")
check(InkColor(hex: "#000000").lightened(by: 0.5).hexString == "#808080", "lightened black")

// MARK: - RNG

var r1 = SplitMix64(seed: 42), r2 = SplitMix64(seed: 42)
var same = true
for _ in 0..<100 { if r1.next() != r2.next() { same = false } }
check(same, "SplitMix64 is deterministic per seed")
var r3 = SplitMix64(seed: 7)
var jitterOK = true
for _ in 0..<1000 { let j = r3.nextJitter(); if j < -1.0001 || j > 1.0001 { jitterOK = false } }
check(jitterOK, "jitter stays in [-1, 1]")

// MARK: - Age (pinned Gregorian/UTC so the law is exact anywhere)

var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(identifier: "UTC")!
func d(_ y: Int, _ mo: Int, _ da: Int) -> Date {
    var dc = DateComponents(); dc.year = y; dc.month = mo; dc.day = da; dc.hour = 12
    return utc.date(from: dc)!
}

let birth = d(2026, 7, 19)
let at = d(2026, 11, 1)
let p = ageParts(birth: birth, at: at, calendar: utc)
check(p.years == 0 && p.months == 3 && p.days == 13, "age parts 3m 13d (got \(p))")
check(ageText(birth: birth, at: at, calendar: utc) == "3 months, 13 days", "age text plural")
check(ageText(birth: at, at: at, calendar: utc) == "Today", "birth day reads Today")
check(ageText(birth: d(2026, 10, 31), at: at, calendar: utc) == "1 day", "one day singular")
check(ageText(birth: d(2026, 10, 18), at: at, calendar: utc) == "2 weeks", "two weeks exact")
check(ageText(birth: d(2026, 10, 20), at: at, calendar: utc) == "1 week, 5 days", "week + days singular week")
check(ageText(birth: d(2026, 9, 24), at: at, calendar: utc) == "1 month, 8 days", "one month singular")
check(ageText(birth: d(2025, 11, 1), at: at, calendar: utc) == "1 year", "one year singular")
check(ageText(birth: d(2025, 8, 14), at: at, calendar: utc) == "1 year, 2 months", "year + months")
checkClose(ageInMonths(birth: birth, at: at, calendar: utc), 3.43, 0.05, "age in months")

let caps = captionSuggestions(name: "Gracelynn", birth: birth, at: at, calendar: utc)
check(caps.first == "Gracelynn — 3 months, 13 days", "caption leads with name + age (got \(caps.first ?? "none"))")
check(caps.count >= 2, "captions offer the date form too")

let miles = allMilestones(birth: birth, calendar: utc)
check(miles.contains { $0.id == "first-christmas" && $0.date == d(2026, 12, 25) },
      "first Christmas lands on 2026-12-25")
check(miles.contains { $0.id == "first-thanksgiving" && $0.date == d(2026, 11, 26) },
      "first Thanksgiving lands on 2026-11-26")
check(milestoneNear(birth: birth, at: d(2026, 10, 19), calendar: utc)?.id == "month-3",
      "three-month milestone is near on its day")
check(nextMilestone(birth: birth, at: at, calendar: utc)?.id == "month-4",
      "next milestone after Nov 1 is four months")

// MARK: - Geometry helpers

let square = [Point2(0, 0), Point2(1, 0), Point2(1, 1), Point2(0, 1)]
checkClose(polygonArea(square), 1, 0.0001, "unit square area")
check(pointInPolygon(Point2(0.5, 0.5), square), "center is inside the square")
check(!pointInPolygon(Point2(1.5, 0.5), square), "outside point is outside")

// MARK: - Synthetic presses

/// Simulates a press of the prior silhouette: samples on a jittered
/// grid inside the true outline, radii like real contact blobs, with
/// a gentle wiggle drift — and optionally one digit's contact missing.
func synthPress(kind: PrintKind, ageMonths: Double, mmPerPoint: Double,
                missingDigit: Int?, seed: UInt64) -> [ContactSample] {
    let prior = shapePrior(kind: kind, ageMonths: ageMonths)
    let lengthMM = kind == .foot ? typicalFootLengthMM(ageMonths: ageMonths)
                                 : typicalHandWidthMM(ageMonths: ageMonths) * 1.9
    let lengthPT = lengthMM / mmPerPoint
    var rng = SplitMix64(seed: seed)
    var samples: [ContactSample] = []
    let spacing = 9.0
    var gx = 4.0
    while gx < lengthPT {
        var gy = 4.0
        while gy < lengthPT {
            let u = gx / lengthPT, v = gy / lengthPT
            let p = Point2(u, v)
            if pointInPolygon(p, prior.outline) {
                var excluded = false
                if let md = missingDigit {
                    let spot = prior.digits[md]
                    let dx = (u - spot.center.x) / spot.radii.x
                    let dy = (v - spot.center.y) / spot.radii.y
                    if dx * dx + dy * dy < 0.95 { excluded = true }
                }
                if !excluded {
                    let t = rng.nextDouble() * 0.8
                    samples.append(ContactSample(
                        x: gx + rng.nextJitter() * 1.5 + t * 2.0,
                        y: gy + rng.nextJitter() * 1.5 + t * 0.8,
                        radius: 11 + rng.nextJitter() * 2.5,
                        t: t))
                }
            }
            gy += spacing
        }
        gx += spacing
    }
    return samples
}

let mmpt = 0.1657 // ≈ 460 ppi at 3x

let fullFoot = synthPress(kind: .foot, ageMonths: 3.5, mmPerPoint: mmpt, missingDigit: nil, seed: 11)
if let shape = PrintBuild.build(samples: fullFoot, kind: .foot, ageMonths: 3.5,
                                pureContact: false, mmPerPoint: mmpt) {
    check(true, "full foot press builds a print")
    checkClose(shape.heightMM, 94, 22, "foot length is true-ish")
    checkClose(shape.widthMM, 57, 18, "foot width is true-ish")
    check(!shape.digitFilled, "complete press needs no prior fill")
    check(shape.outline.count >= 24, "outline is a smooth loop, not a blob (n=\(shape.outline.count))")
    let vals = PrintBuild.gridValues(shape)
    check(vals.count == shape.gridW * shape.gridH, "pressure grid round-trips")
    check((vals.max() ?? 0) > 0.95, "pressure peaks at full contact")
    check(shape.areaMM2 > 1500, "foot area is plausible (got \(Int(shape.areaMM2)) mm²)")
} else {
    check(false, "full foot press builds a print")
}

let noPinky = synthPress(kind: .foot, ageMonths: 3.5, mmPerPoint: mmpt, missingDigit: 4, seed: 12)
if let shape = PrintBuild.build(samples: noPinky, kind: .foot, ageMonths: 3.5,
                                pureContact: false, mmPerPoint: mmpt) {
    check(shape.digitFilled, "missing pinky toe is filled by the prior")
} else {
    check(false, "missing-pinky press still builds")
}
if let shape = PrintBuild.build(samples: noPinky, kind: .foot, ageMonths: 3.5,
                                pureContact: true, mmPerPoint: mmpt) {
    check(!shape.digitFilled, "pure contact never fills")
} else {
    check(false, "missing-pinky press builds under pure contact too")
}

let noBigToe = synthPress(kind: .foot, ageMonths: 3.5, mmPerPoint: mmpt, missingDigit: 0, seed: 13)
if let shape = PrintBuild.build(samples: noBigToe, kind: .foot, ageMonths: 3.5,
                                pureContact: false, mmPerPoint: mmpt) {
    check(shape.digitFilled, "missing big toe is filled by the prior")
} else {
    check(false, "missing-big-toe press still builds")
}

let twoMissing = synthPress(kind: .foot, ageMonths: 3.5, mmPerPoint: mmpt, missingDigit: 4, seed: 14)
var twoMissingSamples = twoMissing
// Knock out the second toe as well: drop samples in its neighborhood
// (unit-space test via the prior at the same scale).
do {
    let prior = shapePrior(kind: .foot, ageMonths: 3.5)
    let lengthMM = typicalFootLengthMM(ageMonths: 3.5)
    let lengthPT = lengthMM / mmpt
    let spot = prior.digits[3]
    twoMissingSamples = twoMissing.filter { s in
        let u = s.x / lengthPT, v = s.y / lengthPT
        let dx = (u - spot.center.x) / spot.radii.x
        let dy = (v - spot.center.y) / spot.radii.y
        return dx * dx + dy * dy >= 0.95
    }
}
if let shape = PrintBuild.build(samples: twoMissingSamples, kind: .foot, ageMonths: 3.5,
                                pureContact: false, mmPerPoint: mmpt) {
    check(!shape.digitFilled, "two missing toes are never guessed")
} else {
    check(false, "two-missing-toes press still builds")
}

let tap = (0..<4).map { i in
    ContactSample(x: 100 + Double(i), y: 100, radius: 6, t: Double(i) * 0.01)
}
check(PrintBuild.build(samples: tap, kind: .foot, ageMonths: 3.5,
                       pureContact: false, mmPerPoint: mmpt) == nil,
      "a stray tap builds nothing")

let fullHand = synthPress(kind: .hand, ageMonths: 6, mmPerPoint: mmpt, missingDigit: nil, seed: 15)
if let shape = PrintBuild.build(samples: fullHand, kind: .hand, ageMonths: 6,
                                pureContact: false, mmPerPoint: mmpt) {
    check(true, "full hand press builds a print")
    check(shape.heightMM > 70 && shape.heightMM < 190,
          "hand length plausible (got \(Int(shape.heightMM)) mm)")
} else {
    check(false, "full hand press builds a print")
}

// MARK: - Verdict

print("—")
print("\(passes) passed, \(failures) failed")
if failures > 0 { exit(1) }
