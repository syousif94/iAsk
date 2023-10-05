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


let selectChatNotification = NotificationPublisher<ChatRecord>()
let stopListeningNotification = NotificationPublisher<Void>()

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
    
    @AppStorage("proMode") var proMode: Bool = false
    
    var model: Model {
        if proMode {
            return .gpt4
        }
        return .gpt3_5Turbo
    }
    
    @Published var messages: [Message] = []
    
    @Published var id: String = ""
    
    /// the current speech to text
    @Published var transcript: String = ""

    /// whether the mic is recording a user question or not
    @Published var isRecording: Bool = false
    /// say the ai answer aloud as it is recieved
    @Published var speakAnswer: Bool = false
    
    /// handles speaking sentences
    @Published var speechQueue = SpeechQueue()
    
    @Published var lastEdited: String? = nil
    
    /// handles the text selection modal
    @Published var isPresentingText: Bool = false
    @Published var presentedText: String = ""
    @Published var codeLanguage: String = ""
    @Published var highlightingReady: Bool = false
    
    @Published var menuShown: Bool = false
    
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
                self.messages = []
            }
            
        }
        
        scrollMessagesList.send(0)
        
        if Application.isCatalyst {
            focusInputNotification.send(nil)
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
        // FIXME: periods in numbers and maybe commas
        sentenceSplitter.sentenceHandler = { sentence in
            // self.speechQueue.enqueue(sentence: sentence)
        }
        
        // listen for document imports from the document picker
        setupDocumentImportListener()
        
    }
    
    func createChatRecord() async {
        let chatRecord = ChatRecord(id: self.id, createdAt: Date())
        try? await chatRecord.write(to: Database.shared.db)
    }
    
    deinit {
        resetSpeechToText()
    }
    
    func shareDialog() {
        guard let url = Disk.cache.getPath(for: "exports/\(id).md") else {
            return
        }
        let contentArr = messages.compactMap { $0.md }
        
        if contentArr.isEmpty {
            return
        }
        
        let content = contentArr.joined(separator: "\n\n")
        
        try? content.write(to: url, atomically: true, encoding: .utf8)
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.windows.first?.rootViewController?.present(av, animated: true, completion: nil)
    }
    
    func saveDialog() {
        guard let url = Disk.cache.getPath(for: "exports/\(id).md") else {
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
    
    func endGenerating(userMessage: Message?) {
        guard let userMessage = userMessage else {
            return
        }
        DispatchQueue.main.async {
            userMessage.answering = false
        }
    }
    
    // MARK: Call LLM
    
    func callChat(at lastUserMessage: Message? = nil) async {
        
        var chatMessages: [Chat] = [
            .init(role: .system, content: """
            You are a genius personal assistant. You have the following guidelines:
            1. NEVER TRUNCATE CODE!!
            2. Include links to github whenever mentioning software, and include links to websites whenever mentioning websites.
            3. Always attempt to rewrite code in other languages. Give it your best effort.
            """)
        ]
        
        let aiMessage: Message
        
        var lastUserMessage = lastUserMessage
        
        DispatchQueue.main.async { [lastUserMessage] in
            lastUserMessage?.answering = true
        }
        
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
            
            chatMessages.append(contentsOf: messages[0...messageIndex!].map { $0.ai })
            
            Task { [message] in
                await message.save()
            }
        }
        else {
            
            lastUserMessage = messages.last
            
            chatMessages.append(contentsOf: messages.map { $0.ai })
            
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
        
        self.latestAiMessages = chatMessages
        
        self.latestAttachments = messages.reversed().flatMap { $0.attachments }.filter { attachment in
            return attachment.hasText
        }
        
//        if let text = await getTextForChat(chatModel: self), !text.isEmpty, let message = chatMessages.last?.content {
//            
//            let lastIndex = chatMessages.count - 1
//            
//            chatMessages[lastIndex] = .init(role: .user, content: """
//            Use the following context to complete this request: \(message)
//            
//            <CONTEXT>
//            
//            \(text)
//            
//            """)
//        }
        
        let functions = getFunctions()
        
        let query = ChatQuery(model: model, messages: chatMessages, functions: functions, temperature: 0.0)
        
        let call = FunctionCallResponse()
        
        let openAI = OpenAI(apiToken: OPEN_AI_KEY)
        
        openAI.chatsStream(query: query) { partialResult in
            switch partialResult {
            case .success(let result):
                if let text = result.choices[0].delta.content {
                    DispatchQueue.main.async {
                        self.sentenceSplitter.handleStreamChunk(text)
                        aiMessage.content += text
                    }
                }
                else if let functionCall = result.choices[0].delta.functionCall {
                    
                    if let name = functionCall.name {
                        call.name += name
                    }
                    if let arguments = functionCall.arguments {
                        call.arguments += arguments
                        
                        if call.nameCompleted {
                            DispatchQueue.main.async {
                                aiMessage.functionLog += arguments
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
            case .failure(let error):
                print(error)
            }
        } completion: { [aiMessage] error in
            if let function = FunctionCall(rawValue: call.name) {
                
                aiMessage.record.functionCallName = call.name
                aiMessage.record.functionCallArgs = call.arguments
                
                DispatchQueue.main.async {
                    aiMessage.functionLog += """
                    
                    ```
                    
                    """
                }

                switch function {
                case .getUserLocation:
                    print("get_user_location")
                    Task { [call] in
                        guard let location = try? await Location.shared.get() else {
                            DispatchQueue.main.async {
                                aiMessage.content = "Sorry, I failed to get your location."
                            }
                            return
                        }
                        print("getting location succeeded",location)
                        
                        guard let geocode = try? await Location.shared.geocode(coordinate: location.coordinate),
                              let cityAndState = geocode.locality else {
                            DispatchQueue.main.async {
                                aiMessage.content = "Sorry, I failed to get your location."
                            }
                            return
                        }
                        
                        print("getting geocode succeeded", cityAndState)
                        
                        DispatchQueue.main.async {
                            let functionMessageRecord = MessageRecord(chatId: self.id, createdAt: Date(), content: cityAndState, role: .function, messageType: .text, functionCallName: call.name)
                            let functionMessage = Message(record: functionMessageRecord)
                            aiMessage.content = "Location: \(cityAndState)"
                            self.messages.append(functionMessage)
                            self.endGenerating(userMessage: lastUserMessage)
                            Task {
                                async let saveAiMessage = aiMessage.save()
                                
                                async let saveFunctionMessage = functionMessage.save()
                                
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
                                    async let saveAiMessage = aiMessage.save()
                                    async let saveFunctionMessage = functionMessage.save()
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
                        print(args)
                        DispatchQueue.main.async {
                            aiMessage.functionLog += "\nSearching: \(args.query)"
                            
                            
                            
                            self.endGenerating(userMessage: lastUserMessage)
                            Task {
                                await aiMessage.save()
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
                            aiMessage.content = "Searching contacts: \(args.name) (\(args.contactType.rawValue))"
                            self.endGenerating(userMessage: lastUserMessage)
                            Task {
                                await aiMessage.save()
                            }
                        }
                        Task {
                            if let json = try? await Google.shared.searchContacts(query: args.name) {
                                print(json)
                            }
                        }
                    } catch {
                        print("Failed to decode JSON: \(error)")
                    }
                case .searchDocuments:
                    do {
                        let args = try call.toArgs(SearchDocumentsArgs.self)
                    }
                    catch {
                        print("Failed to decode JSON: \(error)")
                    }
                case .python:
                    do {
                        let args = try call.toArgs(PythonArgs.self)
                        DispatchQueue.main.async {
                            aiMessage.content += """
                            
                            ```python
                            \(args.script)
                            ```
                            
                            """
                        }
                    }
                    catch {
                        print("Failed to decode JSON: \(error)")
                    }
                case .summarizeDocuments:
                    do {
                        let args = try call.toArgs(SummarizeDocumentsArgs.self)
                        let urls = args.files.compactMap { filePath -> URL? in
                            if let attachment = self.latestAttachments.first(where: { a in
                                a.dataRecord.name == filePath
                            }) {
                                return attachment.url
                            }
                            return URL(string: filePath)
                        }
                        guard urls.count > 0 else {
                            print("No valid files to summarize")
                            return
                        }
                        Task { [lastUserMessage] in
                            for url in urls {
                                let text = extractText(url: url)
                                if let text = text {
                                    DispatchQueue.main.async {
                                        aiMessage.content += "\n\n"
                                    }
                                    let summary = await summarize(text) { token in
                                        DispatchQueue.main.async {
                                            aiMessage.content += token
                                        }
                                    }
                                    
                                }
                            }
                            DispatchQueue.main.async {
                                aiMessage.answering = false
                            }
                            self.endGenerating(userMessage: lastUserMessage)
                            async let saveAiMessage = aiMessage.save()
                            await saveAiMessage
                            
                        }
                        
                    }
                    catch {
                        print("Failed to decode JSON: \(error)")
                    }
                case .writeFiles:
                    do {
                        let args = try call.toArgs(WriteFilesArgs.self)
                    }
                    catch {
                        print("Failed to decode JSON: \(error)")
                        self.endGenerating(userMessage: lastUserMessage)
                    }
                case .sms:
                    do {
                        let args = try call.toArgs(SMSArgs.self)
                    }
                    catch {
                        print("Failed to decode JSON: \(error)")
                        self.endGenerating(userMessage: lastUserMessage)
                    }
                case .call:
                    do {
                        let args = try call.toArgs(CallArgs.self)
                    }
                    catch {
                        print("Failed to decode JSON: \(error)")
                        self.endGenerating(userMessage: lastUserMessage)
                    }
                case .readFiles:
                    do {
                        let args = try call.toArgs(ReadFilesArgs.self)
                        let files = args.files
                        
                        let functionMessageRecord = MessageRecord(chatId: self.id, createdAt: Date(), content: "", role: .function, messageType: .text, functionCallName: call.name)
                        
                        let functionMessage = Message(record: functionMessageRecord)
                        
                        Task { [lastUserMessage] in
                            
                            let urls = files.compactMap { filePath -> URL? in
                                if let attachment = self.latestAttachments.first(where: { a in
                                    a.dataRecord.name == filePath
                                }) {
                                    return attachment.url
                                }
                                return URL(string: filePath)
                            }
                            
                            let text = await readFiles(urls: urls) {
                                return await getTerms(for: self)
                            }
                            
                            if let text = text {
                                functionMessage.content = text
                            }
                            
                            self.messages.append(functionMessage)
                            
                            self.endGenerating(userMessage: lastUserMessage)
                            
                            async let saveAiMessage = aiMessage.save()
                            
                            async let saveFunctionMessage = functionMessage.save()
                            
                            await saveAiMessage
                            
                            await saveFunctionMessage
                            
                            await self.callChat()
                            
                        }
                        
                        
                    }
                    catch {
                        print("Failed to decode JSON: \(error)")
                        self.endGenerating(userMessage: lastUserMessage)
                    }
                }
                
            }
            else {
                self.endGenerating(userMessage: lastUserMessage)
                Task {
                    await aiMessage.save()
                }
                guard error == nil else {
                    print(error)
                    return
                }
            }
        }
    }
    
    func streamResponse() {
        self.resetSpeechToText()
        
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
            let nextIndex = lastEditedMessageIndex + 1
            let nextMessage: Message? = nextIndex < messages.count ? messages[nextIndex] : nil
            
            DispatchQueue.main.async {
                nextMessage?.content = ""
                Task {
                    await self.callChat(at: lastEditedMessage)
                }
                
                Task {
                    await lastEditedMessage.save()
                }
            }
        }
        else {
            let userMessageRecord = MessageRecord(
                chatId: self.id,
                createdAt: Date(),
                content: transcript,
                role: .user,
                messageType: .text
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
    
    var sentenceHandler: ((String) -> Void)?
    
    func handleStreamChunk(_ newValue: String) {
        for character in newValue {
            if sentenceTerminators.contains(character) {
                currentSentence.append(character)
                if let handler = sentenceHandler {
                    handler(currentSentence)
                }
                currentSentence = ""
            } else {
                currentSentence.append(character)
            }
        }
    }
}

