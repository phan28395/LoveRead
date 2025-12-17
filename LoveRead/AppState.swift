import Foundation

final class AppState: ObservableObject {
    enum Tab: Hashable {
        case reader
        case pdfs
    }

    @Published var selectedTab: Tab = .reader
    @Published var readerText: String
    @Published var pdfNavigation: [UUID] = []

    static let defaultReaderText =
        "Welcome to the advanced reader. Paste your text here. When you press Read, I will highlight the words as I speak them. You can pause, change speed, and resume instantly."

    init(readerText: String = AppState.defaultReaderText) {
        self.readerText = readerText
    }
}
