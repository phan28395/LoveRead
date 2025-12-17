import SwiftUI

#if os(iOS)
import UIKit
#endif

struct ExtractedTextView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    let openInReader: () -> Void

    @State private var showingShare = false

    init(text: String, openInReader: @escaping () -> Void) {
        _text = State(initialValue: text)
        self.openInReader = openInReader
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body)
                .padding(.horizontal)
                .navigationTitle("Converted Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Copy") {
                            #if os(iOS)
                            UIPasteboard.general.string = text
                            #endif
                        }
                        Button("Share") { showingShare = true }
                        Button("Open in Reader") {
                            openInReader()
                            dismiss()
                        }
                    }
                }
                .sheet(isPresented: $showingShare) {
                    #if os(iOS)
                    ShareSheet(items: [text])
                    #else
                    Text(text)
                        .padding()
                    #endif
                }
        }
    }
}
