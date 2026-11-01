// PagesView.swift — keepsake pages (spec §2.2, §4, §5): several
// prints composed on one page, with stamps, words, frames, the
// date stamp, and the footprint-butterfly — all non-destructive,
// all autosaved (no Save button anywhere, per house style).

import SwiftUI

struct PagesView: View {
    @EnvironmentObject var store: LibraryStore
    @Binding var selectedTab: AppTab
    @State private var openPageID: UUID? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paperCream.ignoresSafeArea()
                if let child = store.activeChild {
                    let pages = store.pages(for: child.id)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            BigButton(title: "Start a new page") {
                                let page = PageRecord(childID: child.id, createdAt: Date(),
                                                      paper: .cream)
                                store.addPage(page)
                                openPageID = page.id
                            }
                            if pages.isEmpty {
                                Text("Pages are where prints come together — both feet side by side, a hand and a foot, a name underneath. Start one from any print in the book, or from scratch here.")
                                    .font(.body).foregroundColor(.inkSoft)
                                    .padding(.top, 6)
                            }
                            ForEach(pages) { page in
                                Button {
                                    openPageID = page.id
                                } label: {
                                    HStack(spacing: 12) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(page.paper))
                                            .frame(width: 52, height: 64)
                                            .overlay(RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.lineSoft))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(page.title.isEmpty ? "Untitled page" : page.title)
                                                .font(.system(.headline, design: .rounded))
                                                .foregroundColor(.inkSoft)
                                            Text(page.prints.count == 1
                                                 ? "1 print · \(page.createdAt.formatted(date: .abbreviated, time: .omitted))"
                                                 : "\(page.prints.count) prints · \(page.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                                .font(.footnote)
                                                .foregroundColor(.inkFaint)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.inkFaint)
                                    }
                                    .padding(12)
                                    .background(Color.paperCard)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.lineSoft))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(18)
                    }
                } else {
                    Text("Add your baby in the Capture tab first — pages belong to a book.")
                        .font(.body).foregroundColor(.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(36)
                }
            }
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $openPageID) { pageID in
                PageEditorView(pageID: pageID)
            }
        }
    }
}

// MARK: - Editor

struct PageEditorView: View {
    let pageID: UUID
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    private enum Selection: Equatable {
        case print(UUID)
        case layer(UUID)
    }
    @State private var selection: Selection? = nil
    @State private var printImages: [UUID: UIImage] = [:]
    @State private var showAddPrint = false
    @State private var showAddStamp = false
    @State private var showAddWords = false
    @State private var wordsText = ""
    @State private var sharePayload: SharePayload? = nil
    @State private var dragStart: Point2? = nil

    private var page: PageRecord? {
        store.library.pages.first { $0.id == pageID }
    }

