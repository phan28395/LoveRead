import Foundation
import SwiftUI

struct PDFTextModeView: View {
    @Environment(\.scenePhase) private var scenePhase

    let pageTexts: [String]
    @Binding var currentPageIndex: Int
    @Binding var scrollToPageIndex: Int
    @Binding var livePosition: PDFReadingPosition?
    let onPositionChange: (PDFReadingPosition) -> Void
    var karaokePageIndex: Int?
    var karaokeRange: NSRange = NSRange(location: 0, length: 0)
    var isKaraokeActive: Bool = false

    @State private var scrollViewportHeight: CGFloat = 0
    @State private var pendingSaveWorkItem: DispatchWorkItem?
    @State private var lastComputedPosition: PDFReadingPosition?
    @State private var isRestoringInitialScroll = true

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
                            .background(PageGeometryReporter(index: index))
                        }
                    }
                    .padding(.vertical, 16)
                }
                .coordinateSpace(name: "PDFTextScroll")
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
                    isRestoringInitialScroll = true
                    scroll(proxy: proxy, to: scrollToPageIndex, anchor: restoreAnchor(for: scrollToPageIndex), animated: false)
                }
                .onChange(of: scrollToPageIndex) { _, newValue in
                    isRestoringInitialScroll = true
                    scroll(proxy: proxy, to: newValue, anchor: restoreAnchor(for: newValue), animated: true)
                }
                .onPreferenceChange(PageGeometryPreferenceKey.self) { geometries in
                    updatePosition(from: geometries)
                }
                .onDisappear {
                    flushPendingPositionSave()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                flushPendingPositionSave()
            }
        }
    }

    private func setPage(_ index: Int) {
        guard !pageTexts.isEmpty else { return }
        let clamped = max(0, min(index, pageTexts.count - 1))
        currentPageIndex = clamped
        scrollToPageIndex = clamped
        let position = PDFReadingPosition(pageIndex: clamped, x: nil, y: nil, progressFromTop: 0, textScrollAnchor: 0)
        livePosition = position
        schedulePositionSave(position)
    }

    private func scroll(proxy: ScrollViewProxy, to index: Int, anchor: UnitPoint, animated: Bool) {
        guard !pageTexts.isEmpty else { return }
        let clamped = max(0, min(index, pageTexts.count - 1))

        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(clamped, anchor: anchor)
                }
            } else {
                proxy.scrollTo(clamped, anchor: anchor)
            }
        }
    }

    private func updatePosition(from geometries: [Int: PageGeometry]) {
        guard !geometries.isEmpty else { return }
        guard let visibleIndex = computeVisiblePage(from: geometries) else { return }

        if visibleIndex != currentPageIndex {
            currentPageIndex = visibleIndex
        }

        guard let geometry = geometries[visibleIndex] else { return }
        let position = computePosition(pageIndex: visibleIndex, geometry: geometry)
        lastComputedPosition = position
        livePosition = position

        if isRestoringInitialScroll {
            let clampedTarget = max(0, min(scrollToPageIndex, max(0, pageTexts.count - 1)))
            if visibleIndex == clampedTarget {
                isRestoringInitialScroll = false
            }
            return
        }

        schedulePositionSave(position)
    }

    private func flushPendingPositionSave() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil

        guard let lastComputedPosition else { return }
        onPositionChange(lastComputedPosition)
    }

    private func schedulePositionSave(_ position: PDFReadingPosition) {
        lastComputedPosition = position
        pendingSaveWorkItem?.cancel()

        let workItem = DispatchWorkItem { [position] in
            onPositionChange(position)
        }
        pendingSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func computeVisiblePage(from geometries: [Int: PageGeometry]) -> Int? {
        guard !geometries.isEmpty else { return nil }

        let threshold: CGFloat = {
            if scrollViewportHeight > 0 {
                return min(80, max(16, scrollViewportHeight * 0.25))
            }
            return 80
        }()
        let nearTop = geometries.filter { $0.value.minY <= threshold }
        if let best = nearTop.max(by: { $0.value.minY < $1.value.minY }) {
            return best.key
        }

        return geometries.min(by: { abs($0.value.minY) < abs($1.value.minY) })?.key
    }

    private func computePosition(pageIndex: Int, geometry: PageGeometry) -> PDFReadingPosition {
        let threshold: CGFloat = {
            if scrollViewportHeight > 0 {
                return min(80, max(16, scrollViewportHeight * 0.25))
            }
            return 80
        }()

        let progressFromTop: Double? = {
            guard geometry.height > 0 else { return nil }
            let withinPage = min(max(threshold - geometry.minY, 0), geometry.height)
            return Double(withinPage / geometry.height)
        }()

        let textScrollAnchor: Double? = {
            guard scrollViewportHeight > 0, geometry.height > scrollViewportHeight else { return 0 }
            let scrollable = geometry.height - scrollViewportHeight
            guard scrollable > 0 else { return 0 }
            let offset = min(max(-geometry.minY, 0), scrollable)
            return Double(offset / scrollable)
        }()

        return PDFReadingPosition(
            pageIndex: pageIndex,
            x: nil,
            y: nil,
            progressFromTop: progressFromTop,
            textScrollAnchor: textScrollAnchor
        )
    }

    private func restoreAnchor(for targetIndex: Int) -> UnitPoint {
        guard let livePosition, livePosition.pageIndex == targetIndex else { return .top }

        if let anchor = livePosition.textScrollAnchor {
            return UnitPoint(x: 0.5, y: CGFloat(min(max(anchor, 0), 1)))
        }
        if let progress = livePosition.progressFromTop {
            return UnitPoint(x: 0.5, y: CGFloat(min(max(progress, 0), 1)))
        }

        return .top
    }
}

private struct PageGeometry: Equatable {
    let minY: CGFloat
    let height: CGFloat
}

private struct PageGeometryPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: PageGeometry] = [:]
    static func reduce(value: inout [Int: PageGeometry], nextValue: () -> [Int: PageGeometry]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct PageGeometryReporter: View {
    let index: Int

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: PageGeometryPreferenceKey.self,
                value: [
                    index: PageGeometry(
                        minY: proxy.frame(in: .named("PDFTextScroll")).minY,
                        height: proxy.size.height
                    )
                ]
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
        livePosition: .constant(PDFReadingPosition(pageIndex: 0, x: nil, y: nil, progressFromTop: 0.2, textScrollAnchor: 0.3)),
        onPositionChange: { _ in },
        karaokePageIndex: 0,
        karaokeRange: NSRange(location: 6, length: 5),
        isKaraokeActive: true
    )
}
