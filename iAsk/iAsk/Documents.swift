//
//  Documents.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/15/23.
//

import Foundation
import PDFKit
import UIKit
import SwiftUI
import MobileCoreServices
import OpenAI
import GPTEncoder
import Blackbird
import USearch
import NanoID

enum DataType: String, Codable, BlackbirdStringEnum {
    case url = "url"
    case doc = "doc"
    case photo = "photo"
    case video = "video"
    case sound = "sound"
    case folder = "folder"
    case git = "git"
    case unknown = "unknown"
}

enum Disk {
    case cache
    case documents
    case support
    
    func getPath(for path: String) -> URL? {
        var directory: URL? = nil
        
        switch self {
        case .cache:
            directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        case .documents:
            directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        case .support:
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        }
        
        guard var dir = directory else {
            return nil
        }
        
        dir.append(path: path)
        
        do {
            try createFoldersForURLPath(url: dir)
        }
        catch {
            return nil
        }
        
        return dir
    }
}

struct ImageCache {
    static let cacheDirectory: URL = {
        let cachePaths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return cachePaths[0].appendingPathComponent("iAsk/previews")
    }()
    
    static func delete(_ url: URL) {
        let fileURL = getCachePath(url: url)
        deleteFile(at: fileURL)
    }
    
    static func getCachePath(url: URL) -> URL {
        
        let hash = hashString(url.absoluteString)
        
        let path = cacheDirectory.appendingPathComponent(hash).appendingPathExtension("jpg")
        
        try? createFoldersForURLPath(url: path)
        
        return path
    }
    
    static func save(_ image: UIImage, url: URL) {
        let fileURL = getCachePath(url: url)
        if let data = image.jpegData(compressionQuality: 1.0) {
            try? data.write(to: fileURL)
        }
    }
    
    static func get(_ url: URL) -> UIImage? {
        let fileURL = getCachePath(url: url)
        if let data = try? Data(contentsOf: fileURL) {
            return UIImage(data: data)
        }
        return nil
    }
}

extension URL {
    var hash: String {
        return hashString(self.absoluteString)
    }
    
    var dataType: DataType? {
        let ext = self.pathExtension
        if let _ = FileType(rawValue: ext) {
            return .doc
        }
        else if let _ = ImageFileType(rawValue: ext) {
            return .photo
        }
        else if let _ = VideoFileType(rawValue: ext) {
            return .video
        }
        else if let _ = AudioFileType(rawValue: ext) {
            return .sound
        }
        
        return nil
    }
    
    var isDownloadable: Bool {
        let ext = self.pathExtension
        
        let docExtension = FileType(rawValue: ext)
        let photoExtension = ImageFileType(rawValue: ext)
        let videoExtension = VideoFileType(rawValue: ext)
        let soundExtension = AudioFileType(rawValue: ext)
        
        var isDownloadableDoc = false
        
        if let ext = docExtension, ext != .html, ext != .php {
            isDownloadableDoc = true
        }
        else if let _ = photoExtension {
            isDownloadableDoc = true
        }
        else if let _ = videoExtension {
            isDownloadableDoc = true
        }
        else if let _ = soundExtension {
            isDownloadableDoc = true
        }
        
        return isDownloadableDoc
    }
}

func getDownloadURL(for url: URL) -> URL? {
    var ext = url.pathExtension
    if ext.isEmpty {
        ext = "html"
    }
    return Disk.cache.getPath(for: "iAsk/downloads/\(url.hash).\(ext)")
}

func download(url: URL) async throws {
    
    guard let downloadPath = getDownloadURL(for: url) else {
        return
    }
    
    print("downloading url to",url.absoluteString, downloadPath)
    
    if url.isDownloadable {
        try await downloadFile(from: url, to: downloadPath)
        print("downloaded url to file", url.absoluteString, downloadPath.absoluteString)
    }
    else {
        await withCheckedContinuation { continuation in
            Task {
                await Browser.shared.fetchHTML(from: url, completionHandler: { html in
                    print("dumped html to file",url.absoluteString, downloadPath.absoluteString)
                    try? html?.write(to: downloadPath, atomically: true, encoding: .utf8)
                })
                continuation.resume()
            }
        }
    }
}


