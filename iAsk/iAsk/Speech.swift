//
//  Speech.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/8/23.
//

import SwiftUI
import AVFoundation
import Speech
import Accelerate

class TranscriptManager: ObservableObject {
    /// the current speech to text
    var transcript: String = ""
    
    var onTranscript: ((_ transcript: String) -> Void)? = nil

    /// whether the mic is recording a user question or not
    @Published var isRecording: Bool = false
    
    /// the volume of the user's speech
    @Published var decibles: CGFloat = -160
    
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer?
    private var timer: Timer?
    
    init() {
        recognizer = SFSpeechRecognizer()
        
        // try to get permissions to listen
//        Task(priority: .background) {
//            do {
//                guard recognizer != nil else {
//                    throw RecognizerError.nilRecognizer
//                }
//                guard await SFSpeechRecognizer.hasAuthorizationToRecognize() else {
//                    throw RecognizerError.notAuthorizedToRecognize
//                }
//                guard await AVAudioSession.sharedInstance().hasPermissionToRecord() else {
//                    throw RecognizerError.notPermittedToRecord
//                }
//            } catch {
//                speakError(error)
//            }
//        }
    }
    
    func resetSpeechToText() {
        isRecording = false
        task?.cancel()
        audioEngine?.stop()
        audioEngine = nil
        request = nil
        task = nil
    }
    
    func transcribe() {

        DispatchQueue(label: "Speech Recognizer Queue", qos: .background).async { [weak self] in
            guard let self = self, let recognizer = self.recognizer, recognizer.isAvailable else {
                self?.speakError(RecognizerError.recognizerIsUnavailable)
                return
            }
            
            DispatchQueue.main.async {
                self.isRecording = true
            }
            
            do {
                let (audioEngine, request) = try self.prepareEngine()
                self.audioEngine = audioEngine
                self.request = request
                
                self.task = recognizer.recognitionTask(with: request) { result, error in
                    let receivedFinalResult = result?.isFinal ?? false
                    let receivedError = error != nil // != nil mean there's error (true)
                    
                    if receivedFinalResult || receivedError {
                        audioEngine.stop()
                        audioEngine.inputNode.removeTap(onBus: 0)
                    }
                    
                    if let result = result, !result.bestTranscription.formattedString.isEmpty {
//                        self.restartSpeechTimer()
                        self.speak(result.bestTranscription.formattedString)
                    }
                }
            } catch {
//                self.resetSpeechToText()
                self.speakError(error)
            }
        }
    }
    
    private func prepareEngine() throws -> (AVAudioEngine, SFSpeechAudioBufferRecognitionRequest) {
        let audioEngine = AVAudioEngine()
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        let inputNode = audioEngine.inputNode
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.processAudioBuffer(buffer)
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        
        return (audioEngine, request)
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        // For simplicity, just use the first channel
        let channelData0 = channelData[0]
        let length = vDSP_Length(buffer.frameLength)

        // root mean square
        var rms: Float = 0.0
        vDSP_rmsqv(channelData0, 1, &rms, length)
        
        let decibles = RMS2dB(rms) // 0 to -160
        
        DispatchQueue.main.async {
            self.decibles = CGFloat(decibles)
        }
    }
    
    private func RMS2dB(_ rms: Float) -> Float {
        guard rms > 0 else { return -160.0 } // -160 dB is effectively silence
        return 20 * log10(rms)
    }
    
    func stopTranscribing() {
        resetSpeechToText()
    }
    
    func restartSpeechTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false, block: { (timer) in
            if self.transcript.isEmpty {
                self.restartSpeechTimer()
                return
            }
            self.stopTranscribing()
        })
    }
    
    private func speak(_ message: String) {
        if isRecording {
            transcript = message
            onTranscript?(transcript)
        }
        
    }
    
    private func speakError(_ error: Error) {
        var errorMessage = ""
        if let error = error as? RecognizerError {
            errorMessage += error.message
        } else {
            errorMessage += error.localizedDescription
        }
        transcript = "<< \(errorMessage) >>"
        onTranscript?(transcript)
    }
    
    enum RecognizerError: Error {
        case nilRecognizer
        case notAuthorizedToRecognize
        case notPermittedToRecord
        case recognizerIsUnavailable
        
        var message: String {
            switch self {
            case .nilRecognizer: return "Can't initialize speech recognizer"
            case .notAuthorizedToRecognize: return "Not authorized to recognize speech"
            case .notPermittedToRecord: return "Not permitted to record audio"
            case .recognizerIsUnavailable: return "Recognizer is unavailable"
            }
        }
    }
}

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
        Self.speechSynthesizer.stopSpeaking(at: .immediate)
        sentenceQueue.removeAll() // Clear the queue to prevent further speaking
    }
    
    func enqueue(sentence: String) {
        sentenceQueue.append(sentence)
        if !Self.speechSynthesizer.isSpeaking {
            speakNextSentence()
        }
    }
    
    private func speakNextSentence() {
        guard !sentenceQueue.isEmpty else { return } // Ensure there is something to speak
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            let _ = try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print(error)
        }
        
        let sentence = sentenceQueue.removeFirst() // Remove the first sentence from the queue
        print("speaking:", sentence)
        
        currentSentence = sentence
        let utterance = AVSpeechUtterance(string: sentence)
        utterance.rate = utterance.rate * 1.05
        
        Self.speechSynthesizer.speak(utterance)
    }
    
    // AVSpeechSynthesizerDelegate methods
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speakNextSentence() // Only call speakNextSentence here after an utterance finishes
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let sentence = utterance.speechString
        let range = Range(characterRange, in: sentence)!
        currentWord = String(sentence[range])
    }
}
