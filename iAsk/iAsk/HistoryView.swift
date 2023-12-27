//
//  HistoryView.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/8/23.
//

import Foundation
import Blackbird
import SwiftUI
import Combine
import SwiftDate
import OrderedCollections
import MarkdownUI
import Splash

struct HistoryView: View {
    @Environment(\.colorScheme) var colorScheme
    
    @StateObject var history: HistoryViewModel
    
    let keyboardManager = KeyboardManager()
    
    @State private var keyboardHeight: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        HStack {
                            HistorySearchInput()
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color(uiColor: .borderColor))
                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    
                                    ForEach($history.chats, id: \.record.id) { chat in
                                        HistoryListItem(log: chat)
                                    }
                                }
                                .frame(idealWidth: geometry.size.width, maxHeight: .infinity, alignment: .top)
                                .padding(.top)
                                .id("top")
                            }
                            .scrollDismissesKeyboard(.immediately)
                            .onAppear {
                                history.scrollProxy = scrollProxy
                            }
                        }
                        
                    }
                    else {
                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    
                                    ForEach($history.chats, id: \.record.id) { chat in
                                        HistoryListItem(log: chat)
                                    }
                                }
                                .frame(idealWidth: geometry.size.width, maxHeight: .infinity, alignment: .top)
                                .id("top")
                            }
                            .scrollDismissesKeyboard(.immediately)
                            .onAppear {
                                history.scrollProxy = scrollProxy
                            }
                        }
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color(uiColor: .borderColor))
                        HStack {
                            HistorySearchInput()
                        }
                        .padding(.horizontal)
                        .padding(.top)
                        .padding(.bottom, keyboardHeight)
                        .onAppear {
                            keyboardManager.observeKeyboardChanges { height, animation in
                                withAnimation {
                                    self.keyboardHeight = height > 0 ? height - 20 : height
                                }
                                
                            }
                        }
                    }

                }
                
                
            }
            .background(
                colorScheme == .dark
                ? Color(hex: "#2b3136")
                : Color(hex: "#ffffff")
            )
            .environmentObject(history)
        }
    }
}

struct HistorySearchInput: View {
    @EnvironmentObject var history: HistoryViewModel
    
    @State var isRecording = false
    
    var body: some View {
        ZStack(alignment: .leading) {
            TextField("Search History", text: $history.searchValue)
                .padding(.horizontal)
                .padding(.leading, 30)
                .frame(minHeight: 54)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
                .padding(.leading, 10)
            
            HStack {
                Spacer()
                
                Button(action: {
                    if history.transcriptManager.isRecording {
                        history.transcriptManager.stopTranscribing()
                    }
                    else {
                        history.transcriptManager.transcribe()
                    }
                }) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(isRecording ? .red : .gray)
                        .padding(.trailing, 12)
                        .frame(minHeight: 54)
                        .onReceive(history.transcriptManager.$isRecording) { newValue in
                            self.isRecording = newValue
                        }
                }
                
                if !history.searchValue.isEmpty {
                    Button(action: {
                        history.searchValue = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .padding(.trailing, 12)
                            .frame(minHeight: 54)
                    }
                    
                }
                
            }
            
            
        }
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }
}

struct HistoryListItem: View {
    @Binding var log: ChatLog
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var history: HistoryViewModel
    
    var body: some View {
        Button(action: {
            selectChatNotification.send(log.record)
        }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(log.record.createdAt.in(region: .current).toFormat("MMM dd yyyy, h:mma"))
                        .font(.caption)
                    Text(log.record.createdAt.toRelative(since: nil))
                        .font(.caption)
                }
                .padding()
                
                ForEach(log.messages, id: \.record.id) { message in
                    if message.record.messageType == .data {
                        DataMessageView(attachments: .constant(message.attachments), message: message)
                            .padding(.horizontal)
                            .padding(.bottom)
                    }
                    else if message.record.isFunctionCall {
                        switch message.functionType {
                        case .createCalendarEvent:
                            EventsMessageView(message: message, answering: message.answering)
                        default:
                            EmptyView()
                        }
                    }
                    else {
                        HistoryListText(message: message)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .cornerRadius(12)
            .frame(maxWidth: .infinity)
            .background(colorScheme == .dark ?
                Color(red: 1, green: 1, blue: 1, opacity: 0.1) :
                Color(red: 0, green: 0, blue: 0, opacity: 0.05)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contextMenu {
                Button {
                    log.shareDialog()
                } label: {
                    Label("Share Chat", systemImage: "square.and.arrow.up")
                }
                Button {
                    history.deleteChatLog(log: log)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                
                
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.bottom)
        
    }
}

struct HistoryListText: View {
    @EnvironmentObject var history: HistoryViewModel
    var message: Message
    
    var text: AttributedString {
        var attributed = AttributedString(message.content)
        if history.searchValue.isEmpty {
            return attributed
        }
        let terms = history.searchValue.split(separator: " ")
        let ranges = terms.compactMap { attributed.range(of: $0, options: .caseInsensitive) }
        for range in ranges {
            attributed[range].backgroundColor = .yellow
        }

        return attributed
    }
    
    var body: some View {
        if message.record.role != .function {
            HStack {
                Text(
                    text
                )
                    .fontWeight(message.record.role == .user ? .bold : .regular)
                    .font(message.record.role == .user ? nil : Font.system(size: 12))
                    .lineLimit(5)
                    .padding(.horizontal)
                    .padding(.bottom)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        
    }
}