func getCachedPreview(url: URL, cacheGenerator: () async -> UIImage?) async -> UIImage? {

    if let image = ImageCache.get(url) {
        return image
    }
    
    return await cacheGenerator()
}

func getUrlPreview(url: URL) async -> UIImage? {
    await getCachedPreview(url: url) {
        let image = await withCheckedContinuation { continuation in
            Task {
                await Browser.shared.takeURLSnapshot(url) { image in
                    continuation.resume(returning: image)
                }
            }
        }
        if let image = image {
            ImageCache.save(image, url: url)
            return image
        }
        return nil
    }
}

func getVideoPreview(url: URL) async -> UIImage? {
    await getCachedPreview(url: url) {
        let path = ImageCache.getCachePath(url: url)
        do {
            let _ = try await makeVideoThumbnail(url: url, outputURL: path)
        }
        catch {
            return nil
        }
        return ImageCache.get(path)
    }
}

func getPDFPreview(url: URL) async -> UIImage? {
    await getCachedPreview(url: url) {
        guard let document = CGPDFDocument(url as CFURL) else { return nil }
        guard let page = document.page(at: 1) else { return nil }

        let pageRect = page.getBoxRect(.mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        let img = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(pageRect)

            ctx.cgContext.translateBy(x: 0.0, y: pageRect.size.height)
            ctx.cgContext.scaleBy(x: 1.0, y: -1.0)

            ctx.cgContext.drawPDFPage(page)
        }
        
        ImageCache.save(img, url: url)

        return img
    }
}

func getPDFText(url: URL) -> NSMutableAttributedString? {
    if let pdf = PDFDocument(url: url) {
        let pageCount = pdf.pageCount
        let documentContent = NSMutableAttributedString()

        for i in 0 ..< pageCount {
            guard let page = pdf.page(at: i) else { continue }
            guard let pageContent = page.attributedString else { continue }
            documentContent.append(pageContent)
        }
        
        return documentContent
    }
    return nil
}

/// handles getting the text from any url
func extractText(url: URL) -> String? {
    
    guard let path = url.isFileURL ? url : getDownloadURL(for: url) else {
        return nil
    }
    
    let dataType = url.dataType
    
    if dataType == .doc, let fileType = FileType(rawValue: url.pathExtension) {
        // FIXME: extract the text from image based pdfs
        if fileType == .pdf {
            return getPDFText(url: url)?.string
        }
        
        // FIXME: handle office docs
        
        if fileType == .doc {
            
        }
        if fileType == .docx {
            
        }
        if fileType == .xlsx {
            
        }
        if fileType == .pptx {
            
        }
        
        // For all other data types, we can read the strings as utf-8
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            return contents
        } catch {
            print("Error reading file: \(error.localizedDescription)")
            return nil
        }
    }
    else if dataType == .photo {
        
    }
    
    return nil
}

func isFolder(url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    let fileManager = FileManager.default
    let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
    return exists && isDirectory.boolValue
}

func getDataType(url: URL) -> DataType {
    
    if !url.isFileURL {
        return .url
    }
    
    if isFolder(url: url) {
        return .folder
    }
    
    let ext = url.pathExtension.lowercased()
    
    if let _ = ImageFileType(rawValue: ext) {
        return .photo
    }
    if let _ = FileType(rawValue: ext) {
        return .doc
    }
    if let _ = VideoFileType(rawValue: ext) {
        return .video
    }
    if let _ = AudioFileType(rawValue: ext) {
        return .sound
    }
    
    return .unknown
}

func getOpenAIEmbedding(text: String) async throws -> EmbeddingsResult.Embedding? {
    
    let query = EmbeddingsQuery(model: .textEmbeddingAda, input: text)
    
    let openAI = OpenAI(apiToken: OPEN_AI_KEY)
    
    let result = try await openAI.embeddings(query: query)
    
    return result.data.first
}

func getEmbeddingURL(for url: URL) -> URL? {
    return Disk.support.getPath(for: "com.syousif.iAsk/embeddings/\(url.hash)")
}

