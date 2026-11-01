// LibraryStore.swift — owns the on-device library: one JSON file +
// baked PNG caches under Application Support. Nothing leaves the
// phone (spec §8). Saves are debounced and atomic (write-then-move).

import Foundation
import Combine

public final class LibraryStore: ObservableObject {
    @Published public private(set) var library: LibraryFile
    @Published public private(set) var loadError: String? = nil

    public let rootDir: URL
    public let imagesDir: URL
    private let fileURL: URL
    private var saveWork: DispatchWorkItem?

    public init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        rootDir = base.appendingPathComponent("LittleImprints", isDirectory: true)
        imagesDir = rootDir.appendingPathComponent("Images", isDirectory: true)
        fileURL = rootDir.appendingPathComponent("library.json")
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.library.decode(LibraryFile.self, from: data) {
            library = decoded
        } else {
            if fm.fileExists(atPath: fileURL.path) {
                loadError = "The keepsake book could not be read. Nothing was overwritten — please let us know."
            }
            library = LibraryFile()
        }
        applyBackupPreference()
    }

    // MARK: - Accessors

    public var activeChild: ChildProfile? {
        if let id = library.activeChildID,
           let c = library.children.first(where: { $0.id == id }) { return c }
        return library.children.first
    }

    public func prints(for childID: UUID) -> [PrintRecord] {
        library.prints.filter { $0.childID == childID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func pages(for childID: UUID) -> [PageRecord] {
        library.pages.filter { $0.childID == childID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func printRecord(id: UUID) -> PrintRecord? {
        library.prints.first { $0.id == id }
    }

    // MARK: - Mutations (each persists)

    public func mutate(_ change: (inout LibraryFile) -> Void) {
        change(&library)
        scheduleSave()
        applyBackupPreference()
    }

    public func addChild(name: String, birthDate: Date) -> ChildProfile {
        let child = ChildProfile(name: name, birthDate: birthDate)
        mutate { lib in
            lib.children.append(child)
            if lib.activeChildID == nil { lib.activeChildID = child.id }
        }
        return child
    }

    public func setActiveChild(_ id: UUID) {
        mutate { $0.activeChildID = id }
    }

    public func addPrint(_ record: PrintRecord) {
        mutate { lib in
            lib.prints.append(record)
            var hexes = lib.settings.recentColorHexes
            hexes.removeAll { $0 == record.color.hexString }
            hexes.insert(record.color.hexString, at: 0)
            lib.settings.recentColorHexes = Array(hexes.prefix(8))
        }
    }

    public func updatePrint(_ record: PrintRecord) {
        mutate { lib in
            if let i = lib.prints.firstIndex(where: { $0.id == record.id }) {
                lib.prints[i] = record
            }
        }
    }

    public func deletePrint(_ id: UUID) {
        mutate { lib in
            lib.prints.removeAll { $0.id == id }
            for pi in lib.pages.indices {
                lib.pages[pi].prints.removeAll { $0.printID == id }
            }
        }
        let png = imagesDir.appendingPathComponent("print-\(id.uuidString).png")
        try? FileManager.default.removeItem(at: png)
    }

    public func addPage(_ page: PageRecord) {
        mutate { $0.pages.append(page) }
    }

    public func updatePage(_ page: PageRecord) {
        mutate { lib in
            if let i = lib.pages.firstIndex(where: { $0.id == page.id }) {
                lib.pages[i] = page
            }
        }
    }

    public func deletePage(_ id: UUID) {
        mutate { $0.pages.removeAll { $0.id == id } }
    }

    // MARK: - Image cache files

    public func imageURL(for printID: UUID) -> URL {
        imagesDir.appendingPathComponent("print-\(printID.uuidString).png")
    }

    public func saveImageData(_ data: Data, for printID: UUID) {
        try? data.write(to: imageURL(for: printID), options: [.atomic])
    }

    public func imageData(for printID: UUID) -> Data? {
        try? Data(contentsOf: imageURL(for: printID))
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    public func saveNow() {
        guard let data = try? JSONEncoder.library.encode(library) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private func applyBackupPreference() {
        var dir = rootDir
        var values = URLResourceValues()
        values.isExcludedFromBackup = library.settings.excludeFromBackup
        try? dir.setResourceValues(values)
    }
}

extension JSONEncoder {
    static var library: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var library: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
