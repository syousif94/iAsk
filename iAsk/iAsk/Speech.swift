//
//  Speech.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/8/23.
//

import Foundation
import AVFoundation

class SpeechQueue: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    
    static let speechSynthesizer = AVSpeechSynthesizer()
    
    private var sentenceQueue: [String]
    @Published var currentSentence: String
    @Published var currentWord: String
    
    override init() {
        
        self.sentenceQueue = []
        self.currentSentence = ""
        self.currentWord = ""
        super.init()
        Self.speechSynthesizer.delegate = self
    }
    
    func cancelSpeech() {
        Self.speechSynthesizer.stopSpeaking(at: .word)
    }
    
    func enqueue(sentence: String) {
        sentenceQueue.append(sentence)
        if !Self.speechSynthesizer.isSpeaking {
            speakNextSentence()
        }
    }
    
    private func speakNextSentence() {
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            let _ = try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.ambient)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print(error)
        }
        
        if let sentence = sentenceQueue.first {
            
            print("speaking:", sentence)
            
            currentSentence = sentence
            let utterance = AVSpeechUtterance(string: sentence)
            
            utterance.rate = utterance.rate * 1.1

            Self.speechSynthesizer.speak(utterance)
            
            sentenceQueue.removeFirst()
            
            speakNextSentence()
        }
    }
    
    // AVSpeechSynthesizerDelegate methods
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speakNextSentence()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let sentence = utterance.speechString
        let range = Range(characterRange, in: sentence)!
        currentWord = String(sentence[range])
    }
}
