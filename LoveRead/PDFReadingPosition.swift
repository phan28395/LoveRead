import CoreGraphics
import Foundation

struct PDFReadingPosition: Codable, Hashable {
    var pageIndex: Int
    var x: Double?
    var y: Double?

    init(pageIndex: Int, point: CGPoint?) {
        self.pageIndex = pageIndex
        self.x = point.map { Double($0.x) }
        self.y = point.map { Double($0.y) }
    }

    init(pageIndex: Int, x: Double?, y: Double?) {
        self.pageIndex = pageIndex
        self.x = x
        self.y = y
    }

    var point: CGPoint? {
        guard let x, let y else { return nil }
        return CGPoint(x: x, y: y)
    }
}
