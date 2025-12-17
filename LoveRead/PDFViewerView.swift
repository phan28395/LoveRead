import SwiftUI
import PDFKit
import UIKit

struct PDFViewerView: UIViewRepresentable {
    let url: URL
    let initialPosition: PDFReadingPosition
    let onPositionChange: (PDFReadingPosition) -> Void

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.displayMode = .singlePageContinuous
        view.usePageViewController(false)

        context.coordinator.load(url: url, into: view, initialPosition: initialPosition)
        context.coordinator.bind(to: view)

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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPositionChange: onPositionChange)
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.savePositionNow()
        coordinator.teardown()
    }

    final class Coordinator: NSObject {
        fileprivate weak var pdfView: PDFView?
        private let onPositionChange: (PDFReadingPosition) -> Void
        private var loadedURL: URL?
        private var scrollObservation: NSKeyValueObservation?
        private var pendingSaveWorkItem: DispatchWorkItem?

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
            restore(position: initialPosition, in: view, document: document)
        }

        @objc func pageChanged() {
            schedulePositionSave()
        }

        fileprivate func attachScrollObserverIfNeeded() {
            guard scrollObservation == nil, let pdfView else { return }
            guard let scrollView = findScrollView(in: pdfView) else { return }

            scrollObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                self?.schedulePositionSave()
            }
        }

        fileprivate func schedulePositionSave() {
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
                let document = pdfView.document,
                let currentPage = pdfView.currentPage
            else { return }

            let pageIndex = document.index(for: currentPage)
            onPositionChange(PDFReadingPosition(pageIndex: pageIndex, point: pdfView.currentDestination?.point))
        }

        private func restore(position: PDFReadingPosition, in view: PDFView, document: PDFDocument) {
            let clampedIndex = max(0, min(position.pageIndex, max(0, document.pageCount - 1)))
            guard let page = document.page(at: clampedIndex) else { return }

            DispatchQueue.main.async {
                if let point = position.point {
                    let destination = PDFDestination(page: page, at: point)
                    view.go(to: destination)
                } else {
                    view.go(to: page)
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
