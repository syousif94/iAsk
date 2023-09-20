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

class Message: ObservableObject {
    var record: MessageRecord
    @Published var attachments: [Attachment] = []
    
    @Published var content = "" {
        didSet {
            record.content = content
        }
    }
    
    var ai: Chat {
        if record.messageType == .data {
            let contentFromAttachments = attachments.map { attachment in
                if let url = attachment.url, !url.isFileURL, let path = getDownloadURL(for: url) {
                    return "file_path: \(path.absoluteString)"
                }
                return "file_path: \(attachment.dataRecord.path)"
            }.joined(separator: "\n")
            if record.role == .function {
                return .init(role: record.role, content: contentFromAttachments, name: record.functionCallName)
            }
            return .init(role: record.role, content: contentFromAttachments)
        }
        if record.isFunctionCall {
            return .init(role: record.role, content: nil, functionCall: FunctionCallParams(name: record.functionCallName!, arguments: record.functionCallArgs!).ai)
        }
        if record.role == .function {
            return .init(role: .function, content: record.content, name: record.functionCallName)
        }
        return .init(role: record.role, content: record.content)
    }
    
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
    }
    
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
    
    func attach(url: URL, dataType: DataType) async -> Attachment {
        let attachment = Attachment(url: url, message: self, dataType: dataType)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let hasItem = self.attachments.contains(where: { existing in
                    existing.dataRecord.path == attachment.dataRecord.path
                })
                if hasItem {
                    continuation.resume()
                    return
                }
                self.attachments.append(attachment)
                continuation.resume()
            }
        }
        return attachment
    }
    
    func attach(_ attachments: [Attachment]) async {
        self.attachments += attachments
    }
    
    func detach(attachment: Attachment) {
        
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

class Attachment: ObservableObject {
    @Published var generatingPreview = false
    @Published var indexing = false
    
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
        return url?.dataType == .doc
    }
    
    var previewImage: UIImage? {
        return loadPreviewImage()
    }
    
    var url: URL? {
        return URL(string: dataRecord.path)
    }
    
    
    
    init(url: URL, message: Message, dataType: DataType) {
        let now = Date()
        let dataRecord = DataRecord(path: url.absoluteString, name: url.lastPathComponent, dataType: dataType, createdAt: now)
        let attachmentRecord = AttachmentRecord(msgId: message.record.id, dataId: dataRecord.path, chatId: message.record.chatId, createdAt: now)
        
        self.dataRecord = dataRecord
        self.attachmentRecord = attachmentRecord
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
    
    func open() {
        if let url = url {
            if Application.isCatalyst {
                UIApplication.shared.open(url)
            }
            else {
                shareDialog()
            }
        }
    }
    
    private func loadPreviewImage() -> UIImage? {
        guard let url = self.url else {
            return nil
        }
        switch dataRecord.dataType {
        case .photo:
            return UIImage(url: url)
        case .video, .doc, .url:
            if let image = ImageCache.get(url) {
                return image
            }
            return nil
        default:
            return nil
        }
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
                if let ext = FileType(rawValue: url.pathExtension), ext == .pdf {
                    let _ = await getPDFPreview(url: url)
                }
                case .video:
                    let _ = await getVideoPreview(url: url)
                case .url:
                    let _ = await getUrlPreview(url: url)
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
            Attachment(attachmentRecord: $0, dataRecord: dataDict[$0.dataId]!)
        }
    }
}
