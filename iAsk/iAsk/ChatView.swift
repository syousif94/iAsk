//
//  ChatView.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/8/23.
//

import Foundation
import SwiftUI
import OpenAI
import MarkdownUI
import AVFoundation
import Speech
import Combine
import UIKit
import Splash
import CodeEditor
import WrappingHStack
import AlertToast

struct ChatViewWrapper: View {
    let chat: ChatViewModel
    
    @StateObject var alerts: AlertViewModel = AlertViewModel()
    
    var body: some View {
        ChatView()
            .environmentObject(chat)
            .environmentObject(alerts)
            .toast(isPresenting: $alerts.show){
                alerts.alertToast
            }
    }
}

class AlertViewModel: ObservableObject{
    @Published var show = false
    @Published var alertToast: AlertToast = AlertToast(type: .regular, title: "SOME TITLE") {
        didSet{
            withAnimation {
                show.toggle()
            }
        }
    }
}

let focusInputNotification = NotificationPublisher<String?>()

struct QuestionInput: View {
    var messageId: String? = nil
    @Binding var transcript: String
    @FocusState var isFocused: Bool
    
    @EnvironmentObject var chat: ChatViewModel
    
    @Binding var isAnswering: Bool
    
    var body: some View {
        let isEmptySpeech = transcript.isEmpty

        let placeholder = "What can I help you with?"
        
        TextField(placeholder, text: $transcript, axis: .vertical)
            .foregroundColor(isEmptySpeech ? Color.gray : Color.primary)
            .padding()
            .padding(.trailing, 40)
            .font(.custom("HelveticaNeue-Bold", size: 18))
            .focused($isFocused)
            .overlay(alignment: .topTrailing) {
                AnsweringView(isAnimating: $isAnswering)
                    .padding()
            }
            .onReceive(Just(transcript)) { newValue in
                let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
                let matches = detector?.matches(in: newValue, options: [], range: NSMakeRange(0, newValue.utf16.count))

                var urls = [URL]()
                for match in matches ?? [] {
                    if let url = match.url {
                        urls.append(url)
                        print("URL Detected: \(url)")
                        transcript = transcript.replacingOccurrences(of: url.absoluteString, with: "")
                    }
                }
                
                if !urls.isEmpty {
                    Task {
                        await chat.importURLs(urls: urls)
                    }
                }
            }
            .onChange(of: isFocused) { newValue in
                if newValue {
                    DispatchQueue.main.async {
                        chat.lastEdited = messageId
                    }
                }
            }
            .onReceive(focusInputNotification.publisher) { id in
                if messageId == id {
                    isFocused = true
                }
            }
    }
}

let scrollMessagesList = NotificationPublisher<CGFloat>()

struct ChatView: View {
    @EnvironmentObject var chat: ChatViewModel
    
    @StateObject var keyboardObserver = KeyboardObserver()
    
    @FocusState var isFocused: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
    let keyboardManager = KeyboardManager()
        
    @State private var keyboardHeight: CGFloat = 0
    
    @State var showCamera = false
    
    @State var showPhotos = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            
                            ForEach(chat.messages, id: \.record.id) { message in
                                MessageView(message: message, functionType: message.functionType, answering: message.answering)
                            }
                            
                            QuestionInput(transcript: $chat.transcript, isFocused: _isFocused, isAnswering: .constant(false))
                                .onAppear {
                                    if Application.isCatalyst {
                                        isFocused = true
                                    }
                                }
                                

                            Button(action: {
                                if (chat.menuShown) {
                                    chat.menuShown = false
                                    return
                                }
                                else if !Application.isCatalyst, isFocused {
                                    UIApplication.shared.endEditing()
                                }
                                else if !Application.isCatalyst || !isFocused {
                                    isFocused.toggle()
                                }
                                
                            }) {
                                Text("")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .frame(height: geometry.size.height * 0.7)
                        }
                        .id("top")
                        .frame(idealWidth: geometry.size.width, maxHeight: .infinity, alignment: .top)
                        
