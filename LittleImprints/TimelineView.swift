// TimelineView.swift — the growth timeline (spec §5): her prints
// in a row at TRUE relative scale, plus a then-vs-now overlay.
// Honesty rule: whenever the ribbon is scaled to fit, it says so —
// "Shown at 62% of real size" — and one tap of the slider restores
// the real thing.

import SwiftUI

struct GrowthTimelineView: View {
    @EnvironmentObject var store: LibraryStore
    @Binding var selectedTab: AppTab
    @State private var scalePct: Double = 0 // 0 = fit-to-view default, resolved on appear
    @State private var thenID: UUID? = nil
    @State private var nowID: UUID? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paperCream.ignoresSafeArea()
                if let child = store.activeChild {
                    let prints = store.prints(for: child.id).sorted { $0.createdAt < $1.createdAt }
                    if prints.count < 2 {
                        tooFew(child: child, count: prints.count)
                    } else {
                        content(child: child, prints: prints)
                    }
                } else {
                    Text("Add your baby in the Capture tab and the timeline begins.")
                        .font(.body).foregroundColor(.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(36)
                }
            }
            .navigationTitle("Growth Timeline")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func tooFew(child: ChildProfile, count: Int) -> some View {
        VStack(spacing: 12) {
            Text(count == 0 ? "No prints yet." : "One print so far.")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(.inkPlum)
            Text("The timeline needs two prints to show growth — the second one is where it starts to get you.")
                .font(.body).foregroundColor(.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            BigButton(title: "Make a print") { selectedTab = .capture }
                .padding(.horizontal, 40)
        }
    }

    private func content(child: ChildProfile, prints: [PrintRecord]) -> some View {
        let mmpt = ScreenMetrics.mmPerPoint
        let maxHeightPT = prints.map { $0.shape.heightMM / mmpt }.max() ?? 1
        let fitScale = min(1.0, 430.0 / maxHeightPT)
        let effScale = scalePct > 0 ? scalePct / 100 : fitScale
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Every print at the same scale — the growth is real, not arranged.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.inkSoft)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)

                // The ribbon.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 22) {
                        ForEach(prints) { record in
                            VStack(spacing: 6) {
                                PrintThumb(record: record)
                                    .frame(width: CGFloat(record.shape.widthMM / mmpt) * CGFloat(effScale),
                                           height: CGFloat(record.shape.heightMM / mmpt) * CGFloat(effScale))
                                Text(record.ageLabel)
                                    .font(.system(.caption, design: .rounded).weight(.semibold))
                                    .foregroundColor(.inkSoft)
                                Text(record.createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundColor(.inkFaint)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }

                // Scale honesty + control.
                VStack(alignment: .leading, spacing: 6) {
                    Text(effScale >= 0.995
                         ? "Shown at real size."
                         : "Shown at \(Int((effScale * 100).rounded()))% of real size.")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(.inkPlum)
                    Slider(value: Binding(
                        get: { scalePct > 0 ? scalePct : fitScale * 100 },
                        set: { scalePct = $0 }
                    ), in: 20...100, step: 1)
                    Text("Slide to 100% and hold the phone against her foot — it matches.")
                        .font(.footnote)
                        .foregroundColor(.inkFaint)
                }
                .padding(.horizontal, 18)

                Divider().padding(.horizontal, 18)

                thenVsNow(child: child, prints: prints, effScale: effScale, mmpt: mmpt)
            }
            .padding(.bottom, 26)
        }
    }

    private func thenVsNow(child: ChildProfile, prints: [PrintRecord],
                           effScale: Double, mmpt: Double) -> some View {
        let thenRec = prints.first(where: { $0.id == thenID }) ?? prints.first
        let nowRec = prints.first(where: { $0.id == nowID }) ?? prints.last
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Then vs now")
                .padding(.horizontal, 18)
            HStack(spacing: 12) {
                pickerMenu(label: "Then", prints: prints, selection: $thenID,
                           fallback: prints.first)
                pickerMenu(label: "Now", prints: prints, selection: $nowID,
                           fallback: prints.last)
            }
            .padding(.horizontal, 18)
            if let thenRec, let nowRec {
                ZStack(alignment: .bottom) {
                    PrintThumb(record: thenRec)
                        .frame(width: CGFloat(thenRec.shape.widthMM / mmpt) * CGFloat(effScale),
                               height: CGFloat(thenRec.shape.heightMM / mmpt) * CGFloat(effScale))
                    PrintThumb(record: nowRec)
                        .frame(width: CGFloat(nowRec.shape.widthMM / mmpt) * CGFloat(effScale),
                               height: CGFloat(nowRec.shape.heightMM / mmpt) * CGFloat(effScale))
                        .opacity(0.55)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.paperCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.lineSoft))
                .padding(.horizontal, 18)
                Text("\(thenRec.ageLabel) underneath, \(nowRec.ageLabel) on top — same scale, aligned at the heel.")
                    .font(.footnote)
                    .foregroundColor(.inkFaint)
                    .padding(.horizontal, 18)
            }
        }
    }

    private func pickerMenu(label: String, prints: [PrintRecord],
                            selection: Binding<UUID?>, fallback: PrintRecord?) -> some View {
        Menu {
            ForEach(prints) { record in
                Button("\(record.ageLabel) · \(record.kind.label)") {
                    selection.wrappedValue = record.id
                }
            }
        } label: {
            let current = prints.first(where: { $0.id == selection.wrappedValue }) ?? fallback
            HStack {
                Text(label).font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text(current.map { "\($0.ageLabel)" } ?? "—")
                    .font(.system(.subheadline, design: .rounded))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundColor(.inkPlum)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.paperCard)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.lineSoft))
        }
    }
}