struct ScoredEmbedding {
    let score: Float
    let record: EmbeddingRecord
}

func searchIndex(url: URL, queryEmbedding: EmbeddingsResult.Embedding) async -> [ScoredEmbedding]? {
    guard let embeddingsPath = getEmbeddingURL(for: url),
            fileExists(at: embeddingsPath) else {
        return nil
    }
    
    let index = USearchIndex.make(metric: .l2sq, dimensions: 1536, connectivity: 16, quantization: .I8)
    
    let path = embeddingsPath.absoluteString.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!
    
    index.load(path: path)
    
    let (keys, scores) = index.search(vector: queryEmbedding.embedding, count: 5)
    
    print(keys, scores)
    
    var scoresDict = [UInt64: Float]()
    
    for (index, key) in keys.enumerated() {
        scoresDict[key] = scores[index]
    }
    
    let hash = url.hash
    
    if let embeddings = try? await EmbeddingRecord.read(from: Database.shared.db, primaryKeys: keys.map { "\(hash)\($0)" }) {
        return embeddings.compactMap { record -> ScoredEmbedding? in
            guard let index = UInt64(record.chunkId), let score = scoresDict[index] else {
                return nil
            }
            let scoredEmbedding = ScoredEmbedding(score: score, record: record)
            return scoredEmbedding
        }
    }
    
    return nil
}

func indexText(attachment: Attachment) async throws {
    
    guard let url = attachment.url, let text = extractText(url: url) else {
        return
    }
    
    let fileType = FileType(rawValue: url.pathExtension) ?? FileType.txt
    
    let index = USearchIndex.make(metric: .l2sq, dimensions: 1536, connectivity: 16, quantization: .I8)
    
    let splitter = RecursiveCharacterTextSplitter(separators: getSeparators(forLanguage: fileType), chunkSize: 1000, chunkOverlap: 250)
    
    let chunks = splitter.splitText(text)
    
    let encoder = GPTEncoder()
    
    for chunk in chunks {
        let encoded = encoder.encode(text: chunk)
        print("chunk tokens", encoded.count)
    }

    let now = Date()
    
    let dataId = attachment.dataRecord.path
    
    let embeddingId = url.hash
    
    index.reserve(UInt32(chunks.count))
    
    await withThrowingTaskGroup(of: Void.self) { group in
        
        for (i, chunk) in chunks.enumerated() {
            
            group.addTask {
                if let data = try await getOpenAIEmbedding(text: chunk) {

                    let i = UInt64(i)
                    
                    let embedding = data.embedding.map { Float64($0) }
                    
                    index.add(key: i, vector: embedding)

                    let embeddingRecord = EmbeddingRecord(id: "\(embeddingId)\(i)", dataId: attachment.dataRecord.path, chunkId: String(i), chunk: chunk, embeddingId: embeddingId, createdAt: now)
                    
                    try await embeddingRecord.write(to: Database.shared.db)
                }
            }
            
        }
        
    }

    let embeddingsPath = getEmbeddingURL(for: url)
    
    if let embeddingsPath = embeddingsPath {
        let path = embeddingsPath.absoluteString.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!
        index.save(path: path)
    }
}

