import SwiftUI

struct SpeechControlBar: View {
    @ObservedObject var speechManager: SpeechManager
    var isBusy: Bool = false
    var onPlayPause: () -> Void
    var onReset: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "tortoise")
                Slider(value: $speechManager.rate, in: 0.25...0.75)
                Image(systemName: "hare")
            }
            .foregroundColor(.secondary)

            Text("Speed: \(String(format: "%.1f", speechManager.rate * 2))x")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 40) {
                Button(action: onReset) {
                    VStack {
                        Image(systemName: "backward.end.fill")
                            .font(.title)
                            .foregroundColor(.red)
                        Text("Reset")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)

                Button(action: onPlayPause) {
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
                .disabled(isBusy)
                .opacity(isBusy ? 0.5 : 1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.05))
    }
}

#Preview {
    SpeechControlBar(
        speechManager: SpeechManager(anchorDefaultsKey: nil),
        onPlayPause: {},
        onReset: {}
    )
}

