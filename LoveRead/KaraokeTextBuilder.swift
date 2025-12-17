import Foundation
import SwiftUI

enum KaraokeTextBuilder {
    static func attributedString(for text: String, highlightRange: NSRange) -> AttributedString {
        var attributed = AttributedString(text)

        guard highlightRange.location != NSNotFound, highlightRange.length > 0 else { return attributed }
        guard highlightRange.location + highlightRange.length <= text.count else { return attributed }

        let start = attributed.index(attributed.startIndex, offsetByCharacters: highlightRange.location)
        let end = attributed.index(start, offsetByCharacters: highlightRange.length)
        let slice = start..<end

        attributed[slice].foregroundColor = .white
        attributed[slice].backgroundColor = .blue
        attributed[slice].font = .body.bold()

        return attributed
    }
}

