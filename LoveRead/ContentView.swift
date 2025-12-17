import SwiftUI

struct ContentView: View {
    @StateObject private var speechManager = SpeechManager()
    @Binding var textInput: String
    
    // Controls if we are typing or listening
    @State private var isReaderMode = false
    
    var body: some View {
        VStack(spacing: 0) {
            
            // Header
            HStack {
                Text("Smart Reader")
                    .font(.headline)
                Spacer()
                // Toggle Button
                Button(isReaderMode ? "Edit Text" : "Done Typing") {
                    // Stop audio when switching modes
                    speechManager.reset()
                    withAnimation {
                        isReaderMode.toggle()
                    }
                }
                .font(.subheadline)
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            
            // --- MAIN CONTENT AREA ---
            ZStack {
                if isReaderMode {
                    // READ MODE (Highlights Text)
                    ScrollView {
                        // This function creates the colored text
                        Text(buildHighlightedString())
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineSpacing(6)
                    }
                } else {
                    // EDIT MODE (Type Text)
                    TextEditor(text: $textInput)
                        .font(.body)
                        .padding()
                        .background(Color.white)
                }
            }
            
            Divider()
            
            // --- CONTROLS ---
            VStack(spacing: 10) {
                // Speed Slider
                HStack {
                    Image(systemName: "tortoise")
                    Slider(value: $speechManager.rate, in: 0.25...0.75)
                    Image(systemName: "hare")
                }
                .padding(.horizontal)
                .foregroundColor(.secondary)
                
                Text("Speed: \(String(format: "%.1f", speechManager.rate * 2))x")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 10)
            
            HStack(spacing: 40) {
                // Reset Button
                Button(action: {
                    speechManager.reset()
                }) {
                    VStack {
                        Image(systemName: "backward.end.fill")
                            .font(.title)
                            .foregroundColor(.red)
                        Text("Reset")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                
                // Play/Pause Button
                Button(action: {
                    // Auto-switch to Reader Mode if user hits Play while editing
                    if !isReaderMode { isReaderMode = true }
                    
                    if speechManager.isSpeaking {
                        speechManager.pauseSpeaking()
                    } else {
                        speechManager.startSpeaking(text: textInput)
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 70, height: 70)
                            .shadow(radius: 4)
                        
                        Image(systemName: speechManager.isSpeaking ? "pause.fill" : "play.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)
            }
            .padding(10)
            .background(Color.gray.opacity(0.05))
        }
        #if os(iOS)
        .onTapGesture {
            hideKeyboard()
        }
        #endif
    }
    
    // MARK: - Helper to Colorize Text
    // This creates the "Karaoke" effect using AttributedString
    func buildHighlightedString() -> AttributedString {
        KaraokeTextBuilder.attributedString(for: textInput, highlightRange: speechManager.currentRange)
    }
}

#if os(iOS)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

#Preview {
    ContentView(textInput: .constant(AppState.defaultReaderText))
}
