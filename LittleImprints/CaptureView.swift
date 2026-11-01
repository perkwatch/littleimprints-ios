// CaptureView.swift — the whole making of a print (spec §2):
// pick hand/foot + color + material → the pad → the press →
// keep / try again / adjust → the book. One thumb throughout.

import SwiftUI

struct CaptureView: View {
    @EnvironmentObject var store: LibraryStore
    @Binding var selectedTab: AppTab

    private enum Phase { case setup, pad, preview, tooSmall, saved }
    @State private var phase: Phase = .setup

    @State private var kind: PrintKind = .foot
    @State private var material: PrintMaterial = .ink
    @State private var selectedColor: InkColor = InkPalette.classics[0].color
    @State private var customColor: Color = Color(InkPalette.classics[0].color)

    @State private var newName: String = ""
    @State private var newBirth: Date = Date()

    @State private var sampleCount: Int = 0
    @State private var padPulse: Bool = false
    @StateObject private var padControl = PadControl()

    @State private var draft: PrintRecord? = nil
    @State private var previewImage: UIImage? = nil
    @State private var rotDeg: Double = 0
    @State private var nudgeX: Double = 0
    @State private var nudgeY: Double = 0
    @State private var settle: Bool = false
    @State private var kindThumbs: [PrintKind: UIImage] = [:]

    var body: some View {
        ZStack {
            Color.paperCream.ignoresSafeArea()
            switch phase {
            case .setup: setupView
            case .pad: padView
            case .preview: previewView
            case .tooSmall: tooSmallView
            case .saved: savedView
            }
        }
        .onAppear { makeKindThumbs() }
    }

