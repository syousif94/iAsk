//
//  ChatMessage.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/28/23.
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

enum MessageChoices: Codable {
    case contacts(choices: [ContactManager.Choice])
}

class Message: ObservableObject {
    // the database representation of the message only
    var record: MessageRecord
    
    // abstraction over joined attachments and data
    @Published var attachments: [Attachment] = []
    
    // use this to control the display of the message
    @Published var content = "" {
        didSet {
            record.content = content
        }
    }
    
    @Published var answering = false
    
    // use this to keep track of the call type
    @Published var functionType: FunctionCall? = nil
    
    @Published var functionLog = "" {
        didSet {
            record.functionLog = functionLog
        }
    }
    
    @Published var choices: MessageChoices? {
        didSet {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(choices), let text = String(data: data, encoding: .utf8) {
                record.content = text
            }
        }
    }
    
    // renders the message for MacPaw's openAI lib
    var ai: Chat? {
        if record.messageType == .select {
            return nil
        }
        if record.messageType == .data {
            let contentFromAttachments = attachments.map { attachment in
                if let url = attachment.url, !url.isFileURL, let path = getDownloadURL(for: url) {
                    return "file_path: \(path.lastPathComponent)"
                }
                return "file_path: \(attachment.dataRecord.name)"
            }.joined(separator: "\n")
            if record.role == .function {
                return .init(role: record.role, content: contentFromAttachments, name: record.functionCallName)
            }
            return .init(role: record.role, content: contentFromAttachments)
        }
        if record.isFunctionCall {
            let functionCall = ChatFunctionCall(name: record.functionCallName!, arguments: record.functionCallArgs!)
            return .init(role: record.role, content: nil, functionCall: functionCall)
        }
        if record.role == .function {
            return .init(role: .function, content: record.content, name: record.functionCallName)
        }
        return .init(role: record.role, content: record.content)
    }
    
    // renders the message for export
    var md: String? {
        if record.messageType == .data {
            let contentFromAttachments = attachments.map { "file_path: \($0.dataRecord.path)" }.joined(separator: "\n")
            return "**\(record.role):** \(contentFromAttachments)"
        }
        if record.isFunctionCall {
            return "**\(record.role):** \(record.content)"
        }
        if record.role == .function {
            return "**\(record.role):** \(record.content)"
        }
        return record.role == .user ? "**\(record.content)**" : record.content
    }
    
    init(record: MessageRecord) {
        self.record = record
        self.content = record.content
        if let name = record.functionCallName {
            self.functionType = FunctionCall(rawValue: name)
        }
        if let log = record.functionLog {
            self.functionLog = log
        }
        if record.messageType == .select {
            let decoder = JSONDecoder()
            if let data = record.content.data(using: .utf8),
               let choices = try? decoder.decode(MessageChoices.self, from: data) {
                self.choices = choices
            }
        }
    }
    
    // don't remember where this is used lol
    init(chatId: String) {
        let now = Date()
        self.record = MessageRecord(chatId: chatId, createdAt: now, content: "", role: .user, messageType: .data)
    }
    
    func save() async {
        record.updatedAt = Date()
        
        do {
            if record.messageType == .data {
                for attachment in attachments {
                    try await attachment.save()
                }
            }
            try await record.write(to: Database.shared.db)
            var chatRecord = try await ChatRecord.read(from: Database.shared.db, id: record.chatId)
            chatRecord?.updatedAt = record.updatedAt
            try await chatRecord?.write(to: Database.shared.db)
        }
        catch {
            print("Error: \(error)")
        }
    }
    
