//
//  OfficeDocs.swift
//  iAsk
//
//  Created by Sammy Yousif on 12/29/23.
//

import Foundation
import ZIPFoundation

public class OfficeDocumentExtractor {
    
    public static let shared = OfficeDocumentExtractor()
    
    private init() {}
    
    public func getTextFromDocx(fileUrl url: URL) -> [String]? {
        return getText(fileUrl: url, contentPath: "word/document.xml", textTagPattern: "<w:t.*?>(.*?)<\\/w:t>")
    }
    
    public func getTextFromPptx(fileUrl url: URL) -> [String]? {
        return getText(fileUrl: url, contentPath: "ppt/slides", textTagPattern: "<a:t.*?>(.*?)<\\/a:t>", isDirectory: true)
    }
    
    private func getText(fileUrl url: URL, contentPath: String, textTagPattern: String, isDirectory: Bool = false) -> [String]? {
        var results: [String] = []
        
        do {
            let fileManager = FileManager()
            let destinationURL = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
            
            try fileManager.unzipItem(at: url, to: destinationURL)
            
            let contentURL = destinationURL.appendingPathComponent(contentPath, isDirectory: isDirectory)
            let contentFiles = isDirectory ? try fileManager.contentsOfDirectory(at: contentURL, includingPropertiesForKeys: nil, options: []) : [contentURL]
            
            for contentFile in contentFiles where contentFile.pathExtension == "xml" || !isDirectory {
                let contentData = try Data(contentsOf: contentFile)
                if let contentText = parseContent(contentData, textTagPattern: textTagPattern) {
                    results.append(stripXMLTags(from: contentText))
                }
            }
            
            try fileManager.removeItem(at: destinationURL)
        } catch {
            debugPrint(error.localizedDescription)
        }
        
        return results
    }
    
    private func parseContent(_ data: Data, textTagPattern: String) -> String? {
        let xmlStr = String(data: data, encoding: .utf8)
        return matches(xmlStr ?? "", textTagPattern: textTagPattern)
    }
    
    private func matches(_ originalText: String, textTagPattern: String) -> String {
        var result = [String]()
        
        do {
            let regex = try NSRegularExpression(pattern: textTagPattern, options: [])
            let matches = regex.matches(in: originalText, options: [], range: NSRange(location: 0, length: originalText.utf16.count))
            
            for match in matches {
                result.append((originalText as NSString).substring(with: match.range(at: 1)))
            }
        } catch {
            debugPrint(error.localizedDescription)
        }
        
        return result.joined(separator: "\n")
    }
    
    private func stripXMLTags(from text: String) -> String {
            return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
        }
}
