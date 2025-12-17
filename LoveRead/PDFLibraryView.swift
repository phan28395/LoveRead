import SwiftUI
import UniformTypeIdentifiers

struct PDFLibraryView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var library: PDFLibraryStore

    @State private var isImporting = false
    @State private var importErrorMessage: String?

    var body: some View {
        NavigationStack(path: $appState.pdfNavigation) {
            List {
                if library.items.isEmpty {
                    ContentUnavailableView(
                        "No PDFs yet",
                        systemImage: "doc",
                        description: Text("Tap Upload to add a PDF.")
                    )
                } else {
                    ForEach(library.items) { item in
                        NavigationLink(value: item.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.displayName)
                                    .font(.headline)
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    Text(item.addedAt, style: .date)
                                    let lastPage = library.savedPageIndex(for: item.id)
                                    if lastPage > 0 {
                                        Text("Last page: \(lastPage + 1)")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        let itemsToDelete = indexSet.map { library.items[$0] }
                        for item in itemsToDelete {
                            library.delete(item)
                        }
                        appState.pdfNavigation.removeAll { id in
                            itemsToDelete.contains(where: { $0.id == id })
                        }
                    }
                }
            }
            .navigationTitle("My PDFs")
            .navigationDestination(for: UUID.self) { id in
                if let item = library.items.first(where: { $0.id == id }) {
                    PDFViewerScreen(item: item)
                        .environmentObject(appState)
                        .environmentObject(library)
                } else {
                    ContentUnavailableView(
                        "PDF not found",
                        systemImage: "exclamationmark.triangle",
                        description: Text("It may have been deleted.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Upload") { isImporting = true }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                do {
                    let url = try result.getFirstURL()
                    try library.addPDF(from: url)
                } catch {
                    importErrorMessage = (error as NSError).localizedDescription
                }
            }
            .alert("Couldn’t import PDF", isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "")
            }
        }
    }
}

private extension Result where Success == [URL], Failure == Error {
    func getFirstURL() throws -> URL {
        let urls = try get()
        guard let first = urls.first else { throw CocoaError(.fileReadUnknown) }
        return first
    }
}

#Preview {
    PDFLibraryView()
        .environmentObject(AppState())
        .environmentObject(PDFLibraryStore())
}