func answer(query: String, url: URL, onToken: @escaping (_ token: String, _ index: Int, _ jobIndex: Int) -> Void) async {
    let encoder = GPTEncoder()
    
    let promptEncoding = encoder.encode(text: query)
    
    let openAI = OpenAI(apiToken: OPEN_AI_KEY)
    
    if let text = extractText(url: url), let fileType = FileType(rawValue: url.pathExtension) {
        
        let splitter = RecursiveCharacterTextSplitter(separators: getSeparators(forLanguage: fileType), chunkSize: 6000, chunkOverlap: 250)
        
        let chunks = splitter.splitText(text)
        
        let answers = try? await withThrowingTaskGroup(of: String.self) { group in
            var answerChunks = [String]()
            
            for (index, chunk) in chunks.enumerated() {
                
                let systemPrompt = """
                Extract relevant information to the user's question from the following context. If there is no relevant information to the question, say "There is no relevant information to the question".
                ---
                \(chunk)
                """
                
                let query = ChatQuery(model: .gpt3_5Turbo_16k, messages: [
                    .init(role: .system, content: chunk),
                    .init(role: .user, content: query)
                ])
                
                group.addTask {
                    await withCheckedContinuation { continuation in
                        
                        var summary = ""
                        
                        openAI.chatsStream(query: query) { partialResult in
                            switch partialResult {
                            case .success(let result):
                                if let text = result.choices[0].delta.content {
                                    summary += text
                                    onToken(text, result.choices[0].index, index)
                                }
                            case .failure(let error):
                                print(error)
                            }
                        } completion: { error in
                            if let error = error {
                                print(error)
                                continuation.resume(returning: "")
                                return
                            }
                            
                            continuation.resume(returning: summary)
                        }
                    }
                }
                
            }
            
            for try await result in group {
                answerChunks.append(result)
            }
            
            return answerChunks
        }
        
    }
}

func summarize(_ text: String, onToken: @escaping (_ token: String) -> Void) async -> String? {
    let encoder = GPTEncoder()
    let encoded = encoder.encode(text: text)
    print("Total number of token(s): \(encoded.count) and character(s): \(text.count)")
    let openAI = OpenAI(apiToken: OPEN_AI_KEY)

    let transcript = "Extract the key points from the following text and include code examples if applicable:\n\n<TEXT>\(text)"

    let query = ChatQuery(model: .gpt3_5Turbo_16k, messages: [.init(role: .system, content: transcript)])
    
    return await withCheckedContinuation { continuation in
        
        var summary = ""
        
        openAI.chatsStream(query: query) { partialResult in
            switch partialResult {
            case .success(let result):
                if let text = result.choices[0].delta.content {
                    summary += text
                    onToken(text)
                }
            case .failure(let error):
                print(error)
            }
        } completion: { error in
            if let error = error {
                print(error)
                continuation.resume(returning: nil)
                return
            }
            
            continuation.resume(returning: summary)
        }
    }
}

func getRequiredFiles(chatModel: ChatViewModel) async -> [URL]? {
    let attachments = chatModel.latestAttachments
    
    let chatMessages = chatModel.latestAiMessages
    
    if !attachments.isEmpty {
        
        let excludingSystem = chatMessages.dropFirst()
        
        let urls = try? await withThrowingTaskGroup(of: URL?.self, body: { group in
            var urls = [URL]()
            
            for attachment in attachments {
                if let url = attachment.url {
                    group.addTask {
                        let isLocal = url.isFileURL
                        let urlText = isLocal ? url.absoluteString : getDownloadURL(for: url)?.absoluteString
                        let chatHistory = excludingSystem.map { "\($0.role): \($0.content ?? "")" }.joined(separator: "\n")
                        var messages: [Chat] = [
                            .init(role: .system, content: """
                            Do you need to read this file?

                            file_path: \(urlText ?? "")
                            """)
                        ]
                        
                        messages += excludingSystem
                        
                        let needsDoc = await determine(messages)
                        
                        if needsDoc {
                            print("needs the file", url)
                            return url
                        }
                        
                        return nil
                    }
                }
            }
            
            for try await url in group {
                if let url = url {
                    urls.append(url)
                }
            }
            
            return urls
        })
        
        return urls
        
    }
    
    return nil
}

func readFiles(urls: [URL], getTerms: () async -> [String]) async -> String? {
    let encoder = GPTEncoder()
    
    var totalEstimatedTokens: Int = 0
    
    var ragFiles = [URL]()
    
    var researchText = ""
    
    var loaded = Set<URL>()
    
    for url in urls {
        if let text = extractText(url: url) {
            let encoded = encoder.encode(text: text)
            let textURL = (url.isFileURL ? url : getDownloadURL(for: url))!.absoluteString
            if encoded.count < 10000 {
                totalEstimatedTokens += encoded.count
                loaded.insert(url)
                researchText += """
                file_path: \(textURL)
                text: \(text)
                """
            }
            else {
                ragFiles.append(url)
            }
        }
    }
    
    if !ragFiles.isEmpty {
        let terms = await getTerms()
        if !terms.isEmpty, let ragEmbeddings = await getRagEmbeddings(searchTerms: terms, urls: ragFiles) {
            for embedding in ragEmbeddings {
                researchText += """
                file_path: \(embedding.record.dataId)
                chunkId: \(embedding.record.chunkId)
                query similarity score: \(embedding.score)
                text: \(embedding.record.chunk)
                """
            }
        }
        
    }
    
    return researchText
}

