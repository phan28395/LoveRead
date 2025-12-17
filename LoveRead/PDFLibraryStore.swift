import Foundation

@MainActor
final class PDFLibraryStore: ObservableObject {
    @Published private(set) var items: [PDFItem] = []

    private let fileManager = FileManager.default

    init() {
        load()
    }

    func addPDF(from pickedURL: URL) throws {
        let libraryDir = try libraryDirectory()
        try ensureDirectoryExists(libraryDir)

        let id = UUID()
        let fileName = "\(id.uuidString).pdf"
        let destinationURL = libraryDir.appendingPathComponent(fileName)

        try copyPDFToLibrary(from: pickedURL, to: destinationURL)

        let item = PDFItem(
            id: id,
            displayName: pickedURL.deletingPathExtension().lastPathComponent,
            fileName: fileName,
            addedAt: Date()
        )

        items.insert(item, at: 0)
        try save()
    }

    func delete(_ item: PDFItem) {
        do {
            let fileURL = try url(for: item)
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }

            items.removeAll { $0.id == item.id }
            try save()
            UserDefaults.standard.removeObject(forKey: Self.pageKey(for: item.id))
            UserDefaults.standard.removeObject(forKey: Self.positionKey(for: item.id))
        } catch {
            // Non-fatal; keep UI responsive.
        }
    }

    func url(for item: PDFItem) throws -> URL {
        let libraryDir = try libraryDirectory()
        return libraryDir.appendingPathComponent(item.fileName)
    }

    func savedPageIndex(for id: UUID) -> Int {
        if let position = savedPosition(for: id) {
            return position.pageIndex
        }
        return UserDefaults.standard.integer(forKey: Self.pageKey(for: id))
    }

    func savePageIndex(_ pageIndex: Int, for id: UUID) {
        UserDefaults.standard.set(pageIndex, forKey: Self.pageKey(for: id))
    }

    func savedPosition(for id: UUID) -> PDFReadingPosition? {
        let key = Self.positionKey(for: id)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PDFReadingPosition.self, from: data)
    }

    func savePosition(_ position: PDFReadingPosition, for id: UUID) {
        UserDefaults.standard.set(position.pageIndex, forKey: Self.pageKey(for: id))
        let key = Self.positionKey(for: id)
        if let data = try? JSONEncoder().encode(position) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func pageKey(for id: UUID) -> String {
        "pdf_last_page_\(id.uuidString)"
    }

    static func positionKey(for id: UUID) -> String {
        "pdf_last_position_\(id.uuidString)"
    }

    private func load() {
        do {
            let url = try manifestURL()
            guard fileManager.fileExists(atPath: url.path) else {
                items = []
                return
            }
            let data = try Data(contentsOf: url)
            items = try JSONDecoder().decode([PDFItem].self, from: data)
        } catch {
            items = []
        }
    }

    private func save() throws {
        let url = try manifestURL()
        let data = try JSONEncoder().encode(items)
        try data.write(to: url, options: [.atomic])
    }

    private func manifestURL() throws -> URL {
        let libraryDir = try libraryDirectory()
        try ensureDirectoryExists(libraryDir)
        return libraryDir.appendingPathComponent("items.json")
    }

    private func libraryDirectory() throws -> URL {
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return docs.appendingPathComponent("LibraryPDFs", isDirectory: true)
    }

    private func ensureDirectoryExists(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func copyPDFToLibrary(from pickedURL: URL, to destinationURL: URL) throws {
        let needsSecurityScope = pickedURL.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                pickedURL.stopAccessingSecurityScopedResource()
            }
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: pickedURL, to: destinationURL)
    }
}
