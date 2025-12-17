import CoreGraphics
import Foundation

struct PDFReadingPosition: Codable, Hashable {
    var pageIndex: Int
    var x: Double?
    var y: Double?
    var progressFromTop: Double?
    var textScrollAnchor: Double?

    init(pageIndex: Int, point: CGPoint?) {
        self.pageIndex = pageIndex
        self.x = point.map { Double($0.x) }
        self.y = point.map { Double($0.y) }
        self.progressFromTop = nil
        self.textScrollAnchor = nil
    }

    init(
        pageIndex: Int,
        x: Double?,
        y: Double?,
        progressFromTop: Double? = nil,
        textScrollAnchor: Double? = nil
    ) {
        self.pageIndex = pageIndex
        self.x = x
        self.y = y
        self.progressFromTop = progressFromTop
        self.textScrollAnchor = textScrollAnchor
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
