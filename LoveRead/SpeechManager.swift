import Foundation
import AVFoundation

#if os(iOS)
import UIKit
#endif

class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    
    private var synthesizer = AVSpeechSynthesizer()
    
    @Published var isSpeaking = false
    @Published var isPaused = false
    
    // PERSISTENCE 1: Speed
    // We modify this so when you change it, it automatically saves to disk
    @Published var rate: Float {
        didSet {
            UserDefaults.standard.set(rate, forKey: "saved_rate")
        }
    }
    
    @Published var currentRange: NSRange = NSRange(location: 0, length: 0)
    
    private var fullText: String = ""
    
    // PERSISTENCE 2: Position
    // We will load this from disk in init()
    private var anchorIndex: Int = 0
    
    private var currentBufferOffset: Int = 0
    
    override init() {
        // LOAD SAVED DATA
        // If there is no saved rate, default to 0.5
        let savedRate = UserDefaults.standard.float(forKey: "saved_rate")
        self.rate = savedRate == 0 ? 0.5 : savedRate
        
        // Load the last known position
        self.anchorIndex = UserDefaults.standard.integer(forKey: "saved_anchor")
        
        super.init()
        synthesizer.delegate = self
        
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("Audio Error") }
        #endif
    }
    
    func startSpeaking(text: String) {
        // 1. Check if text changed.
        // If the user pasted NEW text, we should reset the position to 0.
        // If it's the SAME text (just reopening app), keep the saved position.
        if text != fullText {
            fullText = text
            // Only reset anchor if the text is actually different
            // (We assume if text length is drastically different, it's new)
            // A simple check:
            if abs(text.count - fullText.count) > 5 {
               anchorIndex = 0
            }
        }
        
        // Safety check for bounds
        if anchorIndex >= fullText.count {
            anchorIndex = 0
        }
        
        synthesizer.stopSpeaking(at: .immediate)
        
        let textToSpeak = String(fullText.dropFirst(anchorIndex))
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
        // Save current spot
        anchorIndex += currentBufferOffset
        currentBufferOffset = 0
        
        // PERSISTENCE 3: Save to Disk immediately
        UserDefaults.standard.set(anchorIndex, forKey: "saved_anchor")
        
        isPaused = true
        isSpeaking = false
        synthesizer.stopSpeaking(at: .immediate)
    }
    
    func reset() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        anchorIndex = 0
        currentBufferOffset = 0
        currentRange = NSRange(location: 0, length: 0)
        
        // Clear saved position
        UserDefaults.standard.set(0, forKey: "saved_anchor")
    }
    
    // MARK: - Delegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        
        let globalLocation = anchorIndex + characterRange.location
        
        DispatchQueue.main.async {
            self.currentRange = NSRange(location: globalLocation, length: characterRange.length)
        }
        
        self.currentBufferOffset = characterRange.location
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if isPaused { return }
        
        let finishedLocation = anchorIndex + utterance.speechString.count
        
        if finishedLocation >= fullText.count - 5 {
            DispatchQueue.main.async {
                self.isSpeaking = false
                self.isPaused = false
                self.anchorIndex = 0
                self.currentBufferOffset = 0
                self.currentRange = NSRange(location: 0, length: 0)
                
                // Clear saved position when finished
                UserDefaults.standard.set(0, forKey: "saved_anchor")
            }
        }
    }
}
