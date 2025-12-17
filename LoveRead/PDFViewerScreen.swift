import SwiftUI

#if os(iOS)
import UIKit
#endif

struct PDFViewerScreen: View {
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
    @StateObject private var speechManager = SpeechManager(anchorDefaultsKey: nil)
    @State private var speechPageIndex: Int?
    @State private var speechText: String = ""

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

                SpeechControlBar(
                    speechManager: speechManager,
                    isBusy: isExtracting && !speechManager.isSpeaking,
                    onPlayPause: { toggleSpeech(from: url) },
                    onReset: resetSpeech
                )
            }
            .navigationTitle(item.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if mode == .text, !pageTexts.isEmpty {
                        Button("Copy Page") { copyCurrentPage() }
                        Button("Share") { isSharing = true }
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
                speechPageIndex = nil
                speechText = ""
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .text {
                    scrollToPageIndex = currentPageIndex
                    Task { _ = await ensureTextLoaded(from: url) }
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
            },
            highlightPageIndex: (isKaraokeActive ? speechPageIndex : nil),
            highlightRange: (isKaraokeActive ? speechManager.currentRange : nil),
            scrollToHighlight: speechManager.isSpeaking
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
                },
                karaokePageIndex: speechPageIndex,
                karaokeRange: speechManager.currentRange,
                isKaraokeActive: isKaraokeActive
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
                    Task { _ = await ensureTextLoaded(from: url) }
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .disabled(isExtracting)
            }
        }
    }

    @MainActor
    private func ensureTextLoaded(from url: URL) async -> Bool {
        if !pageTexts.isEmpty { return true }
        if isExtracting { return false }

        isExtracting = true
        extractionErrorMessage = nil

        do {
            let pages = try await Task.detached(priority: .userInitiated) {
                try PDFTextExtractor.extractPages(from: url)
            }.value

            let hasAnyText = pages.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            pageTexts = pages
            isExtracting = false
            if !hasAnyText {
                extractionErrorMessage = "No selectable text found in this PDF (it may be scanned)."
            }
            return hasAnyText
        } catch {
            isExtracting = false
            extractionErrorMessage = (error as NSError).localizedDescription
            return false
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

    private func toggleSpeech(from url: URL) {
        if speechManager.isSpeaking {
            speechManager.pauseSpeaking()
            return
        }

        Task { @MainActor in
            if speechManager.isPaused, speechPageIndex == currentPageIndex, !speechText.isEmpty {
                speechManager.startSpeaking(text: speechText)
                return
            }

            speechManager.reset()

            guard await ensureTextLoaded(from: url) else { return }
            guard currentPageIndex >= 0, currentPageIndex < pageTexts.count else { return }

            let pageText = pageTexts[currentPageIndex]
            if pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                extractionErrorMessage = "No selectable text found on this page."
                return
            }

            speechPageIndex = currentPageIndex
            speechText = pageText
            speechManager.startSpeaking(text: pageText)
        }
    }

    private func resetSpeech() {
        speechManager.reset()
        speechPageIndex = nil
        speechText = ""
    }

    private var isKaraokeActive: Bool {
        speechManager.isSpeaking || speechManager.isPaused
    }
}
