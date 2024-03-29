//
//  Chat.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/1/23.
//

import SwiftUI
import OpenAI
import MarkdownUI
import AVFoundation
import Speech
import Combine
import UIKit
import NanoID
import Blackbird
import Accelerate
import GPTEncoder


let selectChatNotification = NotificationPublisher<ChatRecord>()
let stopListeningNotification = NotificationPublisher<Void>()

@MainActor
class ChatViewModel: ObservableObject {
    
    var currentlyDragging: URL?
    
    var scrollProxy: ScrollViewProxy?
    
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
    
    @AppStorage("showTips") var showTips = true
    
    @AppStorage("introShown") var introShown = false
    
    var proMode = true
    
    var model: Model {
        if proMode {
            return .gpt4_1106_preview
        }
        return .gpt3_5Turbo_1106
    }
    
    @Published var showLimitExceededAlert = false
    
    @Published var showSettings = false
    
    @Published var isWide = false
    
    @Published var messages: [Message] = []
    
    @Published var id: String = ""
    
    /// the current speech to text
    @Published var transcript: String = ""

    /// whether the mic is recording a user question or not
    @Published var isRecording: Bool = false
    /// say the ai answer aloud as it is recieved
    @AppStorage("speakAnswer") var speakAnswer: Bool = false {
        didSet {
            if !speakAnswer {
                speechQueue.cancelSpeech()
            }
            else if let last = messages.last {
                if last.record.role == .assistant,
                   !last.answering,
                   !last.record.isFunctionCall {
                    sentenceSplitter.handleStreamChunk(last.content)
                }
            }
        }
    }
    
    @AppStorage("listenOnLaunch") var listenOnLaunch: Bool = false
    
    /// handles speaking sentences
    @Published var speechQueue = SpeechQueue()
    
    @Published var lastEdited: String? = nil
    
    /// handles the text selection modal
    @Published var isPresentingText: Bool = false
    @Published var presentedText: String = ""
    @Published var codeLanguage: String = ""
    @Published var highlightingReady: Bool = false
    
    @Published var menuShown: Bool = false
    
    @Published var store = StoreViewModel()
    
    @Published var settings = SettingsViewModel()
    
    /// the volume of the user's speech
    @Published var decibles: CGFloat = -160
    
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer?
    private var timer: Timer?
    
    private let sentenceSplitter = StreamSentenceSplitter()
    
    var cancellables = Set<AnyCancellable>()
    
    // set this to true once the first message has been set
    // need to avoid creating the chat initially in case no
    // messages are sent
    private var chatCreated = false
    
    /// generate the the latest chat messages in ai format once per chat call
    var latestAiMessages: [Chat] = []
    
    /// generate the the latest attachments list once per chat call
    var latestAttachments: [Attachment] = []
    
    func resetChat(_ chatId: String? = nil) async {
        
        if let chatId = chatId {
            
            let messages = await Message.loadForChatId(chatId) ?? []
            DispatchQueue.main.async {
                self.id = chatId
                self.transcript = ""
                self.messages = messages
            }
        }
        else {
            let id = ID()
            let uniqueID = id.generate(size: 10)
            
            self.chatCreated = false
            DispatchQueue.main.async {
                self.id = uniqueID
                if self.messages.count > 2, let last = self.messages.last, last.record.role == .user, last.record.messageType == .data, !last.attachments.isEmpty {
                    last.record.chatId = uniqueID
                    self.messages = [last]
                }
                else {
                    self.messages = []
                }
                
            }
            
        }
        
        scrollMessagesList.send(0)
        
        if Application.isCatalyst {
            DispatchQueue.main.async {
                focusInputNotification.send(nil)
            }
        }
    }
    
    init(id: String? = nil) {
        
        recognizer = SFSpeechRecognizer()
        
        if let id = id {
            self.id = id
        }
        else {
            let id = ID()
            let uniqueID = id.generate(size: 10)
            self.id = uniqueID
        }
        
        // try to get permissions to listen
        Task(priority: .background) {
            do {
                guard recognizer != nil else {
                    throw RecognizerError.nilRecognizer
                }
                guard await SFSpeechRecognizer.hasAuthorizationToRecognize() else {
                    throw RecognizerError.notAuthorizedToRecognize
                }
                guard await AVAudioSession.sharedInstance().hasPermissionToRecord() else {
                    throw RecognizerError.notPermittedToRecord
                }
            } catch {
                speakError(error)
            }
        }
        
        setupStopListeningListener()
        
        // stop listening when the keyboard pops up
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { _ in
                self.stopTranscribing()
            }
            .store(in: &cancellables)
        
        // handle new sentences from the response splitter
        sentenceSplitter.sentenceHandler = { sentence in
             self.speechQueue.enqueue(sentence: sentence)
        }
        
        // listen for document imports from the document picker
        setupDocumentImportListener()
        
        print("initial urls", InitialURLs.shared.urls)
        
        if !InitialURLs.shared.urls.isEmpty {
            Task {
                await self.importURLs(urls: InitialURLs.shared.urls)
            }
        }
        
        
    }
    
