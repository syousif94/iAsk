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
        case events = "events"
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
