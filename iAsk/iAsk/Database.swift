//
//  Database.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/8/23.
//

import Foundation
import Blackbird
import Combine
import NanoID
import OpenAI
import CloudKit

class Database: NSObject {
    static let shared = Database()
    
    let db: Blackbird.Database

    override init() {
        var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = directory.appendingPathComponent("iAsk")
        let dbURL = directory.appendingPathComponent("database.sqlite")
        do {
            try createFoldersForURLPath(url: dbURL)
        }
        catch {
            print("failed to create iAsk application support directory", error.localizedDescription)
        }
//        do {
//            try FileManager.default.removeItem(at: dbURL)
//            print("File successfully deleted!")
//        } catch {
//            print("Error deleting file: \(error)")
//        }
        self.db = try! Blackbird.Database(path: dbURL.absoluteString)
        super.init()
    }
}

struct DataRecord: BlackbirdModel, Codable {
    static var primaryKey: [BlackbirdColumnKeyPath] = [\.$path]
    
    static var indexes: [[BlackbirdColumnKeyPath]] = [
        [\.$parentPath],
        [\.$createdAt],
        [\.$dataType]
    ]
    
    @BlackbirdColumn  var path: String
    @BlackbirdColumn  var parentPath: String?
    @BlackbirdColumn  var name: String
    @BlackbirdColumn  var dataType: DataType
    @BlackbirdColumn  var createdAt: Date
    @BlackbirdColumn  var summary: String?
    @BlackbirdColumn  var keywords: String?
}

extension DataRecord {
    var ckrecord: CKRecord {
        let recordId = CKRecord.ID(recordName: self.path)
        let record = CKRecord(recordType: "Data", recordID: recordId)
        
        record["path"] = self.path as CKRecordValue
        record["parentPath"] = self.parentPath as CKRecordValue?
        record["name"] = self.name as CKRecordValue
        record["dataType"] = self.dataType.rawValue as CKRecordValue
        record["createdAt"] = self.createdAt as CKRecordValue
        record["summary"] = self.summary as CKRecordValue?
        record["keywords"] = self.keywords as CKRecordValue?
        
        return record
    }
    
    init?(ckRecord: CKRecord) {
        guard let path = ckRecord["path"] as? String,
              let name = ckRecord["name"] as? String,
              let dataTypeRawValue = ckRecord["dataType"] as? String,
              let dataType = DataType(rawValue: dataTypeRawValue),
              let createdAt = ckRecord["createdAt"] as? Date else {
            return nil
        }
        
        self.path = path
        self.parentPath = ckRecord["parentPath"] as? String
        self.name = name
        self.dataType = dataType
        self.createdAt = createdAt
        self.summary = ckRecord["summary"] as? String
        self.keywords = ckRecord["keywords"] as? String
    }
}


struct AttachmentRecord: BlackbirdModel, Codable {
    static var primaryKey: [BlackbirdColumnKeyPath] = [\.$msgId, \.$dataId]
    
    static var indexes: [[BlackbirdColumnKeyPath]] = [
        [\.$msgId, \.$createdAt],
        [\.$chatId, \.$createdAt],
        [\.$dataId, \.$createdAt]
    ]

    @BlackbirdColumn var msgId: String
    @BlackbirdColumn var dataId: String
    @BlackbirdColumn var chatId: String
    @BlackbirdColumn var createdAt: Date
    
    var key: String {
        return "\(msgId)\(dataId)"
    }
}

extension AttachmentRecord {
    var ckrecord: CKRecord {
        let recordId = CKRecord.ID(recordName: self.key)
        let record = CKRecord(recordType: "Attachment", recordID: recordId)
        
        record["msgId"] = self.msgId as CKRecordValue
        record["dataId"] = self.dataId as CKRecordValue
        record["chatId"] = self.chatId as CKRecordValue
        record["createdAt"] = self.createdAt as CKRecordValue
        
        return record
    }
    