    func createChatRecord() async {
        let chatRecord = ChatRecord(id: self.id, createdAt: Date())
        try? await chatRecord.write(to: Database.shared.db)
    }
    
//    deinit {
//        resetSpeechToText()
//    }
    
    func shareDialog() {
        let chatName = messages.first(where: { $0.record.messageType == .text })?.content.replacing(" ", with: "-") ?? id
        
        guard let url = Disk.cache.getPath(for: "exports/\(chatName).md") else {
            return
        }
        
        let contentArr = messages.compactMap { $0.md }
        
        if contentArr.isEmpty {
            return
        }
        
        let content = contentArr.joined(separator: "\n\n")
        
        try? content.write(to: url, atomically: true, encoding: .utf8)
        
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        Application.keyWindow?.rootViewController?.present(av, animated: true, completion: nil)
    }
    
    func saveDialog() {
        let chatName = messages.first(where: { $0.record.messageType == .text })?.content.replacing(" ", with: "-") ?? id
        
        guard let url = Disk.cache.getPath(for: "exports/\(chatName).md") else {
            return
        }
        
        let contentArr = messages.compactMap { $0.md }
        
        if contentArr.isEmpty {
            return
        }
        
        let content = contentArr.joined(separator: "\n\n")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        showSaveNotification.send([url])
    }
    
