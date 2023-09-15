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

struct ChatViewWrapper: View {
    let chat: ChatViewModel
    var body: some View {
        ChatView()
            .environmentObject(chat)
            
    }
}

struct QuestionInput: View {
    var messageId: String? = nil
    @Binding var transcript: String
    @FocusState var isFocused: Bool
    
    @EnvironmentObject var chat: ChatViewModel
    
    @State var isAnswering = false
    
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
                    .onChange(of: chat.isAnswering) { newValue in
                        if let id = messageId {
                            isAnswering = newValue.contains(id)
                        }
                        
                    }
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
                    chat.lastEdited = messageId
                    stopListeningNotification.send(())
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
    
    @State var menuShown = false
    
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
                                MessageView(message: message)
                            }
                            
                            QuestionInput(transcript: $chat.transcript, isFocused: _isFocused)
                                

                            Button(action: {
                                if (menuShown) {
                                    menuShown = false
                                    return
                                }
                                else if isFocused {
                                    UIApplication.shared.endEditing()
                                }
                                else {
                                    isFocused.toggle()
                                }
                                
                            }) {
                                Text("")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .frame(height: 390)
                        }
                        .id("top")
                        .frame(idealWidth: geometry.size.width, maxHeight: .infinity, alignment: .top)
                        
                        GeometryReader { contentGeometry in
                            Button(action: {
                                if (menuShown) {
                                    menuShown = false
                                    return
                                }
                                else if isFocused {
                                    UIApplication.shared.endEditing()
                                }
                                else {
                                    isFocused.toggle()
                                }
                            }) {
                                Text("")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .frame(minHeight: geometry.size.height + geometry.safeAreaInsets.top + 10 + geometry.safeAreaInsets.bottom - contentGeometry.frame(in: .global).minY, maxHeight: .infinity)
                            .offset(x: 0, y: -10)
                        }
                        
                    }
                    .onAppear {
                        chat.scrollProxy = scrollProxy
                    }
                }
                
                
                // MARK: RECORD BUTTON
                
                VStack {
                    Spacer()
                    RecordButton(isExpanded: $chat.isRecording, circleRadius: 32, onRecord: {
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
                        Spacer()
                        Menu() {
                            Button("New Chat", action: {
                                menuShown = false
                                Task {
                                    await chat.resetChat()
                                    DispatchQueue.main.async {
                                        self.chat.scrollProxy?.scrollTo("top", anchor: .top)
                                    }
                                    
                                }
                                
                            })
                            Button("Share", action: {
                                if Application.isCatalyst {
                                    chat.saveDialog()
                                }
                                else {
                                    chat.shareDialog()
                                }
                                menuShown = false
                            })
                            
                            Divider()
                            
                            Button("Camera", action: {
                                showCameraNotification.send(true)
                                menuShown = false
                            })
                            
                            Button("Documents") {
                                showDocumentsNotification.send(true)
                                menuShown = false
                            }
                            
                            Button("Photos", action: {
                                
                                showPhotoPickerNotification.send(true)
                                menuShown = false
                            })
                            
                            Button("Browser", action: {
                                showWebNotification.send(true)
                                menuShown = false
                            })
                            
                            Button("Google Account", action: {
                                startGoogleSignInNotification.send(())
                                menuShown = false
                            })
                            
                            Divider()
                            
                            Toggle("Use GPT4", isOn: $chat.proMode)
                            
                        } label: {
                            Image(systemName: "plus")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 26)
                                .padding(15)
                                .tint(chat.proMode ? .orange : .blue)
                                .animation(Animation.linear, value: chat.proMode)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            menuShown = !menuShown
                        })
                        .opacity(keyboardObserver.isKeyboardVisible ? 0 : 1)
                        .menuStyle(.borderlessButton)
                        .background(colorScheme == .dark ?
                                    Color(red: 1, green: 1, blue: 1, opacity: 0.1) :
                                    Color(red: 0, green: 0, blue: 0, opacity: 0.05)
                        )
                        .clipShape(Circle())
                    }
                    .padding(.trailing, 18)
                    .padding(.bottom, 8)
                        
                }
                .padding(.bottom, geometry.safeAreaInsets.bottom == 0 ? 20 : 0)
                
                // MARK: INPUT BAR
                
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            UIApplication.shared.endEditing()
                        }) {
                            Text("Cancel")
                                .foregroundColor(Color.blue)
                                .padding()
                        }
                        .opacity(keyboardObserver.isKeyboardVisible ? 1 : 0)
                        
                        Button(action: {
                            UIApplication.shared.endEditing()
                            chat.send()
                        }) {
                            Image(systemName: "paperplane.fill")
                                            .font(.system(size: 24))
                                            .padding()
                        }
                        .opacity(keyboardObserver.isKeyboardVisible ? 1 : 0)
                    }
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
            
        }
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

    @State private var showCode = false
    @State private var selectedCode = ""
    @State private var selectedLanguage = ""
    
    var isPad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad || Application.isCatalyst
    }
    
    var body: some View {
 
            if message.record.messageType == .data {
                DataMessageView(attachments: $message.attachments, message: message)
                    .padding(.horizontal)
                    .padding(.top)
            }
            
            if message.record.role == .user && message.record.messageType == .text {
                UserMessageView(messageId: message.record.id, transcript: $message.content, isFocused: _isFocused)
            }
            
            if message.record.role == .assistant {
                Markdown(message.content)
//                    .textSelection(.enabled)
                    .padding()
                    .frame(alignment: .topLeading)
                    .multilineTextAlignment(.leading)
                    .markdownCodeSyntaxHighlighter(.splash(theme: self.theme))
                    .markdownBlockStyle(\.paragraph, body: { configuration in
                        VStack {
                            configuration.label
                                .relativeLineSpacing(.em( isPad ? 0.25 : 0.08))
                                .contextMenu {
                                    Button("Copy", role: .none) {
                                        copyToClipboard(text: configuration.content.renderPlainText())
                                    }
                                }
                        }
                        

                    })
                    .markdownBlockStyle(\.codeBlock, body: { configuration in
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
                            .gesture(TapGesture().onEnded({ value in
                                  selectedLanguage = configuration.language ?? ""
                                  selectedCode = configuration.content
                                  print(selectedLanguage)
                                  showCode.toggle()
                            }))
                            .contextMenu {
                                Button("Select") {
                                    selectedLanguage = configuration.language ?? ""
                                    selectedCode = configuration.content
                                    print(selectedLanguage)
                                    showCode.toggle()
                                }
                            }
                        }
                        .padding(.top)
                        .padding(.bottom)
                    })
                    .sheet(isPresented: $showCode, content: {
                        ZStack(alignment: .topTrailing) {
                            VStack(alignment: .leading, spacing: 0) {
                                GeometryReader { geometry in
                                    CodeEditor(source: $selectedCode, language: CodeEditor.Language(rawValue: selectedLanguage), theme: CodeEditor.ThemeName(rawValue: "xcode"))
                                        .frame(width: geometry.size.width, height: geometry.size.height)
                                }
                            }
                            if Application.isCatalyst {
                                HStack {
                                    Spacer()
                                    Button("Done") {
                                        showCode.toggle()
                                    }
                                    .padding()
                                }
                            }
                        }
                    })
            }
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
            AttachmentView(message: message, attachment: attachment) { }
        }
        .frame(maxHeight: .infinity)
    }
}