                        GeometryReader { contentGeometry in
                            Button(action: {
                                if (chat.menuShown) {
                                    chat.menuShown = false
                                    return
                                }
                                else if !Application.isCatalyst, isFocused {
                                    UIApplication.shared.endEditing()
                                }
                                else if !Application.isCatalyst || !isFocused {
                                    isFocused.toggle()
                                }
                            }) {
                                Text("")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .frame(minHeight: geometry.size.height + geometry.safeAreaInsets.top + 10 + geometry.safeAreaInsets.bottom - contentGeometry.frame(in: .global).minY, maxHeight: .infinity)
                            .offset(x: 0, y: -10)
                            .id("scrollBottom")
                        }
                        
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear {
                        chat.scrollProxy = scrollProxy
                    }
                }
                
                
                // MARK: RECORD BUTTON
                
                VStack {
                    Spacer()
                        RecordButton(isExpanded: $chat.isRecording, showSendButton: true, circleRadius: 32, onRecord: {
                            if !chat.isRecording {
                                withAnimation {
                                    chat.transcribe()
                                }
                            }
                        }, onPause: {
                            if chat.isRecording {
                                withAnimation {
                                    chat.stopTranscribing()
                                }
                            }
                        }, onSend: {
                            if chat.isRecording {
                                withAnimation {
                                    chat.streamResponse()
                                }
                            }
                        })
                        
                }
                .padding(.bottom, geometry.safeAreaInsets.bottom == 0 ? 20 : 0)
                
                // MARK: ADD BUTTON
                
                VStack {
                    Spacer()
                    HStack {

                        Button(action: {
                            chat.speakAnswer.toggle()
                        }, label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .tint(chat.speakAnswer ? chat.proMode ? .orange : .blue : .gray)
                                .frame(height: 22)
                                .padding(17)
                                .animation(Animation.linear, value: chat.proMode)
                        })
                        .buttonStyle(BorderlessButtonStyle())
                        .background(colorScheme == .dark ?
                                    Color(red: 1, green: 1, blue: 1, opacity: 0.1) :
                                    Color(red: 0, green: 0, blue: 0, opacity: 0.05)
                        )
                        .clipShape(Circle())
                        
                        Spacer()
                        
                        AddButton {
                            Image(systemName: "plus")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 26)
                                .padding(15)
                                .tint(chat.proMode ? .orange : .blue)
                                .animation(Animation.linear, value: chat.proMode)
                        }
                        .opacity(keyboardObserver.isKeyboardVisible ? 0 : 1)
                        
                        // MARK: ADD BUTTON END
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 2)
                        
                }
                .padding(.bottom, geometry.safeAreaInsets.bottom == 0 ? 20 : 0)
                
                // MARK: INPUT BAR
                
                VStack {
                    Spacer()
                    InputBar()
                }
                .padding(.bottom, keyboardHeight > 0 ? keyboardHeight - geometry.safeAreaInsets.bottom : 0)
                .onAppear {
                    keyboardManager.observeKeyboardChanges { height, animation in
                        self.keyboardHeight = height
                    }
                }
            }
            .background(
                colorScheme == .dark
                ? Color(hex: "#333333")
                : Color(hex: "#ffffff")
            )
            .sheet(isPresented: $chat.isPresentingText, content: {
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 0) {
                        GeometryReader { geometry in
                            CodeEditor(source: chat.presentedText, language: CodeEditor.Language(rawValue: chat.codeLanguage), theme: colorScheme == .dark ? CodeEditor.ThemeName(rawValue: "monokai") : CodeEditor.ThemeName(rawValue: "xcode"))
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            
                        }
                    }
                    .padding(.top, 30)

                    HStack {
                        Spacer()
                        if Application.isCatalyst {
                            Button("Done") {
                                chat.isPresentingText.toggle()
                            }
                            .padding()
                        }
                    }
                    
                    VStack {
                        Spacer()
                        HStack {
                            Button("Select All") {
                            }
                            .padding()
                            Spacer()
                            Button("Copy") {
                            }
                            .padding()
                            Button("Save") {
                            }
                            .padding()
                        }
                    }
                    

                }.background(Color(hex: colorScheme == .dark ? "#272822" : "#ffffff", alpha: 1))
            })
            
        }
    }
}