    func resetSpeechToText() {
        
        isRecording = false
        task?.cancel()
        audioEngine?.stop()
        audioEngine = nil
        request = nil
        task = nil
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session. Error: \(error)")
        }
    }
    
    private func setupDocumentImportListener() {
        print("listening for docs")
        importedDocumentNotification.publisher.sink { urls in
            Task {
                await self.importURLs(urls: urls)
            }
        }
        .store(in: &cancellables)
    }
    
    private func setupStopListeningListener() {
        DispatchQueue.main.async {
            stopListeningNotification.publisher.sink { _ in
                self.stopTranscribing()
            }.store(in: &self.cancellables)
        }
        
    }
    
    func importURLs(urls: [URL]) async {
        var appendMessage = true
        let message: Message
        
        if let lastMessage = self.messages.last, lastMessage.record.messageType == .data, lastMessage.record.role == .user {
            message = lastMessage
            appendMessage = false
        }
        else {
            message = Message(chatId: self.id)
        }
        
        for url in urls {
            
            let attachment = await message.attach(url: url)
        
        }
        
        await message.save()
        
        if appendMessage {
            DispatchQueue.main.async { [message] in
                self.messages.append(message)
            }
        }
        
    }
    
    /**
        Begin transcribing audio.
     
        Creates a `SFSpeechRecognitionTask` that transcribes speech to text until you call `stopTranscribing()`.
        The resulting transcription is continuously written to the published `transcript` property.
     */
    func transcribe() {
        
        self.speakAnswer = false
        
        lastEdited = nil
        
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
    
    func send() {
        timer?.invalidate()
        self.stopTranscribing()
        self.streamResponse()
        
    }
    
    func restartSpeechTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false, block: { (timer) in
            if self.transcript.isEmpty {
                self.restartSpeechTimer()
                return
            }
            self.stopTranscribing()
            self.streamResponse()
        })
    }
    
    private func speak(_ message: String) {
        if isRecording {
            transcript = message
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
    }
    
    func endGenerating(messageId: String?) {
        if let id = messageId {
            if let message = messages.first(where: { message in
                return message.record.id == messageId
            }) {
                self.endGenerating(userMessage: message)
            }
        }
        else {
            self.endGenerating(userMessage: nil)
        }
    }
    
    func endGenerating(userMessage: Message?) {
        if let message = userMessage {
            userMessage?.answering = false
            return
        }
        else {
            let activeMessages = self.messages.filter { $0.answering }
            for message in activeMessages {
                message.answering = false
            }
        }
    }
    
    // MARK: Call LLM
    
    
    func callChat(at lastUserMessage: Message? = nil) async {
        
        var chatMessages: [Chat] = proMode ? [
            .init(role: .system, content: """
            You have the ability to read all files (txt, html, office, etc.) and the text in images (png, jpeg, heic), and browse the web.
            Your goal is to accomplish user requests as quickly as possible using the functions available to you while still being fun and friendly in your responses.
            
            Please obey the following rules:
            
            1. Include links to github whenever mentioning software, and include links to websites whenever mentioning websites.
            2. Assume that users will refer to their friends and family (contacts) by nicknames that might be nouns, foriegn names, nonsense words, ex. cat, taco, bri, babe, mom, xi, hala
            3. Collect all of the information you need before calling a function. If an argument is missing, ask a follow up quesiton before calling the function.
            4. DO NOT call convert_media on code. Convert it yourself.
            5. Always included addresses and links for places in the real world if they appear in documents the user has provided.
            6. DO NOT call get_location if the question contains all the required locations. Do not call get_location before creating reminders or calendar events.
            7. You must get either a phone number or email address in addition to a name before creating a contact.
            8. YOU MUST CALL image_ocr on image files before answering questions related to the content of images, like math or science questions. Your default OCR cannot parse fractions, complex equations, diagrams, or maps into text and cause you to give the wrong answer.
            9. DO NOT CALL image_ocr when the user is asking to create contacts, reminders, or calendar event.
            
            
            You should call functions consecutively if you need current information. Do not make up information on current events without first calling the search function.
            
            Example #1:
            user: whats the weather like?
            assistant (you): get_location()
            function: [{"location": "Malibu, CA" }]
            assistant (you): search(query: "weather in Malibu, CA")
            function: [{"html": "Example html for you to read an extract the weather conditions" }]
            assistant (you): The weather in Malibu is... (fill this in)
            
            Lastly, the current date is \(Date().formatted())
            """)
        ] : [
            .init(role: .user, content: """
            You have the ability to read all files (txt, html, office, etc.) and the text in images (png, jpeg, heic), browse the web, and send text and email messages.
            Your goal is to accomplish my requests as quickly as possible using the functions available to you while still being fun and friendly in your responses.
            
            Please obey the following rules:
            
            1. Include links to github whenever mentioning software, and include links to websites whenever mentioning websites.
            2. If you are asked to ask someone a question, respond by calling the sms function.
            3. Assume that I will refer to my friends and family (contacts) by nicknames that might be nouns, foriegn names, nonsense words, ex. cat, taco, bri, babe, mom, xi, hala
            4. Collect all of the information you need before calling a function. If an argument is missing, ask a follow up quesiton before calling the function.
            5. DO NOT call convert_media on code. Convert it yourself.
            6. Be brief in your responses. It it ok to leave out warnings and extraneous information.
            7. Always included addresses and links for places in the real world if they appear in documents the user has provided.
            
            You should only call search_contacts when someone explicitly asks for contact information.
            If someone asks you to send a message or email, do not call search_contacts, just use the contact's name in the respective sms/email function.
            
            Example #1:
            user: text my mom that she needs to download my new app
            assistant (you): sms(contact: "mom", message: "Hi mom, I love you and miss you. Can you please download my new app?")
            
            Example #2:
            user: ask cat whats up
            assistant (you): sms(name: "cat", message: "whats up")
            
            You should call functions consecutively if you need current information. Do not make up information on current events without first calling the search function.
            
            Example #1:
            user: whats the weather like?
            assistant (you): get_location()
            function: [{"location": "Malibu, CA" }]
            assistant (you): search(query: "weather in Malibu, CA")
            function: [{"html": "Example html for you to read an extract the weather conditions" }]
            assistant (you): The weather in Malibu is... (fill this in)
            
            Lastly, the current date is \(Date().formatted())
            """),
            .init(role: .assistant, content: """
            No problem! What can I assist you with?
            """)
        ]
        
        let aiMessage: Message
        
        var lastUserMessage = lastUserMessage
        
        if let message = lastUserMessage {
            
            let messageIndex = messages.firstIndex { $0.record.id == message.record.id }
            let nextIndex = messageIndex! + 1
            
            if nextIndex < messages.count {
                aiMessage = messages[nextIndex]
            }
            else {
                let aiMessageRecord = MessageRecord(
                    chatId: self.id,
                    createdAt: Date(),
                    content: "",
                    role: .assistant,
                    messageType: .text
                )
                
                aiMessage = Message(record: aiMessageRecord)
                
                aiMessage.answering = true
                
                DispatchQueue.main.async {
                    self.messages.append(aiMessage)
                }
                
            }
            
            chatMessages.append(contentsOf: messages[0...messageIndex!].compactMap { $0.ai })
            
            Task { [message] in
                await message.save()
            }
        }
        else {
            
            lastUserMessage = messages.reversed().first(where: { $0.record.role == .user })

            chatMessages.append(contentsOf: messages.compactMap { $0.ai })
            
            let aiMessageRecord = MessageRecord(
                chatId: self.id,
                createdAt: Date(),
                content: "",
                role: .assistant,
                messageType: .text
            )
            
            aiMessage = Message(record: aiMessageRecord)
            
            aiMessage.answering = true
            
            DispatchQueue.main.async {
                self.messages.append(aiMessage)
            }
        }
        
        DispatchQueue.main.async { [lastUserMessage] in
            lastUserMessage?.answering = true
        }
        
        self.latestAiMessages = chatMessages
        
        self.latestAttachments = messages.reversed().flatMap { $0.attachments }
        
        let functions = getFunctions()
        
        let query = ChatQuery(model: model, messages: chatMessages, functions: functions, temperature: 0.0)
        
        let call = FunctionCallResponse()
        
        let openAI = OpenAI(apiToken: OPEN_AI_KEY)
        
        let textPublisher = PassthroughSubject<String, Never>()
        
        var cancellables = Set<AnyCancellable>()
        
        let throttledPublisher = textPublisher
            .throttle(for: .milliseconds(16), scheduler: RunLoop.main, latest: true)
        
        guard let detector = TextDetector() else {
            return
        }
        
        let latexToMarkdown = LaTeXImageMarkdownConverter(imageGenerator: LaTeXImageGenerator())
        
        throttledPublisher
            .receive(on: DispatchQueue.main)
            .sink { text in
                
                let replacedText = latexToMarkdown.convertLatexToMarkdown(in: text)
                
                let mutableText = detector.replaceAddresses(in: replacedText)

                aiMessage.content = mutableText as String
                
                let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
                impactFeedbackGenerator.impactOccurred()
            }
            .store(in: &cancellables)
        
        var answer = ""
        
        var wasSpeaking = speakAnswer
        
        do {
            
            for try await result in openAI.chatsStream(query: query) {
                if let answering = lastUserMessage?.answering, !answering {
                    return
                }
                
                if let text = result.choices[0].delta.content {
                    
                    answer += text
                    textPublisher.send(answer)
                    if speakAnswer {
                        let textToSpeak = wasSpeaking ? text : answer
                        sentenceSplitter.handleStreamChunk(textToSpeak)
                    }
                    wasSpeaking = speakAnswer
                    
//                    DispatchQueue.main.async { [answer] in
//                        aiMessage.content = answer
//                    }
                }
                else if let functionCall = result.choices[0].delta.functionCall {
                    
                    let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedbackGenerator.impactOccurred()
                    
                    if let name = functionCall.name {
                        #if DEBUG
                        print("function call chunk", name)
                        #endif
                        call.name += name
                    }
                    if let arguments = functionCall.arguments {
                        #if DEBUG
                        print("function arg chunk", arguments)
                        #endif
                        
                        call.arguments += arguments
                        
                        if call.nameCompleted {
                            DispatchQueue.main.async {
                                aiMessage.functionLog += arguments
                                aiMessage.content += arguments
                            }
                        }
                        
                        if !call.nameCompleted, let function = FunctionCall(rawValue: call.name) {
                            
                            call.nameCompleted = true
                            
                            DispatchQueue.main.async {
                                aiMessage.functionType = function
                                aiMessage.functionLog += """
                                
                                ```json
                                
                                """
                            }
                            
                        }
                    }
                }
            }
        }
        catch {
            return
        }
        
        if let answering = lastUserMessage?.answering, !answering {
            return
        }
        
        if let function = FunctionCall(rawValue: call.name) {
            
            let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
            impactFeedbackGenerator.impactOccurred()
            
            aiMessage.record.functionCallName = call.name
            aiMessage.record.functionCallArgs = call.arguments
            
            DispatchQueue.main.async {
                aiMessage.functionLog += """
                
                ```
                
                """
            }

            switch function {
            case .getUserLocation:
                Task { [call] in
                    guard let location = try? await Location.shared.get() else {
                        DispatchQueue.main.async {
                            aiMessage.answering = false
                            aiMessage.content = ""
                        }
                        return
                    }
                    print("getting location succeeded",location)
                    
                    guard let geocode = try? await Location.shared.geocode(coordinate: location.coordinate),
                          let cityAndState = geocode.locality else {
                        DispatchQueue.main.async {
                            aiMessage.answering = false
                            aiMessage.content = ""
                        }
                        return
                    }
                    
                    print("getting geocode succeeded", cityAndState)
                    
                    DispatchQueue.main.async {
                        let functionMessageRecord = MessageRecord(chatId: self.id, createdAt: Date(), content: cityAndState, role: .function, messageType: .text, functionCallName: call.name)
                        let functionMessage = Message(record: functionMessageRecord)
                        aiMessage.content = cityAndState
                        aiMessage.answering = false
                        self.messages.append(functionMessage)
                        self.endGenerating(userMessage: lastUserMessage)
                        let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedbackGenerator.impactOccurred()
                        Task {
                            async let saveAiMessage: () = aiMessage.save()
                            
                            async let saveFunctionMessage: () = functionMessage.save()
                            
                            await saveAiMessage
                            await saveFunctionMessage
                        }
                        Task {
                            await self.callChat()
                        }
                        
                    }
                    
                }
            case .convertMedia:
                do {
                    let args = try call.toArgs(ConvertMediaArgs.self)
                    Task { [call] in
                        
                        let functionMessageRecord = MessageRecord(chatId: self.id, createdAt: Date(), content: "", role: .function, messageType: .data, functionCallName: call.name)
                        
                        let functionMessage = Message(record: functionMessageRecord)
                        
                        DispatchQueue.main.async {
                            self.messages.append(functionMessage)
                        }
                        
                        await withThrowingTaskGroup(of: Void.self) { group in
                            for args in args.items {
                                let config = args.toFFmpegConfig(for: self.latestAttachments)
                                if let config = config {
                                    DispatchQueue.main.async {
                                        aiMessage.functionLog += """
                                        
                                        ```
                                        ffmpeg \(config.command)
                                        ```
                                        
                                        """
                                    }
                                }
                                group.addTask {
                                    let outputURL = try await convertFile(config: config)
                                    let _ = await functionMessage.attach(url: outputURL)
                                    DispatchQueue.main.async {
                                        functionMessage.content += "\(outputURL.absoluteString)\n"
                                    }
                                }
                                
                            }
                        }
                            
                        DispatchQueue.main.async {
                            aiMessage.functionLog += """
                            Conversion Complete
                            """
                            aiMessage.answering = false
//                                    self.messages.append(functionMessage)
                            self.endGenerating(userMessage: lastUserMessage)
                            Task {
                                async let saveAiMessage: () = aiMessage.save()
                                async let saveFunctionMessage: () = functionMessage.save()
                                await saveAiMessage
                                await saveFunctionMessage
                            }
                        }
                        
                        
                    }
                } catch {
                    print("Failed to decode JSON: \(error)")
                    self.endGenerating(userMessage: lastUserMessage)
                }
            case .search:
                do {
                    let args = try call.toArgs(SearchArgs.self)
                    Task {
                        let results = await Browser.shared.search(query: args.query)

                        DispatchQueue.main.async {
                            aiMessage.functionLog += "Obtained \(results.links.count) results"
                        }
                        
                        if let firstLink = results.links.first {
                            DispatchQueue.main.async {
                                aiMessage.content = "Loading \(firstLink.absoluteString)"
                                aiMessage.functionLog += "\n\(aiMessage.content)"
                            }
                            
                            let html = await Browser.shared.fetchHTML(from: firstLink)
                            
                            if let html = html {
                                let text = extractText(html: html)
                                
                                var functionOutput = """
                                [
                                    {
                                        "url":"\(firstLink.absoluteString)",
                                        "html":"\(text ?? "")"
                                    }
                                """
                                
                                if let answer = results.answerText, !answer.isEmpty {
                                    functionOutput += """
                                    ,
                                    {
                                        "url":"google results",
                                        "html":"\(answer)"
                                    }
                                    """
                                }
                                
                                functionOutput += "]"
                                
                                let functionMessageRecord = MessageRecord(chatId: self.id, createdAt: Date(), content: functionOutput, role: .function, messageType: .text, functionCallName: call.name)
                                
                                let functionMessage = Message(record: functionMessageRecord)
                                
                                DispatchQueue.main.async {
                                    self.messages.append(functionMessage)
//                                        self.endGenerating(userMessage: lastUserMessage)
                                    aiMessage.answering = false
                                    let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
                                    impactFeedbackGenerator.impactOccurred()
                                    Task {
                                        async let saveAi: () = aiMessage.save()
                                        async let saveFn: () = functionMessage.save()
                                        async let callChat: () = self.callChat()
                                        await saveAi
                                        await saveFn
                                        await callChat
                                    }
                                }
                                
                                
                            }
                            
                        }
                    }
                } catch {
                    print("Failed to decode JSON: \(error)")
                    self.endGenerating(userMessage: lastUserMessage)
                }
            case .searchContacts:
                do {
                    let args = try call.toArgs(SearchContactsArgs.self)
                    print(args)
                    DispatchQueue.main.async {
                        
                        aiMessage.functionLog += "Searching contacts: \(args.name) (\(args.contactType.rawValue))"

                        Task {
                            let choices = await ContactManager.shared.getChoices(query: args.name, contactType: args.contactType)
                            print(choices)
                            if choices.isEmpty {
                                
                            }
                            else {
                                let choicesMessageRecord = MessageRecord(chatId: self.id, createdAt: Date(), content: "", role: .assistant, messageType: .select)
                                let choiceMessage = Message(record: choicesMessageRecord)
                                choiceMessage.choices = .contacts(choices: choices)
                                DispatchQueue.main.async {
                                    self.messages.append(choiceMessage)
                                }
                            }
                            self.endGenerating(userMessage: lastUserMessage)
                        }
                        
                        Task {
                            await aiMessage.save()
                        }
                    }
                } catch {
                    print("Failed to decode JSON: \(error)")
                }
            case .createNewContact:
                do {
                    let args = try call.toArgs(CreateNewContactArgs.self)
                    
                    if let contact = await ContactManager.shared.createContact(from: args) {
                        print("created contact")
                        
                        try ContactManager.shared.save(contact: contact)
                        
                        aiMessage.systemIdentifier = contact.identifier
                    }
                    
                    
                } catch {
                    print("Failed to decode JSON for new contact: \(error)")
                }
                
                aiMessage.answering = false
                
                endGenerating(userMessage: lastUserMessage)
                
                Task {
                    await aiMessage.save()
                }

            case .createReminder:
                do {
                    let args = try call.toArgs(CreateReminderArgs.self)
                    
                    if let dueDate = Events.getDate(args.dueDate) {
                        let reminder = Events.shared.createReminder(title: args.title, notes: args.notes, date: dueDate)
                        await Events.shared.insertReminder(reminder: reminder)
                    }
                } catch {
                    
                }
                aiMessage.answering = false
                
                endGenerating(userMessage: lastUserMessage)
                
                Task {
                    await aiMessage.save()
                }
            case .readFiles:
                do {
                    let args = try call.toArgs(ReadFilesArgs.self)
                    let files = args.files
                    
                    let functionMessageRecord = MessageRecord(chatId: self.id, createdAt: Date(), content: "", role: .function, messageType: .text, functionCallName: call.name)
                    
                    let functionMessage = Message(record: functionMessageRecord)
                    
                    Task {
                        
                        let texts = files.compactMap { filePath -> String? in
                            
                            guard let attachment = self.latestAttachments.first(where: { a in

                                if a.dataRecord.dataType == .url, let url = a.url, let path = getDownloadURL(for: url) {
                                    let name = path.lastPathComponent
                                    let isTheOne = name == filePath

                                    return isTheOne
                                }

                                let filenameMatch = a.dataRecord.name == filePath && a.hasText
                                if filenameMatch {
                                    return true
                                }

                                return false
                            }) else {
                                return nil
                            }
                            
                            let encoder = GPTEncoder()
                            
                            if let text = attachment.readFile() {
                                
                                let encoded = encoder.encode(text: text)
                                
                                print("read file", filePath, "estimated tokens", encoded.count)
                                
                                return """
                                file_path:
                                \(filePath)
                                text:
                                \(text)
                                """
                            }
                            
                            return nil
                        }
                        
                        functionMessage.content = texts.joined(separator: "\n")
                        
                        DispatchQueue.main.async {
                            aiMessage.answering = false
                            self.messages.append(functionMessage)
                            let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedbackGenerator.impactOccurred()
                            Task {
                                async let saveAiMessage: () = aiMessage.save()
                                
                                async let saveFunctionMessage: () = functionMessage.save()
                                
                                await saveAiMessage
                                
                                await saveFunctionMessage
                                
                                print("calling chat again")
                                
                                await self.callChat()
                            }
                        }
                    }
                }
                catch {
                    print("Failed to decode JSON: \(error)")
                    self.endGenerating(userMessage: lastUserMessage)
                }
            case .createCalendarEvent:
                do {
                    let args = try call.toArgs(CreateCalendarEventArgs.self)
                    
                    if let event = Events.shared.createEvent(args: args) {
                        
                        print("event generated", event)
                        
                        let id = await Events.shared.insertEvent(event: event)
                        
                        print("event saved", id)
                        
                        aiMessage.systemIdentifier = id
                    }
                    DispatchQueue.main.async {
                        aiMessage.answering = false
                        let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedbackGenerator.impactOccurred()
                        Task {
                            async let saveAiMessage: () = aiMessage.save()
                            
                            await saveAiMessage
                        }
                    }
                    
                    self.endGenerating(userMessage: lastUserMessage)
                }
                catch {
                    print("Failed to decode JSON: \(error)")
                    self.endGenerating(userMessage: lastUserMessage)
                }
            case .getCalendar:
                do {
                    let args = try call.toArgs(GetCalendarArgs.self)
                    
                }
                catch {
                    print("Failed to decode JSON: \(error)")
                    
                }
                aiMessage.answering = false
                Task {
                    await aiMessage.save()
                }
                self.endGenerating(userMessage: lastUserMessage)
            case .imageOCR:
                print("reading images")
                
                guard let args = try? call.toArgs(ImageOCRArgs.self) else {
                    return
                }
                let files = args.files
                let images = files.compactMap { filePath -> (UIImage?, String)? in
                    
                    var filePath = filePath
                    
                    if filePath.contains("file_path:") {
                        filePath = filePath.replacingOccurrences(of: "file_path:", with: "")
                    }
                    if filePath.contains("/"), let lastComponent = filePath.split(separator: "/").last {
                        filePath = String(lastComponent)
                    }
                    
                    filePath = filePath.removingPercentEncoding ?? filePath
                    
                    filePath = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    guard let attachment = self.latestAttachments.first(where: { a in

                        if a.dataRecord.dataType == .url, let url = a.url, let path = getDownloadURL(for: url) {
                            let name = path.lastPathComponent
                            let isTheOne = name == filePath

                            return isTheOne
                        }

                        let filenameMatch = a.dataRecord.name == filePath && a.hasText
                        if filenameMatch {
                            return true
                        }

                        return false
                    }) else {
                        return nil
                    }
                    
                    var text = """
                    file_path: \(filePath)
                    apple_ocr:
                    \(attachment.readFile() ?? "")
                    """
                    
                    return (UIImage(contentsOfFile: attachment.localURL!.path), text)
                }
                
                if !images.isEmpty, let question = lastUserMessage?.content {
                    let textPublisher = PassthroughSubject<String, Never>()
                    
                    var cancellables = Set<AnyCancellable>()
                    
                    let throttledPublisher = textPublisher
                        .throttle(for: .milliseconds(16), scheduler: RunLoop.main, latest: true)
                    
                    let nextMessage = Message(record: .init(chatId: self.id, createdAt: Date(), content:  "", role: .assistant, messageType: .text))
                    self.messages.append(nextMessage)
                    
                    throttledPublisher
                        .receive(on: DispatchQueue.main)
                        .sink { text in
                            
                            let replacedText = latexToMarkdown.convertLatexToMarkdown(in: text)
                            
                            let mutableText = detector.replaceAddresses(in: replacedText)

                            nextMessage.content = mutableText as String
                            
                            let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedbackGenerator.impactOccurred()
                        }
                        .store(in: &cancellables)
                    
                    
                    
                    var answer = ""
                    
                    var questionText = ""
                    
                    
                    
                    questionText += question
                    
                    questionText += "\nhere is the text from Apple's ocr software"
                    
                    for image in images {
                        questionText += "\n\(image.1)"
                    }
                    
                    questionText += "\nYou do not need to redact anything. Please include all names. Never regurgitate the text from the Apple OCR back as a field."
                    
                    do {
                        for try await result in await callImageChat(images: images.map { $0.0! }, question: questionText) {
                            
                            if let text = result.choices[0].delta.content {
                                if aiMessage.answering {
                                    aiMessage.answering = false
                                }
                                
                                answer += text
                                textPublisher.send(answer)
                                if speakAnswer {
                                    sentenceSplitter.handleStreamChunk(text)
                                }
                            }
                        }
                    }
                    catch {
                        
                    }
                    
                    let latexReplaced = latexToMarkdown.convertLatexToMarkdown(in: answer)
                    let mutableText = detector.replaceAddresses(in: latexReplaced)
                    nextMessage.content = mutableText as String
                    Task {
                        async let saveAImessage: () = aiMessage.save()
                        async let saveNextMessage: () = nextMessage.save()
                        await saveAImessage
                        await saveNextMessage
                    }
                }
                
                self.endGenerating(userMessage: lastUserMessage)
            case .sms:
                break
            }
            
        }
        else {
            self.endGenerating(userMessage: lastUserMessage)
            let latexReplaced = latexToMarkdown.convertLatexToMarkdown(in: answer)
            let mutableText = detector.replaceAddresses(in: latexReplaced)
            
            DispatchQueue.main.async {
                aiMessage.content = mutableText as String
                Task {
                    await aiMessage.save()
                }
            }
            
//            guard error == nil else {
//                print(error)
//                return
//            }
        }
    }
    
    func streamResponse() {
        self.resetSpeechToText()
        
        if !store.hasPurchasedMonthly {
            showLimitExceededAlert = true
            return
        }
        
        if !chatCreated {
            chatCreated = true
            Task {
                await createChatRecord()
            }
        }
        
        if let lastEdited = self.lastEdited,
           let lastEditedMessageIndex = messages.firstIndex(where: { message in
               message.record.id == lastEdited
           }) {
            let lastEditedMessage = messages[lastEditedMessageIndex]
            let text = lastEditedMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return
            }
            let nextIndex = lastEditedMessageIndex + 1
            let nextMessage: Message? = nextIndex < messages.count ? messages[nextIndex] : nil
            
            DispatchQueue.main.async {
                lastEditedMessage.content = text
                lastEditedMessage.record.model = self.model
                nextMessage?.content = ""
                nextMessage?.functionLog = ""
                nextMessage?.functionType = nil
                Task {
                    await self.callChat(at: lastEditedMessage)
                }
                
                Task {
                    await lastEditedMessage.save()
                }
            }
        }
        else {
            
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !text.isEmpty else {
                return
            }
            
            let userMessageRecord = MessageRecord(
                chatId: self.id,
                createdAt: Date(),
                content: text,
                role: .user,
                messageType: .text,
                model: self.model
            )
            
            let userMessage = Message(record: userMessageRecord)
            
            userMessage.answering = true
            
            DispatchQueue.main.async {
                self.lastEdited = userMessage.record.id
                self.messages.append(userMessage)
                self.transcript = ""
                Task {
                    await self.callChat()
                }
                
                Task { [userMessage] in
                    await userMessage.save()
                }
            }
        }
    }
}



