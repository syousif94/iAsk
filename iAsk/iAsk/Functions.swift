//
//  Functions.swift
//  iAsk
//
//  Created by Sammy Yousif on 9/7/23.
//

import Foundation
import OpenAI

class FunctionCallResponse {
    var name = ""
    var arguments = ""
    var nameCompleted = false
    
    func toArgs<T>(_ type: T.Type) throws -> T where T: Decodable {
        let decoder = JSONDecoder()
        let args = try decoder.decode(type, from: arguments.data(using: .utf8)!)
        #if DEBUG
        print(args)
        #endif
        return args
    }
}

typealias FunctionKnownHandler = (_ chatModel: ChatViewModel, _ aiMessage: Message, _ name: String) -> Void
typealias FunctionArgumentUpdateHandler = (_ chatModel: ChatViewModel, _ aiMessage: Message, _ update: String) -> Void
typealias FunctionRunHandler = (_ chatModel: ChatViewModel, _ aiMessage: Message, _ response: FunctionCallResponse) -> Void

class FunctionHandler {
    let onFunctionKnown: FunctionKnownHandler
    let onArgumentStream: FunctionArgumentUpdateHandler
    let onRun: FunctionRunHandler
    
    init(onFunctionKnown: @escaping FunctionKnownHandler, onArgumentStream: @escaping FunctionArgumentUpdateHandler, onRun: @escaping FunctionRunHandler) {
        self.onFunctionKnown = onFunctionKnown
        self.onArgumentStream = onArgumentStream
        self.onRun = onRun
    }
}

enum FunctionCall: String, Codable {
    case getUserLocation = "get_user_location"
    case createNewContact = "create_new_contact"
    case searchContacts = "search_contacts"
    case search = "search"
    case convertMedia = "convert_media"
//    case python = "python"
//    case writeFiles = "write_files"
    case readFiles = "read_files"
    case sms = "sms"
//    case call = "call"
    case createCalendarEvent = "create_calendar_event"
    case getCalendar = "get_calendar"
    case createReminder = "create_reminder"
//    case editCalendarEvent = "edit_calendar_event"
    case parseEquations = "math_ocr"
}

struct WriteFilesArgs: Codable {
    struct File: Codable {
        let path: String
        let content: String
    }
    let files: [File]?
}

struct ReadFilesArgs: Codable {
    let files: [String]
    let summaryRequested: Bool?
    let mathRequested: Bool?
    let editsRequestedFor: [String]?
}

struct MathOCRArgs: Codable {
    let files: [String]
}

struct ConvertMediaArgs: Codable {
    struct ItemArgs: Codable {
        let inputFilePath: String?
        let command: String?
        let outputExtension: String?
    }
    
    let items: [ItemArgs]
}

struct SearchArgs: Codable {
    let query: String;
}

struct SMSArgs: Codable {
    let contact: String?
    let message: String?
    let phoneNumber: String?
}

struct CallArgs: Codable {
    let contact: String?
    let phoneNumber: String?
}

struct CreateNewContactArgs: Codable {
    let name: String
    let number: String?
    let email: String?
    let employer: String?
}

struct SearchContactsArgs: Codable {
    let name: String;
    let contactType: ContactType
}

struct PythonArgs: Codable {
    let script: String;
}

struct SearchDocumentsArgs: Codable {
    let queries: [String];
    let files: [String];
}

struct SummarizeDocumentsArgs: Codable {
    let files: [String];
}

struct GetCalendarArgs: Codable {
    let startDate: String?
    let endDate: String?
    let titleFilter: String?
}

struct CreateCalendarEventArgs: Codable {
    let title: String
    let location: String?
    let startDate: String
    let endDate: String
    let allDay: Bool
    let notes: String?
    let url: String?
}

struct CreateReminderArgs: Codable {
    let title: String
    let dueDate: String
    let notes: String?
}

