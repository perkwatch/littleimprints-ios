// KeepsakeBookView.swift — the book (spec §5): every kept print,
// its date, her auto-computed age, and its true size. Plus the
// print detail with notes, captions, share, wallpaper, and PDF.

import SwiftUI

struct PrintThumb: View {
    let record: PrintRecord
    @EnvironmentObject var store: LibraryStore
    @State private var img: UIImage? = nil

    var body: some View {
        ZStack {
            Color.paperCard
            if let img {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            }
        }
        .aspectRatio(0.86, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.lineSoft))
        .task(id: record.id) {
            if let data = store.imageData(for: record.id), let ui = UIImage(data: data) {
                img = PrintRenderer.cropped(ui, shape: record.shape)
                return
            }
            img = PrintRenderer.croppedImage(for: record, longEdgePx: 500)
        }
    }
}

struct KeepsakeBookView: View {
    @EnvironmentObject var store: LibraryStore
    @Binding var selectedTab: AppTab
    @State private var showNightstand = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paperCream.ignoresSafeArea()
                if let child = store.activeChild {
                    content(for: child)
                } else {
                    emptyBook
                }
            }
            .navigationTitle(store.activeChild.map { "\($0.name)'s Book" } ?? "Keepsake Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNightstand = true
                    } label: {
                        Label("Nightstand", systemImage: "moon.stars.fill")
                            .font(.system(.subheadline, design: .rounded))
                    }
                    .tint(.inkPlum)
                }
            }
            .fullScreenCover(isPresented: $showNightstand) {
                NightstandWalkView()
            }
        }
    }

    private var emptyBook: some View {
        VStack(spacing: 14) {
            Text("No book yet.")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundColor(.inkPlum)
            Text("Add your baby in the Capture tab and the book begins with the first print.")
                .font(.body).foregroundColor(.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            BigButton(title: "Go to Capture") { selectedTab = .capture }
                .padding(.horizontal, 40)
        }
    }

    private func content(for child: ChildProfile) -> some View {
        let prints = store.prints(for: child.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                milestonePrompt(for: child)
                if prints.isEmpty {
                    VStack(spacing: 12) {
                        Text("No prints yet.")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundColor(.inkPlum)
                        Text("The first one takes ten seconds — and this size won't keep.")
                            .font(.body).foregroundColor(.inkSoft)
                            .multilineTextAlignment(.center)
                        BigButton(title: "Make the first print") { selectedTab = .capture }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    Text(prints.count == 1 ? "1 print" : "\(prints.count) prints")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.inkFaint)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 12) {
                        ForEach(prints) { record in
                            NavigationLink {
                                PrintDetailView(recordID: record.id, selectedTab: $selectedTab)
                            } label: {
                                VStack(spacing: 4) {
                                    PrintThumb(record: record)
                                    Text(record.ageLabel)
                                        .font(.caption2)
                                        .foregroundColor(.inkFaint)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func milestonePrompt(for child: ChildProfile) -> some View {
        if let next = nextMilestone(birth: child.birthDate, at: Date()),
           !store.library.settings.dismissedMilestones.contains(next.id),
           next.date.timeIntervalSinceNow < 21 * 86400 {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundColor(.inkPlum)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Coming up: \(next.title)")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(.inkSoft)
                    Text("A lovely time for another print — the book will mark the day.")
                        .font(.footnote)
                        .foregroundColor(.inkFaint)
                }
                Spacer()
                Button("Dismiss") {
                    store.mutate { lib in
                        if !lib.settings.dismissedMilestones.contains(next.id) {
                            lib.settings.dismissedMilestones.append(next.id)
                        }
                    }
                }
                .font(.system(.footnote, design: .rounded))
                .foregroundColor(.inkFaint)
            }
            .padding(12)
            .background(Color.paperCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.lineSoft))
        }
    }
}

// MARK: - Print detail

struct PrintDetailView: View {
    let recordID: UUID
    @Binding var selectedTab: AppTab
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var bigImage: UIImage? = nil
    @State private var note: String = ""
    @State private var caption: String = ""
    @State private var sharePayload: SharePayload? = nil
    @State private var showWallpaper = false
    @State private var confirmDelete = false
    @State private var loaded = false

    private var record: PrintRecord? { store.printRecord(id: recordID) }

    var body: some View {
        ZStack {
            Color.paperCream.ignoresSafeArea()
            if let record {
                ScrollView {
                    VStack(spacing: 18) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.paperCard)
                                .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
                            if let bigImage {
                                Image(uiImage: bigImage)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(20)
                            } else {
                                ProgressView().padding(70)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 14)

                        facts(for: record)
                        captions(for: record)
                        noteEditor(for: record)
                        actions(for: record)
                    }
                    .padding(.bottom, 30)
                }
            } else {
                Text("This print is no longer in the book.")
                    .foregroundColor(.inkFaint)
            }
        }
        .navigationTitle(record.map { "\($0.kind.label) print" } ?? "Print")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded, let record else { return }
            loaded = true
            note = record.note
            if let child = store.library.children.first(where: { $0.id == record.childID }) {
                caption = captionSuggestions(name: child.name, birth: child.birthDate,
                                             at: record.createdAt).first ?? ""
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let img = PrintRenderer.image(for: record, background: InkColor(hex: "#FFFDF6"),
                                              longEdgePx: 1400)
                DispatchQueue.main.async { bigImage = img }
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .sheet(isPresented: $showWallpaper) {
            if let record { WallpaperView(record: record) }
        }
        .confirmationDialog("Remove this print from the book?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove it", role: .destructive) {
                store.deletePrint(recordID)
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        }
    }

    private func facts(for record: PrintRecord) -> some View {
        VStack(spacing: 4) {
            Text(record.ageLabel)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(.inkSoft)
            Text(record.sizeText)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.inkFaint)
            Text("\(record.material.label) · \(record.createdAt.formatted(date: .long, time: .shortened))")
                .font(.footnote)
                .foregroundColor(.inkFaint)
        }
    }

    private func captions(for record: PrintRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Caption for sharing")
            if let child = store.library.children.first(where: { $0.id == record.childID }) {
                let suggestions = captionSuggestions(name: child.name, birth: child.birthDate,
                                                     at: record.createdAt)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            Button(s) { caption = s }
                                .font(.system(.footnote, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(caption == s ? Color.inkPlum : Color.paperCard)
                                .foregroundColor(caption == s ? .white : .inkPlum)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.lineSoft))
                        }
                    }
                }
            }
            TextField("Caption", text: $caption)
                .font(.system(.body, design: .rounded))
                .padding(10)
                .background(Color.paperCard)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.lineSoft))
        }
        .padding(.horizontal, 18)
    }

    private func noteEditor(for record: PrintRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "A note for the book")
            TextField("What was the day like?", text: $note, axis: .vertical)
                .font(.system(.body, design: .rounded))
                .lineLimit(2...5)
                .padding(10)
                .background(Color.paperCard)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.lineSoft))
                .onChange(of: note) { _, newValue in
                    var updated = record
                    updated.note = newValue
                    store.updatePrint(updated)
                }
        }
        .padding(.horizontal, 18)
    }

    private func actions(for record: PrintRecord) -> some View {
        VStack(spacing: 12) {
            BigButton(title: "Share this print") {
                if let img = Exporter.shareImage(for: record) {
                    sharePayload = SharePayload(items: caption.isEmpty ? [img] : [img, caption])
                }
            }
            BigButton(title: "Share the print alone (no paper)", secondary: true) {
                if let img = Exporter.transparentImage(for: record) {
                    sharePayload = SharePayload(items: [img])
                }
            }
            BigButton(title: "Make it a wallpaper", secondary: true) {
                showWallpaper = true
            }
            BigButton(title: "Print at real size (PDF)", secondary: true) {
                let childName = store.library.children
                    .first(where: { $0.id == record.childID })?.name ?? ""
                if let data = Exporter.pdfData(for: record, childName: childName),
                   let url = Exporter.tempFile(data: data,
                                               name: "little-imprints-true-size.pdf") {
                    sharePayload = SharePayload(items: [url])
                }
            }
            BigButton(title: "Start a page with it", secondary: true) {
                let page = PageRecord(
                    childID: record.childID, createdAt: Date(),
                    title: record.ageLabel, paper: .cream,
                    prints: [PlacedPrint(printID: record.id,
                                         center: Point2(0.5, 0.5), scale: 0.62)])
                store.addPage(page)
                selectedTab = .pages
                dismiss()
            }
            Button("Remove from the book", role: .destructive) { confirmDelete = true }
                .font(.system(.subheadline, design: .rounded))
                .padding(.top, 6)
        }
        .padding(.horizontal, 18)
    }
}