func searchContacts(args: SearchContactsArgs) {
    
}

func searchLocalContacts(query: String) {
    
}

func searchGoogleContacts(query: String) {
    
}


extension SFSpeechRecognizer {
    static func hasAuthorizationToRecognize() async -> Bool {
        await withCheckedContinuation { continuation in
            requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

extension AVAudioSession {
    func hasPermissionToRecord() async -> Bool {
        await withCheckedContinuation { continuation in
            requestRecordPermission { authorized in
                continuation.resume(returning: authorized)
            }
        }
    }
}

class StreamSentenceSplitter {
    private var currentSentence: String = ""
    private let sentenceTerminators: [Character] = [".", "!", "?"]
    private let abbreviations: Set<String> = ["st", "mr", "mrs", "dr", "ms", "jr", "sr"]
    
    var sentenceHandler: ((String) -> Void)?
    
    func handleStreamChunk(_ newValue: String) {
        for character in newValue {
            if sentenceTerminators.contains(character) {
                if canTerminateSentence(with: character) {
                    currentSentence.append(character)
                    if let handler = sentenceHandler {
                        handler(currentSentence)
                    }
                    currentSentence = ""
                } else {
                    currentSentence.append(character)
                }
            } else {
                currentSentence.append(character)
            }
        }
    }
    
    private func canTerminateSentence(with terminator: Character) -> Bool {
        let trimmedSentence = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lastWord = trimmedSentence.split(separator: " ").last {
            let lastWordString = String(lastWord).lowercased()
            if abbreviations.contains(lastWordString) {
                return false
            }
            if let lastCharacter = lastWordString.last, lastCharacter.isNumber {
                return false
            }
        }
        return true
    }
}