    func loadAttachments() async {
        let attachments = await Attachment.load(for: self)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.attachments = attachments
                continuation.resume()
            }
        }
    }
    
    func attach(url: URL) async -> Attachment {
        let attachment = Attachment(url: url, message: self)
        
        await withCheckedContinuation { continuation in
            let hasItem = self.attachments.contains(where: { existing in
                existing.dataRecord.path == attachment.dataRecord.path
            })
            if hasItem {
                continuation.resume()
                return
            }
            
            DispatchQueue.main.async {
                self.attachments.append(attachment)
                continuation.resume()
            }
        }
        return attachment
    }
    
    func attach(_ attachments: [Attachment]) async {
        self.attachments += attachments
    }

    func detach(attachment: Attachment) async {
        let db = Database.shared.db
        
        var deleteData = false
        
        if let otherExamples = try? await AttachmentRecord.read(from: db, matching: \.$dataId == attachment.attachmentRecord.dataId),
           otherExamples.count == 1 {
            deleteData = true
        }
        
        DispatchQueue.main.async {
            self.attachments = self.attachments.filter { a in
                a.dataRecord.path != attachment.dataRecord.path
            }
        }
        
        try? await attachment.attachmentRecord.delete(from: db)
        
        if deleteData, let url = attachment.url {
            try? await attachment.dataRecord.delete(from: db)
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    static func load(id: String) async -> Message? {
        let record = try! await MessageRecord.read(from: Database.shared.db, id: id)
        
        guard let record = record else {
            return nil
        }
        
        let message = Message(record: record)
        
        if record.messageType == .data {
            await message.loadAttachments()
        }
        
        return message
    }
    
    static func loadForChatId(_ chatId: String) async -> [Message]? {
        let records = try! await MessageRecord.read(from: Database.shared.db, sqlWhere: "chatId = ? ORDER BY createdAt ASC", arguments: [chatId])
        
        let messages = records.map(Message.init)
        
        for message in messages where message.record.messageType == .data {
            await message.loadAttachments()
        }
        
        return messages
    }
}

extension UIImage {
    convenience init?(url: URL?) {
        guard let url = url, let data = try? Data(contentsOf: url) else {
            return nil
        }
        self.init(data: data)
    }
}

class Attachment: ObservableObject, Hashable, Identifiable {
    
    var id: String {
        return "\(attachmentRecord.msgId)\(attachmentRecord.dataId)"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(attachmentRecord.msgId)
        hasher.combine(attachmentRecord.dataId)
    }
    
    static func == (lhs: Attachment, rhs: Attachment) -> Bool {
        return lhs.url == rhs.url
    }
    
    @Published var generatingPreview = false
    @Published var indexing = false
    @Published var status = ""
    
    let attachmentRecord: AttachmentRecord
    let dataRecord: DataRecord
    
    var hasPreview: Bool {
        switch dataRecord.dataType {
        case .photo, .video, .doc, .url:
            return true
        default:
            return false
        }
    }
    
    var hasText: Bool {
        guard let dataType = url?.dataType else {
            return false
        }
        return dataType == .doc || dataType == .photo
    }
    
    var previewImage: UIImage? {
        return loadPreviewImage()
    }
    
    var url: URL? {
        return URL(string: dataRecord.path)
    }
    
    func index() async {
        guard let url = url else {
            return
        }
        
        DispatchQueue.main.async {
            self.indexing = true
        }
        
        let importFileType = dataRecord.dataType
        
        if importFileType == .doc || importFileType == .photo {
            
            DispatchQueue.main.async {
                self.status = "Indexing"
            }
            
            try? await indexText(attachment: self)
        }
        else if importFileType == .url {
            DispatchQueue.main.async {
                self.status = "Downloading"
            }
            
            try? await download(url: url)
            
            if url.pathExtension == "pdf" {
                print("generating downloaded pdf", url)
                self.generatingPreview = false
                self.generatePreviewImage()
            }
            
            DispatchQueue.main.async {
                self.status = "Indexing"
            }
            
            if hasText {
                try? await indexText(attachment: self)
            }
        }
        
        DispatchQueue.main.async {
            self.indexing = false
            self.status = ""
        }
    }
    
    init(url: URL, message: Message) {
        let now = Date()
        let dataRecord = DataRecord(path: url.absoluteString, name: url.lastPathComponent, dataType: getDataType(url: url), createdAt: now)
        let attachmentRecord = AttachmentRecord(msgId: message.record.id, dataId: dataRecord.path, chatId: message.record.chatId, createdAt: now)
        
        self.dataRecord = dataRecord
        self.attachmentRecord = attachmentRecord
        
        Task {
            print("starting attachment indexing", url)
            await index()
            print("finished indexing", url)
        }
    }
    
    init(attachmentRecord: AttachmentRecord, dataRecord: DataRecord) {
        self.attachmentRecord = attachmentRecord
        self.dataRecord = dataRecord
    }
    
    func save() async throws {
        try await self.dataRecord.write(to: Database.shared.db)
        try await self.attachmentRecord.write(to: Database.shared.db)
    }
    
    func shareDialog() {
        if let url = url, fileExists(at: url) {
            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            UIApplication.shared.windows.first?.rootViewController?.present(av, animated: true, completion: nil)
        }
    }
    
    func saveDialog() {
        if let url = url {
            showSaveNotification.send([url])
        }
    }
    
    func readFile() -> String? {
        guard let url = url,
              let localUrl = url.isFileURL ? url : getDownloadURL(for: url) else {
            return nil
        }
        
        return extractText(url: localUrl, dataType: dataRecord.dataType)
    }
    
    func open() {
        if let url = url {
            if Application.isCatalyst {
                UIApplication.shared.open(url)
            }
            else {
                Browser.shared.viewModel.browserUrl = url
                showWebNotification.send(true)
            }
        }
    }
    
    private func loadPreviewImage() -> UIImage? {
        
        guard let url = self.url else {
            return nil
        }
        
        print("loading preview image for url", url.absoluteString)
        
        let urlDataType = url.dataType
        
        if urlDataType == .doc, let fileType = FileType(rawValue: url.pathExtension.lowercased()) {
            if fileType == .pdf || dataRecord.dataType == .url {
                return ImageCache.get(url)
            }
        }
        else if urlDataType == .photo {
            return UIImage(url: url)
        }
        else if urlDataType == .video || dataRecord.dataType == .url {
            return ImageCache.get(url)
        }
        
        return nil
    }
    
    func generatePreviewImage() {
        if self.generatingPreview {
            return
        }
        
        guard let url = url else {
            return
        }
        
        self.generatingPreview = true
        
        Task {
            switch dataRecord.dataType {
                case .doc:
                if let ext = FileType(rawValue: url.pathExtension.lowercased()), ext == .pdf {
                    let _ = await getPDFPreview(url: url)
                }
                case .video:
                    let _ = await getVideoPreview(url: url)
                case .url:
                    if let ext = FileType(rawValue: url.pathExtension.lowercased()), ext == .pdf {
                        let _ = await getPDFPreview(url: url)
                    }
                    else {
                        let _ = await getUrlPreview(url: url)
                    }
                    
                default:
                    break
            }
            
            DispatchQueue.main.async {
                self.generatingPreview = false
            }
        }
    }
    
    func getDragItem() {
        
    }
    
    static func load(for message: Message) async -> [Attachment] {
        
        guard let attachmentRecords = try? await AttachmentRecord.read(from: Database.shared.db, sqlWhere: "msgId = ? ORDER BY createdAt ASC", arguments: [message.record.id]) else {
            return []
        }
        
        let dataIds = attachmentRecords.map { "\"\($0.dataId)\"" }.joined(separator: ",")
        
        guard let dataRecords = try? await DataRecord.read(from: Database.shared.db, sqlWhere: "path IN (\(dataIds))") else {
            return []
        }
        
        var dataDict = [String: DataRecord]()
        
        for record in dataRecords {
            dataDict[record.path] = record
        }
        
        return attachmentRecords.compactMap {
            guard let record = dataDict[$0.dataId] else {
                return nil
            }
            return Attachment(attachmentRecord: $0, dataRecord: record)
        }
    }
}