struct InputBar: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    @StateObject var keyboardObserver = KeyboardObserver()
    
    @EnvironmentObject var chat: ChatViewModel
    
    var bg: SwiftUI.Color {
        return colorScheme == .dark ?
              Color(red: 1, green: 1, blue: 1, opacity: 0.1) :
              Color(red: 0, green: 0, blue: 0, opacity: 0.05)
    }
    
    var body: some View {
        HStack {
            AddButton(bgPadding: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 24))
                    .padding()
                    .tint(chat.proMode ? .orange : .blue)
                    .animation(Animation.linear, value: chat.proMode)
            }
            .padding(4)
            .opacity(keyboardObserver.isKeyboardVisible ? 1 : 0)
            
            InputMicButton()
                .background {
                    Circle()
                        .fill(bg)
                        .padding(4)
                }
                .opacity(keyboardObserver.isKeyboardVisible ? 1 : 0)
                .padding(4)
            
            Spacer()
            
            Button(action: {
                UIApplication.shared.endEditing()
                chat.send()
            }) {
                Image(systemName: "play.fill")
                    .tint(.green)
                                .font(.system(size: 24))
                                .padding()
            }
            .background {
                Circle()
                    .fill(bg)
                    .padding(4)
            }
            .padding(4)
            .opacity(keyboardObserver.isKeyboardVisible ? 1 : 0)
            
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

struct InputMicButton: View {
    @State var micHeight: CGFloat = 0
    @State var pauseHeight: CGFloat = 0
    @State var height: CGFloat = 0
    
    @EnvironmentObject var chat: ChatViewModel
    
    var body: some View {
        Button(action: {
            if !chat.isRecording {
                withAnimation {
                    chat.transcribe()
                }
            }
            else {
                withAnimation {
                    chat.stopTranscribing()
                }
            }
        }) {
            ZStack {
                Image(systemName: "mic.fill")
                    .tint(chat.proMode ? .orange : .blue)
                    .font(.system(size: 24))
                    .padding()
                    .opacity(chat.isRecording ? 0 : 1)
                if chat.isRecording {
                    VStack {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 27))
                            .foregroundColor(.orange)
                            .background(
                                GeometryReader { geometry in
                                    Color.clear
                                        .onAppear {
                                            print("pause height", geometry.size.height)
                                            micHeight = geometry.size.height
                                        }
                                }
                            )
                    }
                    .frame(height: micHeight, alignment: .bottom)
                    .overlay {
                        VStack {
                            HStack(alignment: .bottom) {
                                HStack(alignment: .bottom) {
                                    Image(systemName: "pause.fill")
                                        .font(.system(size: 27))
                                        .foregroundColor(.black)
                                        .opacity(0.2)
                                }
                                .frame(height: height, alignment: .bottom)
                                .clipped()
                            }
                            .frame(height: micHeight, alignment: .bottom)
                            .clipped()
                        }
                        .frame(height: micHeight, alignment: .bottom)
                    }
                }
            }
            
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        print("mic height", geometry.size.height)
                        micHeight = geometry.size.height
                    }
            }
        )
        .onReceive(chat.$decibles, perform: { newValue in
            self.height = max(0, computeHeight(decibles: newValue, radius: micHeight))
        })
    }
    
    // Compute height based on dBValue
    func computeHeight(decibles: CGFloat, radius: CGFloat) -> CGFloat {
        let normalizedValue = (decibles + 160) / 160
        let expo = pow(normalizedValue, 2)
        return expo * radius
    }
}

struct SplashCodeSyntaxHighlighter: CodeSyntaxHighlighter {
  private let syntaxHighlighter: SyntaxHighlighter<TextOutputFormat>

  init(theme: Splash.Theme) {
    self.syntaxHighlighter = SyntaxHighlighter(format: TextOutputFormat(theme: theme))
  }

  func highlightCode(_ content: String, language: String?) -> Text {

      return self.syntaxHighlighter.highlight(content)
  }
}

extension CodeSyntaxHighlighter where Self == SplashCodeSyntaxHighlighter {
  static func splash(theme: Splash.Theme) -> Self {
    SplashCodeSyntaxHighlighter(theme: theme)
  }
}

struct TextOutputFormat: OutputFormat {
    private let theme: Splash.Theme

    init(theme: Splash.Theme) {
    self.theme = theme
  }

  func makeBuilder() -> Builder {
    Builder(theme: self.theme)
  }
}

extension TextOutputFormat {
  struct Builder: OutputBuilder {
      private let theme: Splash.Theme
    private var accumulatedText: [Text]

