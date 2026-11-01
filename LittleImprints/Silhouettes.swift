// Silhouettes.swift — age-scaled hand/foot shape priors. Foundation only.
//
// The prior is a seatbelt, not a stencil (spec §2.2): it describes where
// a baby's toes/fingers usually sit relative to the palm/sole, at a few
// ages, so the capture engine can gently regularize an implausible
// outline — e.g. fill ONE missing toe when the rest of the toe arc is
// clearly detected. It never replaces the baby's real outline, and the
// "Pure contact" setting turns it off entirely.
//
// All coordinates are unit space: x right, y DOWN, digits at the top.

import Foundation

public struct DigitSpot {
    /// Center in unit space.
    public let center: Point2
    /// Radii (x, y) in unit space.
    public let radii: Point2
    /// Rotation of the digit ellipse, degrees (0 = upright).
    public let angleDeg: Double
    public init(center: Point2, radii: Point2, angleDeg: Double = 0) {
        self.center = center; self.radii = radii; self.angleDeg = angleDeg
    }
}

public struct ShapePrior {
    /// The palm/sole body ellipse.
    public let palm: DigitSpot
    /// Digit ellipses in arc order (for a foot: big toe → pinky;
    /// for a hand: thumb → pinky).
    public let digits: [DigitSpot]
    /// A plausible full outline in unit space (used for the Nightstand
    /// Walk's gentle placeholder prints before the first real capture,
    /// and by the pure harness to synthesize test presses).
    public let outline: [Point2]
}

private func footPrior(digitScale: Double, palmScale: Double) -> ShapePrior {
    func d(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> DigitSpot {
        DigitSpot(center: Point2(x, y), radii: Point2(rx * digitScale, ry * digitScale))
    }
    return ShapePrior(
        palm: DigitSpot(center: Point2(0.50, 0.56),
                        radii: Point2(0.27 * palmScale, 0.44 * palmScale)),
        digits: [
            d(0.245, 0.085, 0.085, 0.075), // big toe
            d(0.400, 0.100, 0.055, 0.060),
            d(0.525, 0.115, 0.050, 0.055),
            d(0.635, 0.135, 0.045, 0.050),
            d(0.730, 0.165, 0.040, 0.045), // pinky toe
        ],
        outline: [
            Point2(0.30, 0.03), Point2(0.20, 0.06), Point2(0.17, 0.13),
            Point2(0.30, 0.16), Point2(0.36, 0.05), Point2(0.44, 0.16),
            Point2(0.50, 0.07), Point2(0.57, 0.17), Point2(0.62, 0.10),
            Point2(0.68, 0.19), Point2(0.72, 0.14), Point2(0.78, 0.20),
            Point2(0.76, 0.30), Point2(0.74, 0.55), Point2(0.72, 0.80),
            Point2(0.66, 0.94), Point2(0.52, 0.99), Point2(0.36, 0.97),
            Point2(0.31, 0.85), Point2(0.34, 0.62), Point2(0.30, 0.45),
            Point2(0.24, 0.32), Point2(0.20, 0.22),
        ])
}

private func handPrior(digitScale: Double, palmScale: Double) -> ShapePrior {
    func d(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ a: Double = 0) -> DigitSpot {
        DigitSpot(center: Point2(x, y), radii: Point2(rx * digitScale, ry * digitScale), angleDeg: a)
    }
    return ShapePrior(
        palm: DigitSpot(center: Point2(0.53, 0.63),
                        radii: Point2(0.28 * palmScale, 0.34 * palmScale)),
        digits: [
            d(0.145, 0.400, 0.075, 0.110, -35), // thumb
            d(0.345, 0.175, 0.050, 0.115),      // index
            d(0.485, 0.135, 0.052, 0.135),      // middle
            d(0.615, 0.160, 0.050, 0.120),      // ring
            d(0.735, 0.225, 0.042, 0.090),      // pinky
        ],
        outline: [
            Point2(0.36, 0.99), Point2(0.30, 0.80), Point2(0.26, 0.62),
            Point2(0.20, 0.50), Point2(0.10, 0.44), Point2(0.08, 0.36),
            Point2(0.16, 0.30), Point2(0.26, 0.38), Point2(0.29, 0.20),
            Point2(0.31, 0.08), Point2(0.38, 0.09), Point2(0.41, 0.22),
            Point2(0.44, 0.10), Point2(0.47, 0.02), Point2(0.53, 0.03),
            Point2(0.56, 0.20), Point2(0.59, 0.11), Point2(0.62, 0.05),
            Point2(0.68, 0.08), Point2(0.70, 0.24), Point2(0.73, 0.16),
            Point2(0.76, 0.11), Point2(0.81, 0.15), Point2(0.80, 0.34),
            Point2(0.78, 0.60), Point2(0.74, 0.82), Point2(0.68, 0.99),
        ])
}

/// Age bands: (months, digitScale, palmScale). Newborn digits are
/// relatively chunkier; the palm/sole slims relative to length with age.
private let bands: [(months: Double, digit: Double, palm: Double)] = [
    (0, 1.18, 0.94), (3, 1.12, 0.96), (6, 1.04, 0.99),
    (12, 0.97, 1.02), (24, 0.90, 1.05),
]

public func shapePrior(kind: PrintKind, ageMonths: Double) -> ShapePrior {
    let m = clampD(ageMonths, 0, 24)
    var digit = bands.last!.digit
    var palm = bands.last!.palm
    if m <= bands.first!.months {
        digit = bands.first!.digit; palm = bands.first!.palm
    } else {
        for i in 1..<bands.count {
            if m <= bands[i].months {
                let t = (m - bands[i - 1].months) / (bands[i].months - bands[i - 1].months)
                digit = lerpD(bands[i - 1].digit, bands[i].digit, t)
                palm = lerpD(bands[i - 1].palm, bands[i].palm, t)
                break
            }
        }
    }
    switch kind {
    case .foot: return footPrior(digitScale: digit, palmScale: palm)
    case .hand: return handPrior(digitScale: digit, palmScale: palm)
    }
}

/// Typical real-world sizes, used ONLY as generous plausibility bounds
/// (a press wildly outside these is a stray contact, not a print) and
/// never to size a real print — real prints are measured, not assumed.
public func typicalFootLengthMM(ageMonths: Double) -> Double {
    let anchors: [(Double, Double)] = [(0, 79), (3, 95), (6, 106), (12, 121), (18, 134), (24, 146)]
    return anchorLerp(anchors, clampD(ageMonths, 0, 24))
}

public func typicalHandWidthMM(ageMonths: Double) -> Double {
    let anchors: [(Double, Double)] = [(0, 52), (3, 60), (6, 66), (12, 76), (18, 83), (24, 90)]
    return anchorLerp(anchors, clampD(ageMonths, 0, 24))
}

private func anchorLerp(_ anchors: [(Double, Double)], _ m: Double) -> Double {
    if m <= anchors.first!.0 { return anchors.first!.1 }
    for i in 1..<anchors.count {
        if m <= anchors[i].0 {
            let t = (m - anchors[i - 1].0) / (anchors[i].0 - anchors[i - 1].0)
            return lerpD(anchors[i - 1].1, anchors[i].1, t)
        }
    }
    return anchors.last!.1
}