    init?(ckRecord: CKRecord) {
        guard let msgId = ckRecord["msgId"] as? String,
              let dataId = ckRecord["dataId"] as? String,
              let chatId = ckRecord["chatId"] as? String,
              let createdAt = ckRecord["createdAt"] as? Date else {
            return nil
        }
        
        self.msgId = msgId
        self.dataId = dataId
        self.chatId = chatId
        self.createdAt = createdAt
    }
}

struct MessageRecord: BlackbirdModel, Codable {
    
    static var primaryKey: [BlackbirdColumnKeyPath] = [\.$id]
    
    static var indexes: [[BlackbirdColumnKeyPath]] = [
        [ \.$chatId, \.$createdAt ],
    ]
    
    @BlackbirdColumn var id: String
    @BlackbirdColumn var chatId: String
    // set this id if the question came from a a human
    @BlackbirdColumn var parentMessageId: String?
    @BlackbirdColumn var createdAt: Date
    @BlackbirdColumn var updatedAt: Date?
    @BlackbirdColumn var content: String
    @BlackbirdColumn var role: Chat.Role
    @BlackbirdColumn var messageType: MessageType
    @BlackbirdColumn var model: Model?
    @BlackbirdColumn var promptTokens: Int?
    @BlackbirdColumn var completionTokens: Int?
    @BlackbirdColumn var totalTokens: Int?
    
    @BlackbirdColumn var functionCallName: String?
    @BlackbirdColumn var functionCallArgs: String?
    @BlackbirdColumn var functionLog: String?
    
    // store json or ids of objects created on the system as a result of messages
    // ex. calendar, contact, reminder, etc
    @BlackbirdColumn var systemIdentifier: String?
    
    var isFunctionCall: Bool {
        return role == .assistant && functionCallName != nil && !functionCallName!.isEmpty
    }
    
    init(chatId: String, parentMessageId: String? = nil, createdAt: Date, content: String, role: Chat.Role, messageType: MessageType, model: Model? = nil, promptTokens: Int? = nil, completionTokens: Int? = nil, totalTokens: Int? = nil, functionCallName: String? = nil) {
        let idGen = NanoID.ID()
        let uniqueID = idGen.generate(size: 10)
        self.id = uniqueID
        self.chatId = chatId
        self.parentMessageId = parentMessageId
        self.createdAt = createdAt
        self.content = content
        self.role = role
        self.messageType = messageType
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.functionCallName = functionCallName
    }
    
    enum MessageType: String, Codable, BlackbirdStringEnum {
        case text = "text"
        case data = "data"
        
        // present buttons to user
        case select = "select"
        
        // present an editable, sendable message to user
        case message = "msg"
        
        // present a editable events to user
        case newEvents = "events"
        
        // present a users calendar to them
        case calendar = "calendar"
    }
}

extension MessageRecord {
    var ckrecord: CKRecord {
        let recordId = CKRecord.ID(recordName: self.id)
        let record = CKRecord(recordType: "Message", recordID: recordId)
        
        record["id"] = self.id as CKRecordValue
        record["chatId"] = self.chatId as CKRecordValue
        record["parentMessageId"] = self.parentMessageId as CKRecordValue?
        record["createdAt"] = self.createdAt as CKRecordValue
        record["updatedAt"] = self.updatedAt as CKRecordValue?
        record["content"] = self.content as CKRecordValue
        record["role"] = self.role.rawValue as CKRecordValue
        record["messageType"] = self.messageType.rawValue as CKRecordValue
        record["model"] = self.model as CKRecordValue?
        record["promptTokens"] = self.promptTokens as CKRecordValue?
        record["completionTokens"] = self.completionTokens as CKRecordValue?
        record["totalTokens"] = self.totalTokens as CKRecordValue?
        record["functionCallName"] = self.functionCallName as CKRecordValue?
        record["functionCallArgs"] = self.functionCallArgs as CKRecordValue?
        record["functionLog"] = self.functionLog as CKRecordValue?
        record["systemIdentifier"] = self.systemIdentifier as CKRecordValue?
        
        return record
    }
    
