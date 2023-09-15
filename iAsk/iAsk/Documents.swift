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

enum Path {
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
        if let docExtension = FileType(rawValue: ext) {
            return .doc
        }
        else if let photoExtension = ImageFileType(rawValue: ext) {
            return .photo
        }
        else if let videoExtension = VideoFileType(rawValue: ext) {
            return .video
        }
        else if let soundExtension = AudioFileType(rawValue: ext) {
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
        else if let ext = photoExtension {
            isDownloadableDoc = true
        }
        else if let ext = videoExtension {
            isDownloadableDoc = true
        }
        else if let ext = soundExtension {
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
    return Path.cache.getPath(for: "iAsk/downloads/\(url.hash).\(ext)")
}

func download(url: URL) async throws {
    
    guard let downloadPath = getDownloadURL(for: url) else {
        return
    }
    
    print("downloading url to", downloadPath)
    
    if url.isDownloadable {
        try await downloadFile(from: url, to: downloadPath)
        print("downloaded file")
    }
    else {
        await withCheckedContinuation { continuation in
            Task {
                await Browser.shared.fetchHTML(from: url, completionHandler: { html in
                    print("dumped html", html)
                    print(html)
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
func getDocText(url: URL) -> String? {
    guard let fileType = FileType(rawValue: url.pathExtension) else {
        return nil
    }
    
    guard let path = url.isFileURL ? url : getDownloadURL(for: url) else {
        return nil
    }
    
    if fileType == .pdf {
        return getPDFText(url: url)?.string
    }
    
    do {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return contents
    } catch {
        print("Error reading file: \(error.localizedDescription)")
        return nil
    }
}

func isFileExists(url: URL) -> Bool {
    let fileManager = FileManager.default
    return fileManager.fileExists(atPath: url.path)
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

func searchIndex(url: URL, queryEmbedding: EmbeddingsResult.Embedding) async -> String? {
    guard let embeddingsPath = Path.support.getPath(for: "com.syousif.iAsk/embeddings/\(url.hash)") else {
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
    
    if let records = try? await EmbeddingRecord.read(from: Database.shared.db, primaryKeys: keys.map { "\(hash)\($0)" }) {
        return records.map { "file_path: \($0.dataId)\nchunk index: \($0.chunkId)\nchunk: \($0.chunk)" }.joined(separator: "\n\n")
    }
    
    return nil
}

func indexText(attachment: Attachment) async throws {
    guard let url = attachment.url,
          let fileType = FileType(rawValue: url.pathExtension),
          let text = getDocText(url: url)
    else {
        return
    }
    
    var index = USearchIndex.make(metric: .l2sq, dimensions: 1536, connectivity: 16, quantization: .I8)
    
    let splitter = RecursiveCharacterTextSplitter(separators: getSeparators(forLanguage: fileType), chunkSize: 1000, chunkOverlap: 250)
    
    let chunks = splitter.splitText(text)
    
    let encoder = GPTEncoder()
    
    for chunk in chunks {
        let encoded = encoder.encode(text: chunk)
        print("chunk tokens", encoded.count)
    }
    
    let id = ID(size: 10)
    
    let now = Date()
    
    let dataId = attachment.dataRecord.path
    
    let pathHash = hashString(dataId)
    
    let embeddingId = url.hash
    
    index.reserve(UInt32(chunks.count))
    
    for (i, chunk) in chunks.enumerated() {
        
        if let data = try await getOpenAIEmbedding(text: chunk) {

            let incrementedIndex = UInt64(i + 1)
            
            var embedding = data.embedding.map { Float64($0) }
            
            index.add(key: incrementedIndex, vector: embedding)

            let embeddingRecord = EmbeddingRecord(id: "\(embeddingId)\(incrementedIndex)", dataId: attachment.dataRecord.path, chunkId: String(incrementedIndex), chunk: chunk, embeddingId: embeddingId, createdAt: now)
            
            try await embeddingRecord.write(to: Database.shared.db)
        }
        
        
    }

    let embeddingsPath = Path.support.getPath(for: "com.syousif.iAsk/embeddings/\(pathHash)")
    
    if let embeddingsPath = embeddingsPath {
        let path = embeddingsPath.absoluteString.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!
        index.save(path: path)
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

func interrogatePDF(_ pdf: PDFDocument) {
    let pageCount = pdf.pageCount
    let documentContent = NSMutableAttributedString()

    for i in 0 ..< pageCount {
        guard let page = pdf.page(at: i) else { continue }
        guard let pageContent = page.attributedString else { continue }
        documentContent.append(pageContent)
    }
    let encoder = GPTEncoder()
    let encoded = encoder.encode(text: documentContent.string)
    print("Total number of token(s): \(encoded.count) and character(s): \(documentContent.string.count)")
    let openAI = OpenAI(apiToken: OPEN_AI_KEY)

    let transcript = "extract the key points from the following pdf to text extraction. include psuedo code if applicable:\n\n<EXTRACTION>\(documentContent.string)"

    let query = ChatQuery(model: .gpt3_5Turbo_16k, messages: [.init(role: .system, content: transcript)])

    openAI.chatsStream(query: query) { partialResult in
        switch partialResult {
        case .success(let result):
            if let text = result.choices[0].delta.content {
                print(text)
            }
        case .failure(let error):
            print(error)
        }
    } completion: { error in
        print(error)
    }
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
}
