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

    var hasDestinationPoint: Bool {
        x != nil || y != nil
    }

    func destinationPoint(unspecifiedValue: CGFloat) -> CGPoint? {
        guard hasDestinationPoint else { return nil }
        let xValue = x.map { CGFloat($0) } ?? unspecifiedValue
        let yValue = y.map { CGFloat($0) } ?? unspecifiedValue
        return CGPoint(x: xValue, y: yValue)
    }
}