    init?(ckRecord: CKRecord) {
        guard let id = ckRecord["id"] as? String,
              let chatId = ckRecord["chatId"] as? String,
              let createdAt = ckRecord["createdAt"] as? Date,
              let content = ckRecord["content"] as? String,
              let roleRawValue = ckRecord["role"] as? String,
              let role = Chat.Role(rawValue: roleRawValue),
              let messageTypeRawValue = ckRecord["messageType"] as? String,
              let messageType = MessageType(rawValue: messageTypeRawValue) else {
            return nil
        }
        
        self.id = id
        self.chatId = chatId
        self.parentMessageId = ckRecord["parentMessageId"] as? String
        self.createdAt = createdAt
        self.updatedAt = ckRecord["updatedAt"] as? Date
        self.content = content
        self.role = role
        self.messageType = messageType
        self.model = ckRecord["model"] as? String
        self.promptTokens = ckRecord["promptTokens"] as? Int
        self.completionTokens = ckRecord["completionTokens"] as? Int
        self.totalTokens = ckRecord["totalTokens"] as? Int
        self.functionCallName = ckRecord["functionCallName"] as? String
        self.functionCallArgs = ckRecord["functionCallArgs"] as? String
        self.functionLog = ckRecord["functionLog"] as? String
        self.systemIdentifier = ckRecord["systemIdentifier"] as? String
    }
}

struct ChatRecord: BlackbirdModel, Codable {
    @BlackbirdColumn var id: String
    @BlackbirdColumn var summary: String?
    @BlackbirdColumn var createdAt: Date
    @BlackbirdColumn var updatedAt: Date?
}

extension Chat.Role: @unchecked Sendable, BlackbirdStringEnum {
    public static var allCases: [Chat.Role] = [.system, .assistant, .function, .user]
}

extension ChatRecord {
    var ckrecord: CKRecord {
        let recordId = CKRecord.ID(recordName: self.id)
        let record = CKRecord(recordType: "Chat", recordID: recordId)
        
        record["id"] = self.id as CKRecordValue
        record["summary"] = self.summary as CKRecordValue?
        record["createdAt"] = self.createdAt as CKRecordValue
        record["updatedAt"] = self.updatedAt as CKRecordValue?
        
        return record
    }
    
    init?(ckRecord: CKRecord) {
        guard let id = ckRecord["id"] as? String,
              let createdAt = ckRecord["createdAt"] as? Date else {
            return nil
        }
        
        self.id = id
        self.summary = ckRecord["summary"] as? String
        self.createdAt = createdAt
        self.updatedAt = ckRecord["updatedAt"] as? Date
    }
}

struct EmbeddingRecord: BlackbirdModel, Codable {
    /// random id
    @BlackbirdColumn var id: String
    /// path to the data
    @BlackbirdColumn var dataId: String
    /// index of chunk in usearch index
    @BlackbirdColumn var chunkId: String
    /// the string the embedding in the usearch index is referencing
    @BlackbirdColumn var chunk: String
    /// a shared id for all chunks from the same embedding
    @BlackbirdColumn var embeddingId: String
    @BlackbirdColumn var createdAt: Date
    @BlackbirdColumn var updatedAt: Date?
}

struct BrowserHistoryRecord: BlackbirdModel, Codable {
    @BlackbirdColumn var id: String
    @BlackbirdColumn var url: String
    @BlackbirdColumn var title: String?
    @BlackbirdColumn var meta: String?
    @BlackbirdColumn var description: String?
    @BlackbirdColumn var createdAt: Date
    @BlackbirdColumn var lastVisited: Date?
    @BlackbirdColumn var visitCount: Int
}