struct UserMessageView: View {
    var messageId: String
    @Binding var transcript: String
    @FocusState var isFocused: Bool

    var body: some View {
        QuestionInput(messageId: messageId, transcript: $transcript, isFocused: _isFocused)
    }
}

struct PreviewImage: View {
    let message: Message
    @Binding var attachment: Attachment
    @State var loading = false

    var body: some View {
        Group {
            if let image = attachment.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipped()
            }
            else if loading {
                ProgressView()
                    .frame(width: 60, height: 60)
            }
        }
        .onReceive(attachment.$generatingPreview) { newValue in
            self.loading = newValue
        }
        
    }
}

struct AttachmentView<Content: View>: View {
    let message: Message
    @Binding var attachment: Attachment
    let content: Content

    init(message: Message, attachment: Binding<Attachment>, @ViewBuilder builder: () -> Content) {
        self.message = message
        self._attachment = attachment
        self.content = builder()
    }
    
    var innerBody: some View {
        HStack(spacing: 0) {
            PreviewImage(message: message, attachment: $attachment)
            Text(attachment.dataRecord.name)
                .padding()
                .frame(minHeight: 60)
        }
        .clipped()
        .background(Color(hex: "#000000", alpha: 0.1))
        .cornerRadius(12)
        .contextMenu {
            Button {
                attachment.saveDialog()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            Button {
                attachment.shareDialog()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                message.detach(attachment: attachment)
            } label: {
                Label("Delete", systemImage: "trash")
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
        .onTapGesture {
            attachment.open()
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
