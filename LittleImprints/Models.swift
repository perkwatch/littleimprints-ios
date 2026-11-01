// Models.swift — the keepsake library's records. Plain Codable
// structs; everything lives in one on-device JSON library plus PNG
// files (spec §5, §8). No server shape, no account shape — by design.

import Foundation

public struct ChildProfile: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var birthDate: Date
    public init(id: UUID = UUID(), name: String, birthDate: Date) {
        self.id = id; self.name = name; self.birthDate = birthDate
    }
    public func ageText(at date: Date) -> String {
        ageText(birth: birthDate, at: date)
    }
}

/// One kept print. The vector truth (outline + pressure grid) is
/// stored, so the print can be re-rendered at any size, forever,
/// in its original color — the baked PNGs are caches, not the record.
public struct PrintRecord: Codable, Identifiable, Equatable {
    public var id: UUID
    public var childID: UUID
    public var kind: PrintKind
    public var material: PrintMaterial
    public var color: InkColor
    public var createdAt: Date
    /// The baby's age when the print was made, frozen as text so the
    /// keepsake reads the same even if a birthdate is later corrected.
    public var ageLabel: String
    public var shape: PrintShape
    /// Adjustments the parent made before keeping (spec §2.1 step 5).
    public var rotationDeg: Double
    /// Nudge offset in points, applied at render time.
    public var offset: Point2 = Point2(0, 0)
    public var note: String
    /// Deterministic render seed (grain/voids are part of the print).
    public var seed: UInt64
    public init(id: UUID = UUID(), childID: UUID, kind: PrintKind,
                material: PrintMaterial, color: InkColor, createdAt: Date,
                ageLabel: String, shape: PrintShape, rotationDeg: Double = 0,
                note: String = "", seed: UInt64) {
        self.id = id; self.childID = childID; self.kind = kind
        self.material = material; self.color = color
        self.createdAt = createdAt; self.ageLabel = ageLabel
        self.shape = shape; self.rotationDeg = rotationDeg
        self.note = note; self.seed = seed
    }
    public var sizeText: String {
        let w = shape.widthMM / 25.4, h = shape.heightMM / 25.4
        return String(format: "%.1f × %.1f mm  ·  %.2f × %.2f in",
                      shape.widthMM, shape.heightMM, w, h)
    }
}

/// One decoration layer on a page (spec §4). Non-destructive: the
/// prints underneath are never altered.
public struct DecorationLayer: Codable, Identifiable, Equatable {
    public enum LayerKind: String, Codable {
        case stamp      // a drawn stamp/sticker, `symbol` names it
        case text       // name/caption line, `text` holds it
        case dateStamp  // postal-style date stamp, `text` = date line
        case frame      // page frame, `symbol` names the style
        case butterfly  // the footprint-butterfly template group
    }
    public var id: UUID
    public var kind: LayerKind
    public var symbol: String
    public var text: String
    public var color: InkColor
    /// Center in page-normalized coordinates (0…1).
    public var center: Point2
    /// Layer size as a fraction of page width.
    public var scale: Double
    public var rotationDeg: Double
    public init(id: UUID = UUID(), kind: LayerKind, symbol: String = "",
                text: String = "", color: InkColor,
                center: Point2, scale: Double, rotationDeg: Double = 0) {
        self.id = id; self.kind = kind; self.symbol = symbol
        self.text = text; self.color = color; self.center = center
        self.scale = scale; self.rotationDeg = rotationDeg
    }
}

/// A print placed on a page.
public struct PlacedPrint: Codable, Identifiable, Equatable {
    public var id: UUID
    public var printID: UUID
    public var center: Point2 // page-normalized
    /// Print width as a fraction of page width.
    public var scale: Double
    public var rotationDeg: Double
    public init(id: UUID = UUID(), printID: UUID, center: Point2,
                scale: Double, rotationDeg: Double = 0) {
        self.id = id; self.printID = printID; self.center = center
        self.scale = scale; self.rotationDeg = rotationDeg
    }
}

/// A composed keepsake page (spec §2.2 multi-print pages, §5).
public struct PageRecord: Codable, Identifiable, Equatable {
    public var id: UUID
    public var childID: UUID
    public var createdAt: Date
    public var title: String
    public var paper: InkColor
    public var prints: [PlacedPrint]
    public var decorations: [DecorationLayer]
    public init(id: UUID = UUID(), childID: UUID, createdAt: Date,
                title: String = "", paper: InkColor,
                prints: [PlacedPrint] = [], decorations: [DecorationLayer] = []) {
        self.id = id; self.childID = childID; self.createdAt = createdAt
        self.title = title; self.paper = paper
        self.prints = prints; self.decorations = decorations
    }
}

public struct AppSettings: Codable, Equatable {
    /// "Pure contact — no touch-ups": the shape prior never fills.
    public var pureContact: Bool = false
    /// The soft stamp sound on lift-off.
    public var soundOn: Bool = true
    /// Exclude the library from the device's iCloud backup (spec §8:
    /// the choice is the family's, stated plainly, off by default).
    public var excludeFromBackup: Bool = false
    /// Milestone prompts the family has dismissed — forever (spec §5).
    public var dismissedMilestones: [String] = []
    /// Recently used ink colors, most recent first (spec §3).
    public var recentColorHexes: [String] = []
    public init() {}
}

public struct LibraryFile: Codable {
    public var children: [ChildProfile] = []
    public var prints: [PrintRecord] = []
    public var pages: [PageRecord] = []
    public var settings: AppSettings = AppSettings()
    public var activeChildID: UUID? = nil
    public init() {}
}