func getTextForChat(chatModel: ChatViewModel) async -> String? {
    
    let attachments = chatModel.latestAttachments
    
    let urls = attachments.compactMap { $0.url }
    
    print("loading urls for chat", urls)
    
    guard !urls.isEmpty else {
        return nil
    }

    return await readFiles(urls: urls) {
        return await getTerms(for: chatModel)
    }
}

func getTerms(for chatModel: ChatViewModel) async -> [String] {
    let chatMessages = chatModel.latestAiMessages
    let excludingSystem = chatMessages.dropFirst()
    let chatHistory = excludingSystem.map { "\($0.role): \($0.content ?? "")" }.joined(separator: "\n")
    print("chat history", chatHistory)
    let searchTerms = await extractTerms([
        .init(role: .system, content: "Come up with research questions for the following chat history:\n\n \(chatHistory)")
    ])
    
    print("retrieved search terms for model", searchTerms)
    
    return searchTerms
}

func getRagEmbeddings(searchTerms: [String], urls: [URL]) async -> [ScoredEmbedding]? {
    
    let embedded = try? await withThrowingTaskGroup(of: [ScoredEmbedding].self) { group -> [ScoredEmbedding] in
        
        var embeddings = [ScoredEmbedding]()
        
        for term in searchTerms {
            group.addTask {
                return await getEmbeddings(for: term, urls: urls) ?? []
            }
        }
        
        for try await results in group {
            embeddings += results
        }
        
        return embeddings
    }
    
    return embedded
}

func getEmbeddings(for prompt: String, urls: [URL]) async -> [ScoredEmbedding]? {
    guard let questionEmbedding = try? await getOpenAIEmbedding(text: prompt) else {
        return []
    }
    
    let scoredEmbeddingsForDocs = try? await withThrowingTaskGroup(of: [ScoredEmbedding]?.self) { group -> [ScoredEmbedding] in
        
        var scoredEmbeddingsForDocs = [ScoredEmbedding]()
        
        for url in urls {
            group.addTask {
                return await searchIndex(url: url, queryEmbedding: questionEmbedding)
            }
        }
        
        for try await embeddings in group {
            if let embeddings = embeddings {
                scoredEmbeddingsForDocs += embeddings
            }
        }

        return scoredEmbeddingsForDocs
    }
    
    return scoredEmbeddingsForDocs
}

enum ImageFileType: String {
    case apng
    case bmp
    case gif
    case jpeg
    case jpg
    case png
    case svg
    case tif
    case tiff
    case webp
    case heic
}

enum AudioFileType: String {
    case mp3
    case wav
    case aiff
    case flac
    case aac
    case ogg
    case wma
    case m4a
    case opus
    case vox
    case alac
    case m4p
}

enum VideoFileType: String {
    case _3g2 = "3g2"
    case _3gp = "3gp"
    case avi
    case m4v
    case mkv
    case mov
    case mp4
    case mpeg
    case mpg
    case webm
    case wmv
}

enum FileType: String {
    case txt
    case doc
    case docx
    case odt
    case rtf
    case xls
    case xlsx
    case ppt
    case pptx
    case pdf
    case c
    case cpp
    case cs
    case py
    case java
    case pyc
    case rb
    case js
    case jsx
    case html
    case css
    case scss
    case sass
    case php
    case swift
    case go
    case rs
    case ts
    case tsx
    case scala
    case perl
    case lua
    case r
    case matlab
    case vb
    case groovy
    case kt
    case dart
    case coffee
    case asm
    case h
    case hpp
    case csproj
    case pb
    case proto
    case md
    case rst
    case tex
    case sol
    case csv
    case tsv
}
