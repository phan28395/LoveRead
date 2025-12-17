import Foundation
import PDFKit

enum PDFTextExtractor {
    static func extractPages(from url: URL) throws -> [String] {
        guard let document = PDFDocument(url: url) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var pages: [String] = Array(repeating: "", count: document.pageCount)
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            pages[index] = page.string ?? ""
        }
        return pages
    }

    static func extractText(from url: URL) throws -> String {
        let pages = try extractPages(from: url)
        return pages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
