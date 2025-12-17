import Foundation
import AVFoundation

#if os(iOS)
import UIKit
#endif

class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    
    private var synthesizer = AVSpeechSynthesizer()
    
    @Published var isSpeaking = false
    @Published var isPaused = false
    
    private let rateDefaultsKey: String
    private let anchorDefaultsKey: String?
    private let textSignatureDefaultsKey: String?

    // PERSISTENCE 1: Speed
    // We modify this so when you change it, it automatically saves to disk
    @Published var rate: Float {
        didSet {
            UserDefaults.standard.set(rate, forKey: rateDefaultsKey)
        }
    }
    
    @Published var currentRange: NSRange = NSRange(location: 0, length: 0)
    
    private var fullText: String = ""
    
    // PERSISTENCE 2: Position
    // We will load this from disk in init()
    private var anchorIndex: Int = 0
    private var currentTextSignature: String?
    
    private var currentBufferOffset: Int = 0
    
    init(rateDefaultsKey: String = "saved_rate", anchorDefaultsKey: String? = "saved_anchor") {
        self.rateDefaultsKey = rateDefaultsKey
        self.anchorDefaultsKey = anchorDefaultsKey
        if let anchorDefaultsKey {
            self.textSignatureDefaultsKey = "\(anchorDefaultsKey)_text_signature"
        } else {
            self.textSignatureDefaultsKey = nil
        }

        // LOAD SAVED DATA
        // If there is no saved rate, default to 0.5
        let savedRate = UserDefaults.standard.float(forKey: rateDefaultsKey)
        self.rate = savedRate == 0 ? 0.5 : savedRate
        
        // Load the last known position
        if let anchorDefaultsKey {
            self.anchorIndex = UserDefaults.standard.integer(forKey: anchorDefaultsKey)
        } else {
            self.anchorIndex = 0
        }
        if let textSignatureDefaultsKey {
            self.currentTextSignature = UserDefaults.standard.string(forKey: textSignatureDefaultsKey)
        }
        
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
        let signature = Self.textSignature(for: text)
        if signature != currentTextSignature {
            anchorIndex = 0
            currentBufferOffset = 0
            currentRange = NSRange(location: 0, length: 0)
            currentTextSignature = signature
            if let textSignatureDefaultsKey {
                UserDefaults.standard.set(signature, forKey: textSignatureDefaultsKey)
            }
            if let anchorDefaultsKey {
                UserDefaults.standard.set(0, forKey: anchorDefaultsKey)
            }
        }
        fullText = text
        
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
        if let anchorDefaultsKey {
            UserDefaults.standard.set(anchorIndex, forKey: anchorDefaultsKey)
        }
        
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
        if let anchorDefaultsKey {
            UserDefaults.standard.set(0, forKey: anchorDefaultsKey)
        }
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
                if let anchorDefaultsKey = self.anchorDefaultsKey {
                    UserDefaults.standard.set(0, forKey: anchorDefaultsKey)
                }
            }
        }
    }

    private static func textSignature(for text: String) -> String {
        let prefix = String(text.prefix(128))
        let suffix = String(text.suffix(128))
        return "\(text.count)|\(prefix)|\(suffix)"
    }
}
