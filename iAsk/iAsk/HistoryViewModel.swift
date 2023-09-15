//
//  HistoryViewModel.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/17/23.
//

import Foundation
import Blackbird
import SwiftUI
import Combine
import SwiftDate
import OrderedCollections


class ChatLog: ObservableObject, Equatable {
    static func == (lhs: ChatLog, rhs: ChatLog) -> Bool {
        return lhs.record.id == rhs.record.id
    }
    
    let record: ChatRecord
    
    @Published var messages = [Message]()
    
    var messageDict = OrderedDictionary<String, Message>()
    
    init(record: ChatRecord, messages: [Message]) {
        self.record = record
        self.messages = messages
        for message in messages {
            self.messageDict.updateValue(message, forKey: message.record.id)
        }
    }
    
    func updateMessages() {
        DispatchQueue.main.async {
            self.messages = self.messageDict.values.elements
        }
    }
}


class HistoryViewModel: ObservableObject {
    
    var scrollProxy: ScrollViewProxy?
    
    var cancellables = Set<AnyCancellable>()
    
    @Published var chats = [ChatLog]()
    
    var chatLogs = OrderedDictionary<String, ChatLog>()
    
    var searchResultIds = OrderedSet<String>()
    
    func updateChats() {
        var chats = self.chatLogs.values.elements
        if !searchResultIds.isEmpty {
            chats = searchResultIds.elements.compactMap {
                self.chatLogs[$0]
            }
        }
        DispatchQueue.main.async {
            self.chats = chats
        }
    }
    
    @Published var searchValue = ""
    
    init() {
        setupSearchHandler()
    }
    
    func setupSearchHandler() {
        let searchCancellable = $searchValue
                    .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
                    .removeDuplicates()
                    .sink { [weak self] searchText in
                        self?.search(text: searchText)
                    }
        
        searchCancellable.store(in: &cancellables)
        
        Task {
            await setupChatIndex()
        }
    }
    
    func search(text: String) {
        Task {
            await searchChatIndex(input: text)
        }
    }
    
    var lastMessageRecord: MessageRecord? = nil
    
    func setupChatIndex() async {
        // first get all the latest chats
        guard let chatRecords = try? await ChatRecord.read(from: Database.shared.db, orderBy: .descending(\.$createdAt)) else {
            return
        }
        
        lastMessageRecord = try? await MessageRecord.read(from: Database.shared.db, orderBy: .descending(\.$createdAt), limit: 1).first
        
        // then get all their messages
        let chatMessages = try? await withThrowingTaskGroup(of: [Message]?.self) { group in

            for chatRecord in chatRecords {
                group.addTask {
                    return await Message.loadForChatId(chatRecord.id)
                }
            }
            
            var messagesDict = Dictionary<String, [Message]>()
        
            for try await messages in group {
                messagesDict.updateValue(messages!, forKey: messages!.first!.record.chatId)
            }

            return messagesDict
        }
        
        for chatRecord in chatRecords where chatMessages?[chatRecord.id] != nil {
            let chatLog = ChatLog(record: chatRecord, messages: chatMessages![chatRecord.id]!)
            chatLogs.updateValue(chatLog, forKey: chatLog.record.id)
        }
        
        updateChats()
        
        let messageRecordSubscription = MessageRecord.changePublisher(in: Database.shared.db).debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [self] changes in
            Task {
                await self.updateChatIndex()
            }
        }
        
        messageRecordSubscription.store(in: &cancellables)
//
//        let chatRecordSubscription = ChatRecord.changePublisher(in: Database.shared.db).debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
//            .sink { [self] changes in
//            Task {
//                await self.updateChatIndex()
//            }
//        }
//
//        chatRecordSubscription.store(in: &cancellables)
    }
    
    func updateChatIndex()  async {
        var newMessages: [MessageRecord]?
        
        if let lm = self.lastMessageRecord {
            newMessages = try? await MessageRecord.read(from: Database.shared.db, sqlWhere: "createdAt > ? ORDER BY createdAt DESC", arguments: [lm.createdAt])
        }
        else {
            newMessages = try? await MessageRecord.read(from: Database.shared.db, orderBy: .descending(\.$createdAt))
        }
        
        guard let newMessages = newMessages else {
            return
        }
        
        for messageRecord in newMessages.reversed() {
            let message = Message(record: messageRecord)
            if message.record.messageType == .data {
                await message.loadAttachments()
            }
            if let chatLog = self.chatLogs[messageRecord.chatId] {
                if let existingMessage = chatLog.messageDict[messageRecord.id] {
                    chatLog.messageDict.updateValue(message, forKey: existingMessage.record.id)
                    chatLog.updateMessages()
                }
                else {
                    chatLog.messageDict.updateValue(message, forKey: messageRecord.id)
                    chatLog.updateMessages()
                }
            }
            else if let chatRecord = try? await ChatRecord.read(from: Database.shared.db, id: messageRecord.chatId) {
                let chatLog = ChatLog(record: chatRecord, messages: [message])
                chatLogs.updateValue(chatLog, forKey: chatLog.record.id, insertingAt: 0)
            }
        }
        
        self.lastMessageRecord = newMessages.last
        self.updateChats()
    }
    
    func searchChatIndex(input: String) async {
        if input.isEmpty {
            self.searchResultIds = OrderedSet()
            self.updateChats()
            return
        }
        
        let terms = input.split(separator: " ")
        
        let searchArgs = terms.compactMap { "%\($0.lowercased())%" }
        
        var sqlWheres = searchArgs.map { _ in "lower(content) LIKE ?" }.joined(separator: " AND ")
        
        sqlWheres += " ORDER BY createdAt DESC"
        
        let messages = try? await MessageRecord.read(from: Database.shared.db, sqlWhere: sqlWheres, arguments: searchArgs)
        
        let filterMessages = messages?.filter { $0.role != .function && !$0.isFunctionCall }
        
        var messageList = filterMessages?.compactMap { $0.chatId }

        if messageList == nil || messageList!.isEmpty {
            messageList = ["1"]
        }
        
        let chatIds = OrderedSet(messageList!)
        
        self.searchResultIds = chatIds
        
        self.updateChats()
        
        DispatchQueue.main.async {
            self.scrollProxy?.scrollTo("top", anchor: .top)
        }
        
        return
    }

}
