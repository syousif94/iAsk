//
//  StreamingSession.swift
//
//
//  Created by Sergii Kryvoblotskyi on 18/04/2023.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import OpenAI
import UIKit

final class StreamingSession<ResultType: Codable>: NSObject, Identifiable, URLSessionDelegate, URLSessionDataDelegate {
    
    enum StreamingError: Error {
        case unknownContent
        case emptyContent
    }
    
    var onReceiveContent: ((StreamingSession, ResultType) -> Void)?
    var onProcessingError: ((StreamingSession, Error) -> Void)?
    var onComplete: ((StreamingSession, Error?) -> Void)?
    
    private let streamingCompletionMarker = "[DONE]"
    private let urlRequest: URLRequest
    private lazy var urlSession: URLSession = {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        return session
    }()
    
    private var previousChunkBuffer = ""

    init(urlRequest: URLRequest) {
        self.urlRequest = urlRequest
    }
    
    func perform() {
        self.urlSession
            .dataTask(with: self.urlRequest)
            .resume()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onComplete?(self, error)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let stringContent = String(data: data, encoding: .utf8) else {
            onProcessingError?(self, StreamingError.unknownContent)
            return
        }
        processJSON(from: stringContent)
    }
    
}

extension StreamingSession {
    
    private func processJSON(from stringContent: String) {
        let jsonObjects = "\(previousChunkBuffer)\(stringContent)"
            .components(separatedBy: "data:")
            .filter { $0.isEmpty == false }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        previousChunkBuffer = ""
        
        guard jsonObjects.isEmpty == false, jsonObjects.first != streamingCompletionMarker else {
            return
        }
        jsonObjects.enumerated().forEach { (index, jsonContent)  in
            guard jsonContent != streamingCompletionMarker else {
                return
            }
            guard let jsonData = jsonContent.data(using: .utf8) else {
                onProcessingError?(self, StreamingError.unknownContent)
                return
            }
            
            var apiError: Error? = nil
            do {
                let decoder = JSONDecoder()
                let object = try decoder.decode(ResultType.self, from: jsonData)
                onReceiveContent?(self, object)
            } catch {
                apiError = error
            }
            
            if let apiError = apiError {
                do {
                    let decoded = try JSONDecoder().decode(APIErrorResponse.self, from: jsonData)
                    onProcessingError?(self, decoded)
                } catch {
                    if index == jsonObjects.count - 1 {
                        previousChunkBuffer = "data: \(jsonContent)" // Chunk ends in a partial JSON
                    } else {
                        onProcessingError?(self, apiError)
                    }
                }
            }
        }
    }
    
}

extension StreamingSession {
    
    // Function to encode the UIImage to base64
    func encodeImageToBase64(_ image: UIImage) -> String? {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return nil }
        return imageData.base64EncodedString()
    }
    
    // Function to create the request payload with the base64 encoded image
    func createRequestPayload(with image: UIImage, question: String) -> Data? {
        guard let base64Image = encodeImageToBase64(image) else { return nil }
        
        let imageMessage: [String: Any] = [
            "type": "image_url",
            "image_url": [
                "url": "data:image/jpeg;base64,\(base64Image)"
            ]
        ]
        
        let textMessage: [String: Any] = [
            "type": "text",
            "text": question
        ]
        
        let message: [String: Any] = [
            "content": [textMessage, imageMessage],
            "role": "user"
        ]
        
        let messages: [[String: Any]] = [message]
        
        let payload: [String: Any] = [
            "model": "gpt-4-vision-preview",
            "messages": messages,
            "max_tokens": 300
        ]
        
        return try? JSONSerialization.data(withJSONObject: payload)
    }
    
    // Function to start the streaming session with an image and a question
    func start(with image: UIImage, question: String, apiKey: String) {
        guard let payload = createRequestPayload(with: image, question: question) else {
            onProcessingError?(self, StreamingError.unknownContent)
            return
        }
        
        var request = urlRequest
        request.httpMethod = "POST"
        request.httpBody = payload
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        self.urlSession
            .dataTask(with: request)
            .resume()
    }
}

func callImageChat() {
    let image = UIImage(named: "CalcLimit")! // Replace with your actual UIImage
    let question = "Solve the equation"
    let apiKey = OPEN_AI_KEY

    let urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!) // Replace with the actual URL
    let streamingSession = StreamingSession<ChatResult>(urlRequest: urlRequest)

    streamingSession.onReceiveContent = { session, result in
        print("streaming result", result)
        print(result.choices.first?.message)
    }

    streamingSession.onProcessingError = { session, error in
        print("streaming error", error)
    }

    streamingSession.onComplete = { session, error in
        print("streaming completed", error)
    }

    streamingSession.start(with: image, question: question, apiKey: apiKey)
}

final class JSONRequest<ResultType> {
    
    let body: Codable?
    let url: URL
    let method: String
    
    init(body: Codable? = nil, url: URL, method: String = "POST") {
        self.body = body
        self.url = url
        self.method = method
    }
}

protocol URLRequestBuildable {
    
    associatedtype ResultType
    
    func build(token: String, organizationIdentifier: String?, timeoutInterval: TimeInterval) throws -> URLRequest
}

extension JSONRequest: URLRequestBuildable {
    
    func build(token: String, organizationIdentifier: String?, timeoutInterval: TimeInterval) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let organizationIdentifier {
            request.setValue(organizationIdentifier, forHTTPHeaderField: "OpenAI-Organization")
        }
        request.httpMethod = method
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }
}


