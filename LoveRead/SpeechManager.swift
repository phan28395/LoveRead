import Foundation
import AVFoundation

#if os(iOS)
import UIKit
#endif

class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    
    private var synthesizer = AVSpeechSynthesizer()
    
    // UI State
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var rate: Float = 0.5
    
    // TRACKING: The word currently being spoken (for highlighting)
    @Published var currentRange: NSRange = NSRange(location: 0, length: 0)
    
    // Internal Memory
    private var fullText: String = ""
    private var offsetIndex: Int = 0 // Where did we start this specific sentence?
    
    override init() {
        super.init()
        synthesizer.delegate = self
        #if os(iOS)
        setupMobileAudio()
        #endif
    }
    
    #if os(iOS)
    func setupMobileAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }
    #endif
    
    // MARK: - Smart Controls
    
    func startSpeaking(text: String) {
        // If we are starting fresh (new text), reset everything
        if text != fullText {
            fullText = text
            offsetIndex = 0
        }
        
        // If we reached the end previously, reset
        if offsetIndex >= fullText.count {
            offsetIndex = 0
        }
        
        // STOP any current audio so we can apply new settings (Speed/Voice)
        synthesizer.stopSpeaking(at: .immediate)
        
        // Calculate the text to speak (Slice from the bookmark to the end)
        let textToSpeak = String(fullText.dropFirst(offsetIndex))
        
        if textToSpeak.isEmpty { return }
        
        let utterance = AVSpeechUtterance(string: textToSpeak)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = rate
        utterance.volume = 1.0
        
        synthesizer.speak(utterance)
        
        isSpeaking = true
        isPaused = false
    }
    
    func pauseSpeaking() {
        // We use STOP here to allow speed changes.
        // The 'offsetIndex' is already updated by the delegate below.
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = true
    }
    
    func reset() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        offsetIndex = 0
        currentRange = NSRange(location: 0, length: 0)
    }
    
    // MARK: - The "GPS" (Delegate)
    
    // This runs automatically every time the voice speaks a new word
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        
        // IMPORTANT MATH:
        // 'characterRange' is relative to the *snippet* we are currently speaking.
        // 'offsetIndex' is where that snippet started in the *full text*.
        // We add them together to get the "Global Position" for highlighting.
        
        let globalLocation = offsetIndex + characterRange.location
        
        // Update the UI
        DispatchQueue.main.async {
            self.currentRange = NSRange(location: globalLocation, length: characterRange.length)
        }
        
        // Update our bookmark so if we pause NOW, we know where to resume
        // We save the START of the current word as the resume point
        // (If you want to be safer, add characterRange.length to skip this word on resume)
        self.offsetIndex = globalLocation
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            // Only reset if we truly finished the whole text
            if self.offsetIndex >= self.fullText.count - 1 {
                self.isSpeaking = false
                self.isPaused = false
                self.offsetIndex = 0
                self.currentRange = NSRange(location: 0, length: 0)
            }
        }
    }
}