func getFunctions() -> [ChatFunctionDeclaration] {
    let functions = [
      ChatFunctionDeclaration(
          name: "search",
          description: "Get useful current information to help answer users' questions",
          parameters:
            JSONSchema(
              type: .object,
              properties: [
                "query": .init(type: .string, description: "The search query to look up")
              ],
              required: ["query"]
            )
      ),
      ChatFunctionDeclaration(
          name: "create_new_contact",
          description: "Create a new contact in the user's contact list.",
          parameters:
            JSONSchema(
              type: .object,
              properties: [
                "name": .init(type: .string, description: "The name of the new contact"),
                "number": .init(type: .string, description: "The phone number of the new contact"),
                "email": .init(type: .string, description: "The email address of the new contact"),
                "employer": .init(type: .string, description: "Where the contact works")
              ],
              required: ["name"]
            )
      ),
//      ChatFunctionDeclaration(
//          name: "python",
//          description: "Run python code and get the output back",
//          parameters:
//            JSONSchema(
//              type: .object,
//              properties: [
//                "script": .init(type: .string, description: "The python code to run")
//              ],
//              required: ["script"]
//            )
//      ),
//      ChatFunctionDeclaration(
//          name: "call",
//          description: "Call a phone number on behalf of the user.",
//          parameters:
//            JSONSchema(
//              type: .object,
//              properties: [
//                "contact": .init(type: .string, description: "The name of the contact the user wishes to contact, ex. Brad"),
//                "phoneNumber": .init(type: .string, description: "The phone number to dial, e.g. 8323305481")
//              ],
//              required: []
//            )
//      ),
//      ChatFunctionDeclaration(
//          name: "sms",
//          description: "Send an sms message to a contact on behalf of the user. Use this when the user asks you to contact someone or ask someone a question.",
//          parameters:
//            JSONSchema(
//              type: .object,
//              properties: [
//                "contact": .init(type: .string, description: "The name of the contact the user wishes to contact, ex. Brad"),
//                "phoneNumber": .init(type: .string, description: "The phone number to dial, e.g. 8323305481"),
//                "message": .init(type: .string, description: "The message you have generated to send")
//              ],
//              required: []
//            )
//      ),
      ChatFunctionDeclaration(
          name: "search_contacts",
          description: "Get search results from the user's contacts",
          parameters:
            JSONSchema(
              type: .object,
              properties: [
                "name": .init(type: .string, description: "A name to search for, e.g. Steve"),
                "contactType": .init(type: .string, enumValues: ["email", "phone", "address"])
              ],
              required: ["name", "contactType"]
            )
      ),
      ChatFunctionDeclaration(
          name: "send_email",
          description: "Send an email to a contact",
          parameters:
            JSONSchema(
              type: .object,
              properties: [
                "contact": .init(type: .string, description: "The name of the contact, e.g. joe"),
                "email": .init(type: .string, description: "The email address for the contact, e.g. john@doe.com"),
                "subject": .init(type: .string, description: "The subject of the email"),
                "body": .init(type: .string, description: "The body of the email")
              ],
              required: ["subject", "body"]
            )
      ),
      ChatFunctionDeclaration(
          name: "get_calendar",
          description: "Get the user's calendar, including events and reminders",
          parameters:
            JSONSchema(
              type: .object,
              properties: [
                "startDate": .init(type: .string, description: "The earliest calendar events to load in yyyy-MM-dd HH:mm, e.g. 2010-05-20 15:30. Leave blank for an hour before the current time."),
                "endDate": .init(type: .string, description: "The latest calendar events to load in yyyy-MM-dd HH:mm, e.g. 2010-05-20 16:30. Leave blank for the next end of month after the start date"),
                "textFilter": .init(type: .string, description: "Filter out the events by search terms. Use this if the user is looking for a particular event or reminder.")
              ],
              required: []
            )
      ),
      ChatFunctionDeclaration(
          name: "create_calendar_event",
          description: "Create a calendar entry in the user's calendar.",
          parameters:
            JSONSchema(
              type: .object,
              properties: [
                "title": .init(type: .string, description: "The name of the event, e.g. Lunch or Team Meeting"),
                "location": .init(type: .string, description: "The location of the event, e.g. Chipotle or 2801 Example St"),
                "startDate": .init(type: .string, description: "The start time of the event in yyyy-MM-dd HH:mm, e.g. 2010-05-20 15:30"),
                "endDate": .init(type: .string, description: "The end time of the event in yyyy-MM-dd HH:mm, e.g. 2010-05-20 16:30"),
                "allDay": .init(type: .boolean, description: "Does the event last all day?")
              ],
              required: ["title", "startDate", "endDate", "allDay"]
            )
      ),
      ChatFunctionDeclaration(
          name: "create_reminder",
          description: "Create a new reminder in the user's reminders list.",
          parameters:
            JSONSchema(
              type: .object,
              properties: [
                "title": .init(type: .string, description: "The title of the reminder"),
                "dueDate": .init(type: .string, description: "The due date and time for the reminder in yyyy-MM-dd HH:mm format"),
                "notes": .init(type: .string, description: "Additional notes for the reminder")
              ],
              required: ["title", "dueDate"]
            )
      ),
      ChatFunctionDeclaration(
          name: "convert_media",
          description: "Convert an image or video using ffmpeg",
          parameters:
            JSONSchema(
              type: .object,
              properties: [
                "items": .init(
                    type: .array,
                    description: "A list of media to convert, ex. {\"inputFilePath\": \"file:///var/pic.png\", \"command\": \"-vf \"scale=iw*10:ih*10:flags=neighbor\"\", \"outputExtension\": \"apng\"}. The command property is optional.",
                    items: JSONSchema.Items(
                        type: .object,
                        properties: [
                            "inputFilePath": .init(type: .string, description: "The file path for the input file"),
                            "command": .init(type: .string, description: "The ffmpeg arguments used for the conversion apart from the input and output files, e.g. -vf \"scale=iw*10:ih*10:flags=neighbor\""),
                            "outputExtension": .init(type: .string, description: "The output format e.g. mp4 or apng"),
                        ]
                ))
              ],
              required: ["items"]
            )
      ),
      ChatFunctionDeclaration(
          name: "get_user_location",
          description: "Get the user's coordinates and city",
          parameters:
            JSONSchema(
              type: .object,
              properties: [:],
              required: []
            )
      ),
      ChatFunctionDeclaration(
          name: "math_ocr",
          description: "You must use this to handle math equations in photos. Photos are file_paths that end in .heic, .jpeg, .jpg, or .png only. Do not use this for documents.",
          parameters:
            JSONSchema(
              type: .object,
              properties: [
                "files": .init(
                    type: .array,
                    items: JSONSchema.Items(
                        type: .string
                ))
              ],
              required: ["files"]
            )
      ),
//      ChatFunctionDeclaration(
//          name: "write_files",
//          description: "Write data to files based on their path. Do not worry about overwriting files.",
//          parameters:
//            JSONSchema(
//              type: .object,
//              properties: [
//                "files": .init(
//                    type: .array,
//                    description: "A list of file objects to write to",
//                    items: JSONSchema.Items(
//                        type: .object,
//                        properties: [
//                                    "path":.init(type: .string, description: "path to write to"),
//                                    "content": .init(type: .string, description: "the file content")
//                        ]
//                ))
//              ],
//              required: ["files"]
//            )
//      ),
//      ChatFunctionDeclaration(
//          name: "read_files",
//          description: "Read files using their path",
//          parameters:
//            JSONSchema(
//              type: .object,
//              properties: [
//                "files": .init(
//                    type: .array,
//                    items: JSONSchema.Items(
//                        type: .string
//                ))
//              ],
//              required: ["files"]
//            )
//      )
    ]
    return functions
}

