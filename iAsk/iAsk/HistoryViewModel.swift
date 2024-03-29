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
    
    func shareDialog() {
        
        let chatName = messages.first(where: { $0.record.messageType == .text })?.content.replacing(" ", with: "-") ?? record.id
        
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
    
    func updateMessages() {
        self.messages = self.messageDict.values.elements
    }
}


class HistoryViewModel: ObservableObject {
    
    var scrollProxy: ScrollViewProxy?
    
    var cancellables = Set<AnyCancellable>()
    
    @Published var chats = [ChatLog]()
    
    var chatLogs = OrderedDictionary<String, ChatLog>()
    
    var searchResultIds = OrderedSet<String>()
    
    func deleteChatLog(log: ChatLog) {
        chatLogs.removeValue(forKey: log.record.id)
        updateChats()
        Task {
            try? await log.record.delete(from: Database.shared.db)
        }
    }
    
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
    
    @Published var transcriptManager = TranscriptManager()
    
    init() {
        setupSearchHandler()
        
        transcriptManager.onTranscript = { transcript in
            DispatchQueue.main.async {
                self.searchValue = transcript
            }
            
        }
    }
    
    func setupSearchHandler() {
        let searchCancellable = $searchValue
                    .debounce(for: .seconds(0.15), scheduler: DispatchQueue.main)
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
                    DispatchQueue.main.async {
                        chatLog.messageDict.updateValue(message, forKey: existingMessage.record.id)
                        chatLog.updateMessages()
                    }
                    
                }
                else {
                    DispatchQueue.main.async {
                        chatLog.messageDict.updateValue(message, forKey: messageRecord.id)
                        chatLog.updateMessages()
                    }
                }
            }
            else if let chatRecord = try? await ChatRecord.read(from: Database.shared.db, id: messageRecord.chatId), let messages = await Message.loadForChatId(messageRecord.chatId) {
                let chatLog = ChatLog(record: chatRecord, messages: messages)
                
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

        var foundMessages = true
        if messageList == nil || messageList!.isEmpty {
            messageList = ["1"]
            foundMessages = false
        }
        
        let chatIds = OrderedSet(messageList!)
        
        DispatchQueue.main.async { [foundMessages] in
            self.searchResultIds = chatIds
            
            self.updateChats()
            
            if foundMessages {
                self.scrollProxy?.scrollTo("top", anchor: .top)
            }
        }
    }

}