// MARK: - Wallpaper

struct WallpaperView: View {
    let record: PrintRecord
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var paper: InkColor = .cream
    @State private var trail: Bool = false
    @State private var preview: UIImage? = nil
    @State private var sharePayload: SharePayload? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paperCream.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if let preview {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 380)
                                .clipShape(RoundedRectangle(cornerRadius: 22))
                                .overlay(RoundedRectangle(cornerRadius: 22)
                                    .stroke(Color.lineSoft))
                                .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
                        } else {
                            ProgressView().padding(60)
                        }
                        if record.kind == .foot {
                            Picker("Style", selection: $trail) {
                                Text("One print").tag(false)
                                Text("Footprint trail").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: trail) { _, _ in render() }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(text: "Paper")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(PaperPalette.papers, id: \.name) { sw in
                                        SwatchView(swatch: sw, selected: paper.hexString == sw.hex) {
                                            paper = sw.color
                                            render()
                                        }
                                    }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            SectionTitle(text: "Setting it, honestly")
                            Text("Little Imprints can't set your wallpaper itself — iOS keeps that for you. Save the picture below, then open Settings → Wallpaper → Add New and pick it. It takes about twenty seconds, and then it's there every time you pick up the phone.")
                                .font(.footnote)
                                .foregroundColor(.inkSoft)
                        }
                        BigButton(title: "Save the wallpaper picture") {
                            let img = trail
                                ? Exporter.trailWallpaperImage(for: record, paper: paper)
                                : Exporter.wallpaperImage(for: record, paper: paper)
                            if let img { sharePayload = SharePayload(items: [img]) }
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Wallpaper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { render() }
            .sheet(item: $sharePayload) { payload in
                ShareSheet(items: payload.items)
            }
        }
    }

    private func render() {
        let useTrail = trail
        DispatchQueue.global(qos: .userInitiated).async {
            let img = useTrail
                ? Exporter.trailWallpaperImage(for: record, paper: paper)
                : Exporter.wallpaperImage(for: record, paper: paper)
            DispatchQueue.main.async { preview = img }
        }
    }
}
