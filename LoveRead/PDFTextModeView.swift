import Foundation
import SwiftUI

struct PDFTextModeView: View {
    let pageTexts: [String]
    @Binding var currentPageIndex: Int
    @Binding var scrollToPageIndex: Int
    let onPageIndexChange: (Int) -> Void
    var karaokePageIndex: Int?
    var karaokeRange: NSRange = NSRange(location: 0, length: 0)
    var isKaraokeActive: Bool = false

    @State private var isProgrammaticScroll = false
    @State private var scrollViewportHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    setPage(max(0, currentPageIndex - 1))
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 32, height: 32)
                }
                .disabled(currentPageIndex <= 0)

                Text("Page \(currentPageIndex + 1) / \(max(pageTexts.count, 1))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    setPage(min(max(pageTexts.count - 1, 0), currentPageIndex + 1))
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .frame(width: 32, height: 32)
                }
                .disabled(currentPageIndex >= pageTexts.count - 1)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(pageTexts.indices, id: \.self) { index in
                            let pageText = pageTexts[index]
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Page \(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()

                                if isKaraokeActive, karaokePageIndex == index, !pageText.isEmpty {
                                    Text(KaraokeTextBuilder.attributedString(for: pageText, highlightRange: karaokeRange))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                } else {
                                    Text(pageText.isEmpty ? "No selectable text found on this page." : pageText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.horizontal)
                            .id(index)
                            .background(PageOffsetReporter(index: index))
                        }
                    }
                    .padding(.vertical, 16)
                }
                .coordinateSpace(name: "PDFTextScroll")
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            isProgrammaticScroll = false
                        }
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { scrollViewportHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, newValue in
                                scrollViewportHeight = newValue
                            }
                    }
                )
                .onAppear {
                    scroll(proxy: proxy, to: scrollToPageIndex, animated: false)
                }
                .onChange(of: scrollToPageIndex) { _, newValue in
                    scroll(proxy: proxy, to: newValue, animated: true)
                }
                .onPreferenceChange(PageOffsetPreferenceKey.self) { offsets in
                    if isProgrammaticScroll {
                        if let visibleIndex = computeVisiblePage(from: offsets), visibleIndex == scrollToPageIndex {
                            isProgrammaticScroll = false
                        }
                        return
                    }

                    guard let visibleIndex = computeVisiblePage(from: offsets) else { return }
                    if visibleIndex != currentPageIndex {
                        currentPageIndex = visibleIndex
                        onPageIndexChange(visibleIndex)
                    }
                }
            }
        }
    }

    private func setPage(_ index: Int) {
        guard !pageTexts.isEmpty else { return }
        let clamped = max(0, min(index, pageTexts.count - 1))
        currentPageIndex = clamped
        scrollToPageIndex = clamped
        onPageIndexChange(clamped)
    }

    private func scroll(proxy: ScrollViewProxy, to index: Int, animated: Bool) {
        guard !pageTexts.isEmpty else { return }
        let clamped = max(0, min(index, pageTexts.count - 1))

        isProgrammaticScroll = true
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(clamped, anchor: .top)
                }
            } else {
                proxy.scrollTo(clamped, anchor: .top)
            }
        }
    }

    private func computeVisiblePage(from offsets: [Int: CGFloat]) -> Int? {
        guard !offsets.isEmpty else { return nil }

        let threshold: CGFloat = {
            if scrollViewportHeight > 0 {
                return min(80, max(16, scrollViewportHeight * 0.25))
            }
            return 80
        }()
        let nearTop = offsets.filter { $0.value <= threshold }
        if let best = nearTop.max(by: { $0.value < $1.value }) {
            return best.key
        }

        return offsets.min(by: { abs($0.value) < abs($1.value) })?.key
    }
}

private struct PageOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct PageOffsetReporter: View {
    let index: Int

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: PageOffsetPreferenceKey.self,
                value: [index: proxy.frame(in: .named("PDFTextScroll")).minY]
            )
        }
    }
}

#Preview {
    PDFTextModeView(
        pageTexts: [
            "Hello world on page 1\n\nMore text here.",
            "",
            "Page 3 text."
        ],
        currentPageIndex: .constant(0),
        scrollToPageIndex: .constant(0),
        onPageIndexChange: { _ in },
        karaokePageIndex: 0,
        karaokeRange: NSRange(location: 6, length: 5),
        isKaraokeActive: true
    )
}
