// Theme.swift — the keepsake look: warm paper, plum ink, quiet type.
// One parent's thumb runs everything: big targets, no precision taps.

import SwiftUI
import UIKit

extension Color {
    init(_ c: InkColor) { self.init(red: c.r, green: c.g, blue: c.b) }
    static let paperCream = Color(InkColor(hex: "#FAF3E3"))
    static let paperCard = Color(InkColor(hex: "#FFFDF6"))
    static let inkPlum = Color(InkColor(hex: "#5E2750"))
    static let inkSoft = Color(InkColor(hex: "#4A4038"))
    static let inkFaint = Color(InkColor(hex: "#8A7B6B"))
    static let lineSoft = Color(InkColor(hex: "#E5D9C3"))
}

extension InkColor {
    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(r: Double(r), g: Double(g), b: Double(b))
    }
    static var cream: InkColor { InkColor(hex: "#FAF3E3") }
    static var plum: InkColor { InkColor(hex: "#5E2750") }
}

/// The one big friendly button used at every decision point.
struct BigButton: View {
    let title: String
    var secondary: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(secondary ? Color.paperCard : Color.inkPlum)
                .foregroundColor(secondary ? .inkPlum : .white)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.lineSoft, lineWidth: secondary ? 1.5 : 0)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

/// A color swatch in the pickers.
struct SwatchView: View {
    let swatch: PaletteSwatch
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Circle()
                    .fill(Color(swatch.color))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle().stroke(selected ? Color.inkPlum : Color.lineSoft,
                                        lineWidth: selected ? 3 : 1)
                    )
                Text(swatch.name)
                    .font(.caption2)
                    .foregroundColor(.inkSoft)
                    .lineLimit(1)
            }
            .frame(width: 64)
        }
        .buttonStyle(.plain)
    }
}

/// Section heading in the app's one calm voice.
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(.headline, design: .rounded))
            .foregroundColor(.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
