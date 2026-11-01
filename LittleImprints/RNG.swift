// RNG.swift — deterministic seeded randomness (SplitMix64).
// Foundation only. Print rendering is seeded per print so a keepsake
// re-renders identically forever: the grain and voids in her print are
// part of the keepsake, not a dice roll on every open.

import Foundation

public struct SplitMix64: RandomNumberGenerator {
    public private(set) var state: UInt64
    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    public mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// Uniform in [lo, hi).
    public mutating func nextDouble(_ lo: Double, _ hi: Double) -> Double {
        lo + nextDouble() * (hi - lo)
    }

    /// Roughly normal in [-1, 1] (sum of uniforms) for organic jitter.
    public mutating func nextJitter() -> Double {
        (nextDouble() + nextDouble() + nextDouble()) / 1.5 - 1.0
    }
}
