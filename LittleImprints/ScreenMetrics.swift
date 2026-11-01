// ScreenMetrics.swift — true-scale calibration (spec §2.2, §5, §6).
//
// A print is only "her real size" if points map to millimetres
// honestly. iOS doesn't expose physical screen size, so we key off
// the native pixel resolution — the stable fingerprint of each
// device panel — and fall back to the modern-iPhone standard.
// Sizes are stored in mm at capture time, so a keepsake stays true
// even when the family changes phones later.

import UIKit

public enum ScreenMetrics {

    /// Panel pixel densities (pixels per inch) by native resolution.
    private static let ppiTable: [String: Double] = [
        "750x1334": 326, "1080x1920": 401, "1242x2208": 401,
        "1125x2436": 458, "1242x2688": 458, "1284x2778": 458,
        "1170x2532": 460, "1179x2556": 460, "1206x2622": 460,
        "1290x2796": 460, "1320x2868": 460,
        "1536x2048": 264, "1620x2160": 264, "1640x2360": 264,
        "1668x2388": 264, "2048x2732": 264, "1488x2266": 264,
    ]

    public static var pixelsPerInch: Double {
        let b = UIScreen.main.nativeBounds
        let key = "\(Int(b.width))x\(Int(b.height))"
        let flipped = "\(Int(b.height))x\(Int(b.width))"
        if let ppi = ppiTable[key] ?? ppiTable[flipped] { return ppi }
        return UIDevice.current.userInterfaceIdiom == .pad ? 264 : 460
    }

    /// Millimetres per UIKit point on this device:
    /// 25.4 ÷ (pixels-per-inch ÷ pixels-per-point).
    public static var mmPerPoint: Double {
        25.4 * Double(UIScreen.main.scale) / pixelsPerInch
    }

    /// The device's exact wallpaper size in pixels (spec §6).
    public static var wallpaperPixelSize: CGSize {
        UIScreen.main.nativeBounds.size
    }
}
