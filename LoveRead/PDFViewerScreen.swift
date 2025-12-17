import SwiftUI

#if os(iOS)
import UIKit
#endif

struct PDFViewerScreen: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var library: PDFLibraryStore

    let item: PDFItem

    private enum Mode: Hashable {
        case pdf
        case text
    }

    @State private var mode: Mode = .pdf
    @State private var currentPageIndex: Int = 0
    @State private var scrollToPageIndex: Int = 0

    @State private var pageTexts: [String] = []
    @State private var isExtracting = false
    @State private var extractionErrorMessage: String?
    @State private var isSharing = false

    var body: some View {
        if let url = try? library.url(for: item) {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    Text("PDF").tag(Mode.pdf)
                    Text("Text").tag(Mode.text)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                switch mode {
                case .pdf:
                    pdfView(url: url)
                case .text:
                    textView(url: url)
                }
            }
            .navigationTitle(item.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if mode == .text, !pageTexts.isEmpty {
                        Button("Copy Page") { copyCurrentPage() }
                        Button("Share") { isSharing = true }
                        Button("Open in Reader") { openCurrentPageInReader() }
                    }
                }
            }
            .sheet(isPresented: $isSharing) {
                #if os(iOS)
                ShareSheet(items: [currentPageText])
                #else
                Text(currentPageText)
                    .padding()
                #endif
            }
            .onAppear {
                let saved = library.savedPosition(for: item.id)
                currentPageIndex = saved?.pageIndex ?? library.savedPageIndex(for: item.id)
                scrollToPageIndex = currentPageIndex
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .text {
                    scrollToPageIndex = currentPageIndex
                    ensureTextLoaded(from: url)
                }
            }
            .alert("Couldn’t convert PDF", isPresented: Binding(
                get: { extractionErrorMessage != nil },
                set: { if !$0 { extractionErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(extractionErrorMessage ?? "")
            }
        } else {
            ContentUnavailableView(
                "PDF missing",
                systemImage: "exclamationmark.triangle",
                description: Text("This file couldn’t be opened.")
            )
            .navigationTitle(item.displayName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func pdfView(url: URL) -> some View {
        let initialPosition = library.savedPosition(for: item.id)
            ?? PDFReadingPosition(pageIndex: library.savedPageIndex(for: item.id), x: nil, y: nil)

        return PDFViewerView(
            url: url,
            initialPosition: initialPosition,
            onPositionChange: { position in
                library.savePosition(position, for: item.id)
                if position.pageIndex != currentPageIndex {
                    currentPageIndex = position.pageIndex
                }
                if position.pageIndex != scrollToPageIndex {
                    scrollToPageIndex = position.pageIndex
                }
            }
        )
    }

    @ViewBuilder
    private func textView(url: URL) -> some View {
        if isExtracting && pageTexts.isEmpty {
            ProgressView("Converting…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !pageTexts.isEmpty {
            PDFTextModeView(
                pageTexts: pageTexts,
                currentPageIndex: $currentPageIndex,
                scrollToPageIndex: $scrollToPageIndex,
                onPageIndexChange: { newIndex in
                    scrollToPageIndex = newIndex
                    library.savePosition(PDFReadingPosition(pageIndex: newIndex, x: nil, y: nil), for: item.id)
                }
            )
        } else {
            ContentUnavailableView(
                "No text extracted",
                systemImage: "text.magnifyingglass",
                description: Text("Tap Convert to extract text from this PDF.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                Button(isExtracting ? "Converting…" : "Convert") {
                    ensureTextLoaded(from: url)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .disabled(isExtracting)
            }
        }
    }

    private func ensureTextLoaded(from url: URL) {
        guard !isExtracting else { return }
        guard pageTexts.isEmpty else { return }

        isExtracting = true
        extractionErrorMessage = nil

        Task.detached(priority: .userInitiated) {
            do {
                let pages = try PDFTextExtractor.extractPages(from: url)
                let hasAnyText = pages.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                await MainActor.run {
                    self.pageTexts = pages
                    self.isExtracting = false
                    if !hasAnyText {
                        self.extractionErrorMessage = "No selectable text found in this PDF (it may be scanned)."
                    }
                }
            } catch {
                await MainActor.run {
                    self.isExtracting = false
                    self.extractionErrorMessage = (error as NSError).localizedDescription
                }
            }
        }
    }

    private var currentPageText: String {
        guard currentPageIndex >= 0, currentPageIndex < pageTexts.count else { return "" }
        return pageTexts[currentPageIndex].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyCurrentPage() {
        #if os(iOS)
        UIPasteboard.general.string = currentPageText
        #endif
    }

    private func openCurrentPageInReader() {
        if pageTexts.isEmpty {
            appState.readerText = ""
        } else {
            let textFromHere = pageTexts[currentPageIndex...]
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            appState.readerText = textFromHere
        }
        appState.selectedTab = .reader
    }
}
