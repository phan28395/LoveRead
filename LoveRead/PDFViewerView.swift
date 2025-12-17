import SwiftUI
import PDFKit
import UIKit

struct PDFViewerView: UIViewRepresentable {
    let url: URL
    let initialPosition: PDFReadingPosition
    let onPositionChange: (PDFReadingPosition) -> Void
    var highlightPageIndex: Int?
    var highlightRange: NSRange?
    var scrollToHighlight: Bool = false

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.displayMode = .singlePageContinuous
        view.usePageViewController(false)

        context.coordinator.load(url: url, into: view, initialPosition: initialPosition)
        context.coordinator.bind(to: view)
        context.coordinator.updateHighlight(
            pageIndex: highlightPageIndex,
            range: highlightRange,
            scrollToVisible: scrollToHighlight
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged),
            name: Notification.Name.PDFViewPageChanged,
            object: view
        )

        DispatchQueue.main.async {
            context.coordinator.attachScrollObserverIfNeeded()
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        context.coordinator.load(url: url, into: uiView, initialPosition: initialPosition)
        context.coordinator.bind(to: uiView)
        context.coordinator.attachScrollObserverIfNeeded()
        context.coordinator.updateHighlight(
            pageIndex: highlightPageIndex,
            range: highlightRange,
            scrollToVisible: scrollToHighlight
        )
        context.coordinator.checkRestoreCompletionIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPositionChange: onPositionChange)
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.flushLastKnownPosition()
        coordinator.teardown()
    }

    final class Coordinator: NSObject {
        fileprivate weak var pdfView: PDFView?
        private let onPositionChange: (PDFReadingPosition) -> Void
        private var loadedURL: URL?
        private var scrollObservation: NSKeyValueObservation?
        private var pendingSaveWorkItem: DispatchWorkItem?
        private var isRestoring = false
        private var lastHighlightSignature: HighlightSignature?
        private var lastKnownPosition: PDFReadingPosition?
        private var desiredRestorePageIndex: Int?

        init(onPositionChange: @escaping (PDFReadingPosition) -> Void) {
            self.onPositionChange = onPositionChange
        }

        fileprivate func bind(to view: PDFView) {
            pdfView = view
        }

        fileprivate func load(url: URL, into view: PDFView, initialPosition: PDFReadingPosition) {
            guard loadedURL != url else { return }
            loadedURL = url

            guard let document = PDFDocument(url: url) else {
                view.document = nil
                return
            }

            view.document = document
            view.layoutDocumentView()
            lastKnownPosition = initialPosition
            isRestoring = true
            desiredRestorePageIndex = max(0, min(initialPosition.pageIndex, max(0, document.pageCount - 1)))
            restore(position: initialPosition, in: view, document: document)
        }

        @objc func pageChanged() {
            if isRestoring, restoreIsComplete() {
                isRestoring = false
                desiredRestorePageIndex = nil
                return
            }
            schedulePositionSave()
        }

        fileprivate func checkRestoreCompletionIfNeeded() {
            if isRestoring, restoreIsComplete() {
                isRestoring = false
                desiredRestorePageIndex = nil
            }
        }

        fileprivate func attachScrollObserverIfNeeded() {
            guard scrollObservation == nil, let pdfView else { return }
            guard let scrollView = findScrollView(in: pdfView) else { return }

            scrollObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self, weak scrollView] _, _ in
                guard let self else { return }
                if self.isRestoring, let scrollView, (scrollView.isTracking || scrollView.isDragging) {
                    self.isRestoring = false
                    self.desiredRestorePageIndex = nil
                }
                self.schedulePositionSave()
            }
        }

        fileprivate func schedulePositionSave() {
            guard !isRestoring else { return }
            pendingSaveWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.savePositionNow()
            }
            pendingSaveWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }

        fileprivate func savePositionNow() {
            guard
                let pdfView,
                let document = pdfView.document
            else { return }

            guard pdfView.window != nil else { return }
            guard pdfView.bounds.width > 1, pdfView.bounds.height > 1 else { return }

            let anchorInsetY = min(80, max(16, pdfView.bounds.height * 0.25))
            let anchorPointInView = CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.minY + anchorInsetY)

            var probePoint = anchorPointInView
            var page = pdfView.page(for: probePoint, nearest: false)
            if page == nil {
                let step: CGFloat = 12
                var y = probePoint.y
                while y > pdfView.bounds.minY {
                    y -= step
                    probePoint = CGPoint(x: probePoint.x, y: y)
                    if let found = pdfView.page(for: probePoint, nearest: false) {
                        page = found
                        break
                    }
                }
            }
            if page == nil {
                page = pdfView.page(for: anchorPointInView, nearest: true) ?? pdfView.currentPage
                probePoint = anchorPointInView
            }

            guard let page else { return }
            let pageIndex = document.index(for: page)

            let pagePoint = pdfView.convert(probePoint, to: page)
            let pageBounds = page.bounds(for: pdfView.displayBox)
            let clampedY = min(max(pagePoint.y, pageBounds.minY), pageBounds.maxY)

            let position = PDFReadingPosition(pageIndex: pageIndex, x: nil, y: Double(clampedY))
            lastKnownPosition = position
            onPositionChange(position)
        }

        private func restoreIsComplete() -> Bool {
            guard
                let desiredRestorePageIndex,
                let pdfView,
                let document = pdfView.document,
                pdfView.window != nil
            else { return false }

            let anchorInsetY = min(80, max(16, pdfView.bounds.height * 0.25))
            let anchorPointInView = CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.minY + anchorInsetY)
            guard let page = pdfView.page(for: anchorPointInView, nearest: true) ?? pdfView.currentPage else { return false }
            return document.index(for: page) == desiredRestorePageIndex
        }

        fileprivate func flushLastKnownPosition() {
            guard let lastKnownPosition else { return }
            onPositionChange(lastKnownPosition)
        }

        fileprivate func updateHighlight(pageIndex: Int?, range: NSRange?, scrollToVisible: Bool) {
            guard let pdfView else { return }
            guard let document = pdfView.document else {
                clearHighlight(in: pdfView)
                return
            }

            guard let pageIndex, let range else {
                clearHighlight(in: pdfView)
                return
            }

            guard pageIndex >= 0, pageIndex < document.pageCount, let page = document.page(at: pageIndex) else {
                clearHighlight(in: pdfView)
                return
            }

            let signature = HighlightSignature(pageIndex: pageIndex, range: range, scrollToVisible: scrollToVisible)
            if signature == lastHighlightSignature { return }
            lastHighlightSignature = signature

            guard let selection = selection(on: page, for: range) else {
                clearHighlight(in: pdfView)
                return
            }

            pdfView.highlightedSelections = [selection]
            if scrollToVisible {
                pdfView.setCurrentSelection(selection, animate: false)
                pdfView.scrollSelectionToVisible(nil)
                pdfView.setCurrentSelection(nil, animate: false)
            } else {
                pdfView.setCurrentSelection(nil, animate: false)
            }
        }

        private func selection(on page: PDFPage, for range: NSRange) -> PDFSelection? {
            guard let pageString = page.string else { return nil }
            let nsString = pageString as NSString
            let maxLength = nsString.length
            guard maxLength > 0 else { return nil }

            var clamped = range
            if clamped.location < 0 { clamped.location = 0 }
            if clamped.location >= maxLength { return nil }
            let end = min(maxLength, clamped.location + max(0, clamped.length))
            clamped.length = max(0, end - clamped.location)
            clamped = trimmedRange(clamped, in: nsString)
            guard clamped.length > 0 else { return nil }

            return page.selection(for: clamped)
        }

        private func trimmedRange(_ range: NSRange, in string: NSString) -> NSRange {
            var lower = range.location
            var upper = range.location + range.length
            let whitespace = CharacterSet.whitespacesAndNewlines

            while lower < upper {
                let scalar = string.character(at: lower)
                let isWhitespace = UnicodeScalar(scalar).map { whitespace.contains($0) } ?? false
                if !isWhitespace { break }
                lower += 1
            }

            while upper > lower {
                let scalar = string.character(at: upper - 1)
                let isWhitespace = UnicodeScalar(scalar).map { whitespace.contains($0) } ?? false
                if !isWhitespace { break }
                upper -= 1
            }

            return NSRange(location: lower, length: max(0, upper - lower))
        }

        private func clearHighlight(in view: PDFView) {
            lastHighlightSignature = nil
            view.highlightedSelections = nil
            view.setCurrentSelection(nil, animate: false)
        }

        private func restore(position: PDFReadingPosition, in view: PDFView, document: PDFDocument) {
            let clampedIndex = max(0, min(position.pageIndex, max(0, document.pageCount - 1)))
            guard let page = document.page(at: clampedIndex) else { return }

            DispatchQueue.main.async {
                if let point = position.destinationPoint(unspecifiedValue: kPDFDestinationUnspecifiedValue) {
                    let destination = PDFDestination(page: page, at: point)
                    view.go(to: destination)
                } else {
                    let pageBounds = page.bounds(for: view.displayBox)
                    let topDestination = PDFDestination(
                        page: page,
                        at: CGPoint(x: kPDFDestinationUnspecifiedValue, y: pageBounds.maxY)
                    )
                    view.go(to: topDestination)
                }
            }
        }

        private func findScrollView(in view: UIView) -> UIScrollView? {
            if let scrollView = view as? UIScrollView { return scrollView }
            for subview in view.subviews {
                if let found = findScrollView(in: subview) { return found }
            }
            return nil
        }

        fileprivate func teardown() {
            pendingSaveWorkItem?.cancel()
            pendingSaveWorkItem = nil

            scrollObservation?.invalidate()
            scrollObservation = nil

            if let pdfView {
                NotificationCenter.default.removeObserver(self, name: Notification.Name.PDFViewPageChanged, object: pdfView)
            }
        }

        deinit {
            teardown()
        }
    }
}

private struct HighlightSignature: Hashable {
    let pageIndex: Int
    let range: NSRange
    let scrollToVisible: Bool
}
