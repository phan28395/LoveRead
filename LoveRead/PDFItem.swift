import Foundation

struct PDFItem: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var fileName: String
    var addedAt: Date
}

