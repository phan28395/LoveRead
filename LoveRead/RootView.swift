import SwiftUI

struct RootView: View {
    @StateObject private var appState = AppState()
    @StateObject private var pdfLibrary = PDFLibraryStore()

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            ContentView(textInput: $appState.readerText)
                .tabItem {
                    Label("Reader", systemImage: "text.justify")
                }
                .tag(AppState.Tab.reader)

            PDFLibraryView()
                .environmentObject(appState)
                .environmentObject(pdfLibrary)
                .tabItem {
                    Label("PDFs", systemImage: "doc.richtext")
                }
                .tag(AppState.Tab.pdfs)
        }
    }
}

#Preview {
    RootView()
}