    var body: some View {
        ZStack {
            Color.paperCream.ignoresSafeArea()
            if let page {
                ScrollView {
                    VStack(spacing: 14) {
                        titleField(page)
                        canvas(page)
                        selectionControls(page)
                        addBar(page)
                        paperRow(page)
                        BigButton(title: "Share this page") {
                            if let img = PageRenderer.image(for: page, store: store) {
                                sharePayload = SharePayload(items: [img])
                            }
                        }
                        Button("Delete this page", role: .destructive) {
                            store.deletePage(pageID)
                            dismiss()
                        }
                        .font(.system(.subheadline, design: .rounded))
                    }
                    .padding(16)
                }
            } else {
                Text("This page is gone.").foregroundColor(.inkFaint)
            }
        }
        .navigationTitle("Page")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharePayload) { payload in ShareSheet(items: payload.items) }
        .sheet(isPresented: $showAddPrint) { addPrintSheet }
        .sheet(isPresented: $showAddStamp) { addStampSheet }
        .sheet(isPresented: $showAddWords) { addWordsSheet }
        .task(id: page?.prints.map { $0.printID } ?? []) { await loadImages() }
    }

    // MARK: Canvas

    private func titleField(_ page: PageRecord) -> some View {
        TextField("Page title", text: Binding(
            get: { page.title },
            set: { v in update { $0.title = v } }
        ))
        .font(.system(.title3, design: .rounded).weight(.semibold))
        .foregroundColor(.inkPlum)
        .multilineTextAlignment(.center)
    }

    private func canvas(_ page: PageRecord) -> some View {
        GeometryReader { geo in
            let pw = min(geo.size.width, 400)
            let ph = pw * 5 / 4
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(page.paper))
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
                ForEach(page.prints) { placed in
                    if let record = store.printRecord(id: placed.printID),
                       let img = printImages[record.id] {
                        let w = pw * placed.scale
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: w, height: w * img.size.height / max(img.size.width, 1))
                            .rotationEffect(.degrees(placed.rotationDeg + record.rotationDeg))
                            .position(x: pw * placed.center.x, y: ph * placed.center.y)
                            .onTapGesture { selection = .print(placed.id) }
                            .gesture(dragGesture(for: .print(placed.id), pageSize: CGSize(width: pw, height: ph)) {
                                placed.center
                            } set: { newCenter in
                                update { pg in
                                    if let i = pg.prints.firstIndex(where: { $0.id == placed.id }) {
                                        pg.prints[i].center = newCenter
                                    }
                                }
                            })
                    }
                }
                ForEach(page.prints) { placed in
                    if selection == .print(placed.id),
                       let record = store.printRecord(id: placed.printID),
                       let img = printImages[record.id] {
                        let w = pw * placed.scale
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.inkPlum, style: StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
                            .frame(width: w + 10,
                                   height: w * img.size.height / max(img.size.width, 1) + 10)
                            .rotationEffect(.degrees(placed.rotationDeg + record.rotationDeg))
                            .position(x: pw * placed.center.x, y: ph * placed.center.y)
                            .allowsHitTesting(false)
                    }
                }
                ForEach(page.decorations.filter { $0.kind != .frame }) { layer in
                    DecorationView(layer: layer, pageSize: CGSize(width: pw, height: ph))
                        .position(x: pw * layer.center.x, y: ph * layer.center.y)
                        .onTapGesture { selection = .layer(layer.id) }
                        .gesture(dragGesture(for: .layer(layer.id), pageSize: CGSize(width: pw, height: ph)) {
                            layer.center
                        } set: { newCenter in
                            update { pg in
                                if let i = pg.decorations.firstIndex(where: { $0.id == layer.id }) {
                                    pg.decorations[i].center = newCenter
                                }
                            }
                        })
                }
                ForEach(page.decorations.filter { $0.kind == .frame }) { layer in
                    PageFrameView(style: layer.symbol, color: layer.color)
                }
            }
            .frame(width: pw, height: ph)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 500)
    }

    private func dragGesture(for sel: Selection, pageSize: CGSize,
                             get: @escaping () -> Point2,
                             set: @escaping (Point2) -> Void) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if selection != sel { selection = sel }
                if dragStart == nil { dragStart = get() }
                guard let start = dragStart else { return }
                set(Point2(
                    clampD(start.x + value.translation.width / pageSize.width, 0.03, 0.97),
                    clampD(start.y + value.translation.height / pageSize.height, 0.03, 0.97)))
            }
            .onEnded { _ in dragStart = nil }
    }

    // MARK: Selection controls

    @ViewBuilder
    private func selectionControls(_ page: PageRecord) -> some View {
        if let selection {
            VStack(spacing: 10) {
                HStack {
                    Text("Selected")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(.inkSoft)
                    Spacer()
                    Button("Remove") { removeSelection(page) }
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.red)
                }
                HStack(spacing: 10) {
                    Text("Size").font(.system(.footnote, design: .rounded)).foregroundColor(.inkFaint)
                    Slider(value: selectionScaleBinding(page), in: 0.10...1.05, step: 0.01)
                }
                HStack(spacing: 10) {
                    Text("Turn").font(.system(.footnote, design: .rounded)).foregroundColor(.inkFaint)
                    Button("-15°") { rotateSelection(page, by: -15) }
                    Button("+15°") { rotateSelection(page, by: 15) }
                    Spacer()
                    Button("Bring forward") { reorderSelection(page, forward: true) }
                    Button("Send back") { reorderSelection(page, forward: false) }
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.inkPlum)
            }
            .padding(12)
            .background(Color.paperCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.lineSoft))
        } else {
            Text("Tap a print or a stamp to move it, size it, or turn it.")
                .font(.footnote).foregroundColor(.inkFaint)
        }
    }

    private func selectionScaleBinding(_ page: PageRecord) -> Binding<Double> {
        Binding(
            get: {
                switch selection {
                case .print(let id): return page.prints.first { $0.id == id }?.scale ?? 0.5
                case .layer(let id): return page.decorations.first { $0.id == id }?.scale ?? 0.16
                case nil: return 0.5
                }
            },
            set: { v in
                switch selection {
                case .print(let id):
                    update { pg in
                        if let i = pg.prints.firstIndex(where: { $0.id == id }) { pg.prints[i].scale = v }
                    }
                case .layer(let id):
                    update { pg in
                        if let i = pg.decorations.firstIndex(where: { $0.id == id }) { pg.decorations[i].scale = v }
                    }
                case nil: break
                }
            })
    }

    private func rotateSelection(_ page: PageRecord, by deg: Double) {
        switch selection {
        case .print(let id):
            update { pg in
                if let i = pg.prints.firstIndex(where: { $0.id == id }) { pg.prints[i].rotationDeg += deg }
            }
        case .layer(let id):
            update { pg in
                if let i = pg.decorations.firstIndex(where: { $0.id == id }) { pg.decorations[i].rotationDeg += deg }
            }
        case nil: break
        }
    }

    private func reorderSelection(_ page: PageRecord, forward: Bool) {
        switch selection {
        case .print(let id):
            update { pg in
                guard let i = pg.prints.firstIndex(where: { $0.id == id }) else { return }
                let j = forward ? min(i + 1, pg.prints.count - 1) : max(i - 1, 0)
                pg.prints.swapAt(i, j)
            }
        case .layer(let id):
            update { pg in
                guard let i = pg.decorations.firstIndex(where: { $0.id == id }) else { return }
                let j = forward ? min(i + 1, pg.decorations.count - 1) : max(i - 1, 0)
                pg.decorations.swapAt(i, j)
            }
        case nil: break
        }
    }

    private func removeSelection(_ page: PageRecord) {
        switch selection {
        case .print(let id):
            update { $0.prints.removeAll { $0.id == id } }
        case .layer(let id):
            update { $0.decorations.removeAll { $0.id == id } }
        case nil: break
        }
        selection = nil
    }

    // MARK: Add bar + sheets

    private func addBar(_ page: PageRecord) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                addChip("Print", "hand.raised.fill") { showAddPrint = true }
                addChip("Stamp", "heart.fill") { showAddStamp = true }
                addChip("Words", "text.quote") { showAddWords = true }
                addChip("Date stamp", "stamp.fill") { addDateStamp(page) }
                Menu {
                    ForEach(StampCatalog.frameStyles, id: \.symbol) { style in
                        Button(style.name) { setFrame(page, style: style.symbol) }
                    }
                } label: {
                    chipLabel("Frame", "square.dashed")
                }
                addChip("Butterfly", "ladybug.fill") { addButterfly(page) }
            }
        }
    }

    private func addChip(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, symbol) }
            .buttonStyle(.plain)
    }

    private func chipLabel(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(.system(.subheadline, design: .rounded).weight(.semibold))
        .foregroundColor(.inkPlum)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Color.paperCard)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.lineSoft))
    }

    private var addPrintSheet: some View {
        NavigationStack {
            ZStack {
                Color.paperCream.ignoresSafeArea()
                if let page, let child = store.library.children.first(where: { $0.id == page.childID }) {
                    let prints = store.prints(for: child.id)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                                  spacing: 12) {
                            ForEach(prints) { record in
                                Button {
                                    update { pg in
                                        pg.prints.append(PlacedPrint(
                                            printID: record.id,
                                            center: Point2(0.5, 0.5), scale: 0.52))
                                    }
                                    showAddPrint = false
                                } label: {
                                    PrintThumb(record: record)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Add a print")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var addStampSheet: some View {
        NavigationStack {
            ZStack {
                Color.paperCream.ignoresSafeArea()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 14) {
                        ForEach(StampCatalog.symbols + StampCatalog.drawn, id: \.symbol) { stamp in
                            Button {
                                addStamp(symbol: stamp.symbol)
                                showAddStamp = false
                            } label: {
                                VStack(spacing: 6) {
                                    stampGlyph(stamp.symbol)
                                        .frame(width: 44, height: 44)
                                    Text(stamp.name)
                                        .font(.caption)
                                        .foregroundColor(.inkSoft)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.paperCard)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.lineSoft))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Add a stamp")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func stampGlyph(_ symbol: String) -> some View {
        switch symbol {
        case "drawn-butterfly": ButterflyShape().fill(Color.inkPlum)
        case "drawn-bow": BowShape().fill(Color.inkPlum)
        case "drawn-flower": FlowerShape().fill(Color.inkPlum)
        default:
            Image(systemName: symbol)
                .resizable().scaledToFit()
                .foregroundColor(.inkPlum)
        }
    }

    private var addWordsSheet: some View {
        NavigationStack {
            ZStack {
                Color.paperCream.ignoresSafeArea()
                VStack(spacing: 14) {
                    if let page, let child = store.library.children.first(where: { $0.id == page.childID }) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(captionSuggestions(name: child.name, birth: child.birthDate,
                                                           at: page.createdAt), id: \.self) { s in
                                    Button(s) { wordsText = s }
                                        .font(.system(.footnote, design: .rounded))
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Color.paperCard)
                                        .foregroundColor(.inkPlum)
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color.lineSoft))
                                }
                            }
                        }
                    }
                    TextField("Her name, a caption, a date…", text: $wordsText)
                        .font(.system(.title3, design: .rounded))
                        .padding(12)
                        .background(Color.paperCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.lineSoft))
                    BigButton(title: "Put it on the page") {
                        let t = wordsText.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        update { pg in
                            pg.decorations.append(DecorationLayer(
                                kind: .text, text: t, color: .plum,
                                center: Point2(0.5, 0.86), scale: 0.30))
                        }
                        wordsText = ""
                        showAddWords = false
                    }
                    Spacer()
                }
                .padding(18)
            }
            .navigationTitle("Add words")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Mutations

    private func update(_ change: (inout PageRecord) -> Void) {
        guard var pg = page else { return }
        change(&pg)
        store.updatePage(pg)
    }

    private func addStamp(symbol: String) {
        update { pg in
            let color = pg.prints.last
                .flatMap { store.printRecord(id: $0.printID) }?.color ?? .plum
            pg.decorations.append(DecorationLayer(
                kind: .stamp, symbol: symbol, color: color,
                center: Point2(0.22, 0.20), scale: 0.16))
        }
    }

    private func addDateStamp(_ page: PageRecord) {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        update { pg in
            pg.decorations.append(DecorationLayer(
                kind: .dateStamp, text: fmt.string(from: page.createdAt),
                color: InkColor(hex: "#9E2A2B"),
                center: Point2(0.74, 0.12), scale: 0.26, rotationDeg: -8))
        }
    }

    private func setFrame(_ page: PageRecord, style: String) {
        update { pg in
            pg.decorations.removeAll { $0.kind == .frame }
            pg.decorations.append(DecorationLayer(
                kind: .frame, symbol: style, color: .plum,
                center: Point2(0.5, 0.5), scale: 1))
        }
    }

    private func addButterfly(_ page: PageRecord) {
        guard let foot = page.prints.first(where: {
            store.printRecord(id: $0.printID)?.kind == .foot
        }) else {
            // No footprint on the page yet — a plain butterfly stamp.
            addStamp(symbol: "drawn-butterfly")
            return
        }
        let record = store.printRecord(id: foot.printID)
        update { pg in
            pg.decorations.append(DecorationLayer(
                kind: .butterfly, color: record?.color ?? .plum,
                center: foot.center, scale: foot.scale * 0.95,
                rotationDeg: foot.rotationDeg))
        }
    }

    private func paperRow(_ page: PageRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Paper")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PaperPalette.papers, id: \.name) { sw in
                        SwatchView(swatch: sw, selected: page.paper.hexString == sw.hex) {
                            update { $0.paper = sw.color }
                        }
                    }
                    ColorPicker("", selection: Binding(
                        get: { Color(page.paper) },
                        set: { c in update { $0.paper = InkColor(c) } }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
            }
        }
    }

    private func loadImages() async {
        guard let page else { return }
        var out = printImages
        for placed in page.prints where out[placed.printID] == nil {
            if let record = store.printRecord(id: placed.printID),
               let img = PrintRenderer.image(for: record, longEdgePx: 800) {
                out[record.id] = img
            }
        }
        printImages = out
    }
}
