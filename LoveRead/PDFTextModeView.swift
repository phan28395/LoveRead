import SwiftUI

struct PDFTextModeView: View {
    let pageTexts: [String]
    @Binding var currentPageIndex: Int
    @Binding var scrollToPageIndex: Int
    let onPageIndexChange: (Int) -> Void

    @State private var isProgrammaticScroll = false

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
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Page \(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()

                                Text(displayText(for: index))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal)
                            .id(index)
                            .background(PageOffsetReporter(index: index))
                        }
                    }
                    .padding(.vertical, 16)
                }
                .coordinateSpace(name: "PDFTextScroll")
                .onAppear {
                    scroll(proxy: proxy, to: scrollToPageIndex, animated: false)
                }
                .onChange(of: scrollToPageIndex) { _, newValue in
                    scroll(proxy: proxy, to: newValue, animated: true)
                }
                .onPreferenceChange(PageOffsetPreferenceKey.self) { offsets in
                    guard !isProgrammaticScroll else { return }
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

    private func displayText(for index: Int) -> String {
        let trimmed = pageTexts[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No selectable text found on this page." : trimmed
    }

    private func scroll(proxy: ScrollViewProxy, to index: Int, animated: Bool) {
        guard !pageTexts.isEmpty else { return }
        let clamped = max(0, min(index, pageTexts.count - 1))

        isProgrammaticScroll = true
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(clamped, anchor: .top)
            }
        } else {
            proxy.scrollTo(clamped, anchor: .top)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isProgrammaticScroll = false
        }
    }

    private func computeVisiblePage(from offsets: [Int: CGFloat]) -> Int? {
        guard !offsets.isEmpty else { return nil }

        let threshold: CGFloat = 120
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
        onPageIndexChange: { _ in }
    )
}