      fileprivate init(theme: Splash.Theme) {
      self.theme = theme
      self.accumulatedText = []
    }

    mutating func addToken(_ token: String, ofType type: TokenType) {
      let color = self.theme.tokenColors[type] ?? self.theme.plainTextColor
      self.accumulatedText.append(Text(token).foregroundColor(.init(uiColor: color)))
    }

    mutating func addPlainText(_ text: String) {
      self.accumulatedText.append(
        Text(text).foregroundColor(.init(uiColor: self.theme.plainTextColor))
      )
    }

    mutating func addWhitespace(_ whitespace: String) {
      self.accumulatedText.append(Text(whitespace))
    }

    func build() -> Text {
      self.accumulatedText.reduce(Text(""), +)
    }
  }
}

struct MessageView: View {
    
    @StateObject var message: Message
    
    @FocusState var isFocused: Bool
    
    @Environment(\.colorScheme) var colorScheme

    @EnvironmentObject var chat: ChatViewModel
    
    @State var functionType: FunctionCall?
    
    @State var answering: Bool
    
    var isPad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad || Application.isCatalyst
    }
    
    var markdownView: some View {
        Markdown(message.content)
            .padding(.horizontal)
            .padding(.bottom)
            .frame(alignment: .topLeading)
            .multilineTextAlignment(.leading)
            .markdownCodeSyntaxHighlighter(.splash(theme: self.theme))
            .markdownBlockStyle(\.paragraph, body: { configuration in
                VStack {
                    configuration.label
                        .relativeLineSpacing(.em( isPad ? 0.25 : 0.08))
                        
                }
            })
            .markdownBlockStyle(\.codeBlock, body: { configuration in
                MarkdownCodeView(message: message, configuration: configuration, isFocused: _isFocused, showCode: $chat.isPresentingText, selectedCode: $chat.presentedText, selectedLanguage: $chat.codeLanguage)
                    .padding(.top)
                    .padding(.bottom)
            })
            
            .simultaneousGesture(TapGesture().onEnded({
                UIApplication.shared.endEditing()
            }))
            .contextMenu {
                Button("Copy", role: .none) {

                }
            }
    }
    
    var logView: some View {
        Markdown(message.functionLog)
            .padding()
            .frame(alignment: .topLeading)
            .multilineTextAlignment(.leading)
            .markdownCodeSyntaxHighlighter(.splash(theme: self.theme))
            .markdownBlockStyle(\.paragraph, body: { configuration in
                VStack {
                    configuration.label
                        .relativeLineSpacing(.em( isPad ? 0.25 : 0.08))
                        
                }
            })
            .markdownBlockStyle(\.codeBlock, body: { configuration in
                MarkdownCodeView(message: message, configuration: configuration, isFocused: _isFocused, showCode: $chat.isPresentingText, selectedCode: $chat.presentedText, selectedLanguage: $chat.codeLanguage)
            })
            
            .simultaneousGesture(TapGesture().onEnded({
                UIApplication.shared.endEditing()
            }))
            .contextMenu {
                Button("Copy", role: .none) {

                }
            }
    }
    
    var body: some View {
 
            if message.record.messageType == .data {
                DataMessageView(attachments: $message.attachments, message: message)
                    .padding(.horizontal)
                    .padding(.top)
            }
            
            if message.record.role == .user && message.record.messageType == .text {
                UserMessageView(messageId: message.record.id, transcript: $message.content, answering: $message.answering, isFocused: _isFocused)
            }
            
            if message.record.role == .assistant {
                Group {
                    if functionType != nil {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text(functionType!.rawValue)
                                    .font(.caption)
                                    .padding(.horizontal)
                                    .padding(.vertical, 4)
                                Spacer()
                            }
                            .background(Color(hex: "#000000", alpha: 0.3))
                            .clipShape(RoundedCornersShape(corners: [.topLeft, .topRight], radius: 8))
                            ScrollViewReader { proxy in
                                ScrollView {
                                    logView
                                        .id("log")
                                }
                                .background(Color(hex: "#000000", alpha: 0.1))
                                .clipShape(RoundedCornersShape(corners: [.bottomLeft, .bottomRight], radius: 8))
                                .frame(maxWidth: .infinity, maxHeight: 90)
                                .onChange(of: message.functionLog) { newValue in
                                    proxy.scrollTo("log", anchor: .bottom)
                                }
                                .onAppear {
                                    proxy.scrollTo("log", anchor: .bottom)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    markdownView
                }
                .onChange(of: message.answering, perform: { newValue in
                    print("answering changed", newValue)
                    self.answering = newValue
                })
                .onChange(of: message.functionType, perform: { newValue in
                    print("function type changed", newValue)
                    self.functionType = newValue
                })
                
                
            }
        }
}

struct MarkdownCodeView: View {
    var message: Message
    
    @FocusState var isFocused: Bool
    
    @Environment(\.colorScheme) var colorScheme

    @Binding var showCode: Bool
    @Binding var selectedCode: String
    @Binding var selectedLanguage: String
    var configuration: CodeBlockConfiguration
    
    @EnvironmentObject var alerts: AlertViewModel
    @EnvironmentObject var chat: ChatViewModel
    
    init(message: Message, configuration: CodeBlockConfiguration, isFocused: FocusState<Bool>, showCode: Binding<Bool>, selectedCode: Binding<String>, selectedLanguage: Binding<String>) {
        self.message = message
        self._isFocused = isFocused
        self._showCode = showCode
        self._selectedCode = selectedCode
        self._selectedLanguage = selectedLanguage
        self.configuration = configuration
    }
    
    var isPad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad || Application.isCatalyst
    }
    
    var body: some View {
        innerView
    }
    
    var innerView: some View {

        VStack(alignment: .leading) {
            ScrollView(.horizontal, showsIndicators: false) {
                if isPad {
                    configuration.label
                          .relativeLineSpacing(.em(0.25))
                          .padding()
                }
                else {
                    configuration.label
                          .relativeLineSpacing(.em(0.25))
                          .markdownTextStyle {
                              FontSize(14)
                          }
                          .padding()
                }
            }
            .background(Color(hex: "#000000", alpha: 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .markdownMargin(top: .em(0.8), bottom: .em(0.8))
            .onTapGesture {
                selectedLanguage = configuration.language ?? ""
                selectedCode = configuration.content
                showCode.toggle()
                print("tap gesture completed", showCode)
            }
            .onDrag {
                let selectedCode = configuration.content
                var lang = configuration.language
                if lang == nil || lang!.isEmpty {
                    lang = "md"
                }
                guard let url = try? selectedCode.toCache(ext: lang!), let provider = NSItemProvider(contentsOf: url) else {
                    return NSItemProvider()
                }
                chat.currentlyDragging = url
                provider.suggestedName = url.lastPathComponent
                return provider
            }
            .contextMenu {
                Button("Edit") {
                    
                    DispatchQueue.main.async {
                        selectedLanguage = configuration.language ?? ""
                        selectedCode = configuration.content
                        showCode.toggle()
                    }
                    
                }
                Button("Copy") {
                    let selectedCode = configuration.content
                    copyToClipboard(text: selectedCode)
                    alerts.alertToast = AlertToast(displayMode: .hud, type: .systemImage("checkmark.circle.fill", .green), title: "Copied")
                }
                Button("Save") {
                    var selectedCode = configuration.content
                    var lang = configuration.language
                    if lang == nil || lang!.isEmpty {
                        lang = "md"
                    }
                    if let url = try? selectedCode.toCache(ext: lang!) {
                        showSaveNotification.send([url])
                    }
                }
            }
        }
        
        
    }

}

struct FunctionCodeView: View {
    var body: some View {
        HStack {
            Text("Working")
                .foregroundStyle(.white)
                .padding()
            ProgressView()
                .controlSize(.small)
                .padding()
        }
        .background(.green)
        .cornerRadius(12)
        .clipped()
    }
}

private extension MessageView {
    var theme: Splash.Theme {
        switch colorScheme {
        case .dark:
            return .wwdc17(withFont: .init(size: 16))
        default:
            return .sunset(withFont: .init(size: 16))
        }
    }
}

// 2. DataMessageView
struct DataMessageView: View {
    @Binding var attachments: [Attachment]
    var message: Message

    var body: some View {
        WrappingHStack($attachments, id: \.self, alignment: .leading, lineSpacing: 10) { attachment in
            AttachmentView(message: message, attachment: attachment)
        }
        .frame(
            maxHeight: .infinity)
    }
}

struct UserMessageView: View {
    var messageId: String
    @Binding var transcript: String
    @Binding var answering: Bool
    @FocusState var isFocused: Bool

    var body: some View {
        QuestionInput(messageId: messageId, transcript: $transcript, isFocused: _isFocused, isAnswering: $answering)
    }
}

struct AttachmentPreview: View {
    let message: Message
    @Binding var attachment: Attachment
    @Binding var sideLength: CGFloat
    @State var generating = false

    var body: some View {
        ZStack {
            if let image = attachment.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: sideLength, height: sideLength * 1.2)
                    .clipped()
            }
            else if let url = attachment.url, let text = extractText(url: url) {
                Text(text)
                    .font(
                        .system(size: 5)
                    )
                    .frame(width: sideLength, height: sideLength * 1.2)
                    .clipped()
            }
            if generating {
                ProgressView()
                    .frame(width: sideLength, height: sideLength * 1.2)
            }
        }
        .onReceive(attachment.$generatingPreview) { newValue in
            self.generating = newValue
        }
    }
}