    // MARK: - Setup

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let child = store.activeChild {
                    headerFor(child)
                    kindPicker
                    colorPickerSection
                    materialPicker
                    BigButton(title: "Ready — press gently") {
                        phase = .pad
                    }
                    Text("The screen becomes the ink pad. Hold the phone steady, press, lift — that's all.")
                        .font(.footnote)
                        .foregroundColor(.inkFaint)
                } else {
                    welcomeSetup
                }
            }
            .padding(20)
        }
    }

    private var welcomeSetup: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Little Imprints")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundColor(.inkPlum)
            Text("Your phone is the ink pad. Press your baby's hand or foot to the screen, and keep the print — true size, in ink or paint — forever.")
                .font(.body)
                .foregroundColor(.inkSoft)
            Text("Everything stays on this phone. No account, no sign-in, nothing uploaded — ever.")
                .font(.footnote)
                .foregroundColor(.inkFaint)
            SectionTitle(text: "Whose book is this?")
            TextField("Baby's name", text: $newName)
                .font(.system(.title3, design: .rounded))
                .padding(12)
                .background(Color.paperCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.lineSoft))
            DatePicker("Birthday", selection: $newBirth, in: ...Date(),
                       displayedComponents: .date)
                .font(.system(.body, design: .rounded))
            BigButton(title: "Start the book") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                _ = store.addChild(name: name, birthDate: newBirth)
            }
            .opacity(newName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
            Text("The birthday is how the book knows her age on every print — “3 months, 12 days” — and how the growth timeline stays honest.")
                .font(.footnote)
                .foregroundColor(.inkFaint)
        }
    }

    private func headerFor(_ child: ChildProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("For \(child.name)")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundColor(.inkPlum)
                Spacer()
                if store.library.children.count > 1 {
                    Menu {
                        ForEach(store.library.children) { c in
                            Button(c.name) { store.setActiveChild(c.id) }
                        }
                    } label: {
                        Text("Switch")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(.inkPlum)
                    }
                }
            }
            Text(child.ageText(at: Date()))
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.inkFaint)
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Hand or foot?")
            HStack(spacing: 14) {
                ForEach(PrintKind.allCases, id: \.self) { k in
                    Button {
                        kind = k
                    } label: {
                        VStack(spacing: 8) {
                            if let img = kindThumbs[k] {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 74)
                            } else {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.lineSoft.opacity(0.5))
                                    .frame(height: 74)
                            }
                            Text(k.label)
                                .font(.system(.headline, design: .rounded))
                                .foregroundColor(.inkPlum)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.paperCard)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(kind == k ? Color.inkPlum : Color.lineSoft,
                                        lineWidth: kind == k ? 3 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var colorPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Ink color")
            if !store.library.settings.recentColorHexes.isEmpty {
                Text("Recent")
                    .font(.caption).foregroundColor(.inkFaint)
                HStack(spacing: 6) {
                    ForEach(store.library.settings.recentColorHexes, id: \.self) { hex in
                        SwatchView(swatch: PaletteSwatch(name: "", hex: hex),
                                   selected: selectedColor.hexString == hex) {
                            selectedColor = InkColor(hex: hex)
                        }
                    }
                    Spacer()
                }
            }
            swatchRow(InkPalette.classics)
            swatchRow(InkPalette.pastels)
            HStack {
                ColorPicker("Any color", selection: $customColor, supportsOpacity: false)
                    .font(.system(.body, design: .rounded))
                    .onChange(of: customColor) { _, newValue in
                        selectedColor = InkColor(newValue)
                    }
                Spacer()
                Circle().fill(Color(selectedColor)).frame(width: 30, height: 30)
                    .overlay(Circle().stroke(Color.lineSoft))
            }
        }
    }

    private func swatchRow(_ swatches: [PaletteSwatch]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(swatches, id: \.name) { sw in
                    SwatchView(swatch: sw, selected: selectedColor.hexString == sw.hex) {
                        selectedColor = sw.color
                    }
                }
            }
        }
    }

    private var materialPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Ink or paint?")
            Picker("Material", selection: $material) {
                ForEach(PrintMaterial.allCases, id: \.self) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            Text(material == .ink
                 ? "Ink — thin, a little translucent, sharp at the edges."
                 : "Paint — thick, soft at the edges, covers fully.")
                .font(.footnote)
                .foregroundColor(.inkFaint)
        }
    }

    // MARK: - The pad

    private var padView: some View {
        ZStack {
            Color.paperCream.ignoresSafeArea()
            PadSurface(control: padControl,
                       onProgress: { sampleCount = $0 },
                       onFinish: { samples, lifted in
                           finishPress(samples: samples, lifted: lifted)
                       })
            VStack {
                Text("Press the little \(kind.label.lowercased()) flat,\nhold a moment, lift.")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundColor(.inkPlum)
                    .multilineTextAlignment(.center)
                    .padding(.top, 26)
                    .allowsHitTesting(false)
                Spacer()
                // The guide ring breathes gently until contact
                // lands (spec §2.1's soft pulsing ring). Decorative
                // only: it must NEVER eat a touch — the pad below
                // gets every press (review finding: the overlay sat
                // above the pad in the press zone).
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(Color.inkPlum.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                    .frame(width: 300, height: 380)
                    .opacity(sampleCount > 0 ? 1.0 : (padPulse ? 0.85 : 0.45))
                    .scaleEffect(sampleCount > 0 ? 1.0 : (padPulse ? 1.012 : 0.995))
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                               value: padPulse)
                    .allowsHitTesting(false)
                Spacer()
                Text(sampleCount == 0 ? "The pad is listening…"
                                      : "That's it — keep holding…")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.inkFaint)
                    .allowsHitTesting(false)
                HStack(spacing: 14) {
                    BigButton(title: "Cancel", secondary: true) {
                        phase = .setup
                    }
                    if sampleCount > 0 {
                        BigButton(title: "Done") { padControl.finish() }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .onAppear {
            sampleCount = 0
            padControl.reset()
            padPulse = true
        }
        .onDisappear { padPulse = false }
    }

    private func finishPress(samples: [ContactSample], lifted: Bool) {
        guard phase == .pad, let child = store.activeChild else { return }
        if lifted {
            StampSound.shared.play(enabled: store.library.settings.soundOn)
        }
        let months = ageInMonths(birth: child.birthDate, at: Date())
        let pure = store.library.settings.pureContact
        let mat = material, col = selectedColor, k = kind
        DispatchQueue.global(qos: .userInitiated).async {
            let shape = PrintBuild.build(samples: samples, kind: k, ageMonths: months,
                                         pureContact: pure,
                                         mmPerPoint: ScreenMetrics.mmPerPoint)
            DispatchQueue.main.async {
                guard let shape else {
                    phase = .tooSmall
                    return
                }
                let now = Date()
                let rec = PrintRecord(
                    childID: child.id, kind: k, material: mat, color: col,
                    createdAt: now,
                    ageLabel: ageText(birth: child.birthDate, at: now),
                    shape: shape,
                    seed: UInt64(now.timeIntervalSince1970 * 1000) &+ UInt64(samples.count))
                draft = rec
                rotDeg = 0; nudgeX = 0; nudgeY = 0
                settle = false
                phase = .preview
                renderPreview()
                withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
                    settle = true
                }
            }
        }
    }

    // MARK: - Preview / adjust / keep

    private var previewView: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("There it is.")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundColor(.inkPlum)
                    .padding(.top, 10)
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.paperCard)
                        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
                    if let img = previewImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .padding(18)
                            .scaleEffect(settle ? 1 : 1.16)
                            .opacity(settle ? 1 : 0.4)
                    } else {
                        ProgressView().padding(60)
                    }
                }
                .padding(.horizontal, 20)
                if let d = draft {
                    VStack(spacing: 3) {
                        Text("\(d.kind.label) · \(d.ageLabel)")
                            .font(.system(.headline, design: .rounded))
                            .foregroundColor(.inkSoft)
                        Text(d.sizeText)
                            .font(.footnote)
                            .foregroundColor(.inkFaint)
                        if d.shape.digitFilled {
                            Text("One little digit didn't quite press, so we gently completed it. Prefer prints exactly as pressed? Turn on “Pure contact” in Settings.")
                                .font(.footnote)
                                .foregroundColor(.inkFaint)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                adjustControls
                VStack(spacing: 12) {
                    BigButton(title: "Keep this print") { keepDraft() }
                    BigButton(title: "Try again", secondary: true) { phase = .pad }
                    Button("Start over") { phase = .setup }
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.inkFaint)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var adjustControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Straighten it a touch?")
            HStack {
                Text("Turn")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.inkSoft)
                Slider(value: $rotDeg, in: -25...25, step: 0.5) { editing in
                    if !editing { applyAdjustments() }
                }
                Text("\(Int(rotDeg))°")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.inkFaint)
                    .frame(width: 40)
            }
            HStack {
                Text("Nudge")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.inkSoft)
                Spacer()
                nudgeButton("arrow.up", dx: 0, dy: -4)
                nudgeButton("arrow.left", dx: -4, dy: 0)
                nudgeButton("arrow.right", dx: 4, dy: 0)
                nudgeButton("arrow.down", dx: 0, dy: 4)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
    }

    private func nudgeButton(_ symbol: String, dx: Double, dy: Double) -> some View {
        Button {
            nudgeX = clampD(nudgeX + dx, -30, 30)
            nudgeY = clampD(nudgeY + dy, -30, 30)
            applyAdjustments()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.inkPlum)
                .frame(width: 46, height: 40)
                .background(Color.paperCard)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.lineSoft))
        }
        .buttonStyle(.plain)
    }

    private func applyAdjustments() {
        guard var d = draft else { return }
        d.rotationDeg = rotDeg
        d.offset = Point2(nudgeX, nudgeY)
        draft = d
        renderPreview()
    }

    private func renderPreview() {
        guard let d = draft else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = PrintRenderer.image(for: d, background: InkColor(hex: "#FFFDF6"),
                                          longEdgePx: 1100)
            DispatchQueue.main.async { previewImage = img }
        }
    }

    private func keepDraft() {
        guard let d = draft else { return }
        store.addPrint(d)
        DispatchQueue.global(qos: .utility).async {
            if let data = PrintRenderer.image(for: d, longEdgePx: 2048)?.pngData() {
                store.saveImageData(data, for: d.id)
            }
        }
        phase = .saved
    }

    // MARK: - Too small / saved

    private var tooSmallView: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("That was just a tap.")
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundColor(.inkPlum)
            Text("Press the little \(kind.label.lowercased()) flat on the pad and hold a moment — a real press is what makes the print.")
                .font(.body)
                .foregroundColor(.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            BigButton(title: "Try again") { phase = .pad }
                .padding(.horizontal, 20)
            Button("Back to start") { phase = .setup }
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.inkFaint)
            Spacer()
        }
    }

    private var savedView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 58))
                .foregroundColor(.inkPlum)
            Text("Kept.")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundColor(.inkPlum)
            if let child = store.activeChild {
                Text("It's in \(child.name)'s book now — \(child.ageText(at: Date())), at true size.")
                    .font(.body)
                    .foregroundColor(.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
            VStack(spacing: 12) {
                BigButton(title: "Make another print") { phase = .pad }
                BigButton(title: "See it in the book", secondary: true) {
                    selectedTab = .book
                    phase = .setup
                }
                Button("Done") { phase = .setup }
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.inkFaint)
            }
            .padding(.horizontal, 20)
            Spacer()
        }
    }

    // MARK: - Kind thumbnails

    private func makeKindThumbs() {
        guard kindThumbs.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            var out: [PrintKind: UIImage] = [:]
            for k in PrintKind.allCases {
                let shape = PrintRenderer.silhouetteShape(
                    kind: k, ageMonths: 3.5, lengthMM: 90,
                    mmPerPoint: ScreenMetrics.mmPerPoint)
                out[k] = PrintRenderer.image(shape: shape, color: .plum,
                                             material: .ink, seed: 5, longEdgePx: 300)
            }
            DispatchQueue.main.async { kindThumbs = out }
        }
    }
}