struct DetermineArgs: Codable {
    let isTrue: Bool
}

func determine(_ messages: [Chat]) async -> Bool {
    
    let functions = [
      ChatFunctionDeclaration(
          name: "determine",
          description: "Determine whether the answer is true or false",
          parameters:
            JSONSchema(
              type: .object,
              properties: [
                "isTrue": .init(type: .boolean, description: "Whether the answer to the question is true or false")
              ],
              required: ["isTrue"]
            )
      )
    ]
    
    let openAI = OpenAI(apiToken: OPEN_AI_KEY)
    
    let query = ChatQuery(model: .gpt3_5Turbo, messages: messages, functions: functions, functionCall: .function("determine"))
    
    if let result = try? await openAI.chats(query: query), let functionCall = result.choices[0].message.functionCall {
    
        let call = FunctionCallResponse()
        
        call.name = functionCall.name ?? ""
        
        call.arguments = functionCall.arguments ?? ""
        
        if let args = try? call.toArgs(DetermineArgs.self) {
            return args.isTrue
        }
    }
    
    return false
}

struct TermsArgs: Codable {
    let terms: [String]
}

func extractTerms(_ messages: [Chat]) async -> [String] {
    let functions = [
      ChatFunctionDeclaration(
          name: "extract_terms",
          description: "Extract relevant terms from the input text",
          parameters:
            JSONSchema(
              type: .object,
              properties: [
                "terms": .init(type: .string, description: "Terms extracted from the text")
              ],
              required: ["terms"]
            )
      )
    ]
    
    let openAI = OpenAI(apiToken: OPEN_AI_KEY)
    
    let query = ChatQuery(model: .gpt3_5Turbo, messages: messages, functions: functions, functionCall: .function("extract_terms"))
    
    if let result = try? await openAI.chats(query: query), let functionCall = result.choices[0].message.functionCall {
    
        let call = FunctionCallResponse()
        
        call.name = functionCall.name ?? ""
        
        call.arguments = functionCall.arguments ?? ""
        
        if let args = try? call.toArgs(TermsArgs.self) {
            return args.terms
        }
    }
    
    return []
}