struct AttachmentView: View {
    let message: Message
    @Binding var attachment: Attachment
    @State var status = ""
    
    @State var sideLength: CGFloat = 140

    init(message: Message, attachment: Binding<Attachment>) {
        self.message = message
        self._attachment = attachment
    }
    
    var innerBody: some View {
        ZStack {
            AttachmentPreview(message: message, attachment: $attachment, sideLength: $sideLength)
            
            VStack(alignment: .leading) {
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                    if !status.isEmpty {
                        HStack {
                            Text(status)
                                .font(
                                    .caption
                                )
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.top, 2)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    HStack {
                        Text(attachment.dataRecord.name)
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.bottom, 4)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    
                }
                .padding(.horizontal, 4)
                .frame(width: sideLength, height: sideLength * 0.75)
                .background(
                    LinearGradient(gradient: Gradient(colors: [Color(hex: "#000000", alpha: 0), Color(hex: "#000000", alpha: 0.7)]), startPoint: .top, endPoint: .bottom)
                )
                .onReceive(attachment.$status) { newValue in
                    self.status = newValue
                }
            }
            .frame(width: sideLength, height: sideLength * 1.2)
            
        }
        .frame(width: sideLength)
        .clipped()
        .background(Color(hex: "#000000", alpha: 0.1))
        .cornerRadius(12)
        .contextMenu {
            Button {
                attachment.open()
            } label: {
                Label("Open", systemImage: "square.and.arrow.down")
            }
            Button {
                attachment.saveDialog()
            } label: {
                Label("Save to File", systemImage: "square.and.arrow.down")
            }
            Button {
                attachment.shareDialog()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                Task {
                    await message.detach(attachment: attachment)
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
            Button {
                
                if let url = attachment.url {
                    ImageCache.delete(url)
                    attachment.generatePreviewImage()
                    
                    if !url.isFileURL {
                        Task {
                            try? await download(url: url)
                        }
                    }
                }
                
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .onDrag {
            guard let url = attachment.url, let provider = NSItemProvider(contentsOf: url) else {
                return NSItemProvider()
            }
            provider.suggestedName = attachment.dataRecord.name
            return provider
        }
        .onAppear {
            if attachment.previewImage == nil, attachment.hasPreview {
                attachment.generatePreviewImage()
            }
        }
    }
    
    var body: some View {
        if message.record.role == .function {
            VStack {
                innerBody
            }
            .padding(.bottom)
        }
        else {
            innerBody
        }
    }
}

struct AnsweringView: View {
    @Binding var isAnimating: Bool
    @State var opacity: Double = 1

    var body: some View {
        if isAnimating {
            VStack(spacing: 4) {
                ForEach(0..<3) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<2) { column in
                            Circle()
                                .foregroundColor(.blue)
                                .frame(width: 3, height: 3)
                                .opacity(opacity)
                                .animation(Animation.linear(duration: 0.3).repeatForever().delay(Double(row * 2 + column) * 0.2), value: opacity)
                        }
                    }
                }
            }
            .onTapGesture {
                print("cancel message")
            }
            .onAppear {
                opacity = 0
            }
        }
    }
}
