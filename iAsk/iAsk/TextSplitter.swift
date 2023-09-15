//
//  TextSplitter.swift
//  iAsk
//
//  Created by Sammy Yousif on 9/5/23.
//

import Foundation

protocol Document {
    var pageContent: String { get set }
    var metadata: [String: Any] { get set }
}

protocol TextSplitter {
    func splitText(_ text: String) -> [String]
}

class BaseTextSplitter: TextSplitter {
    var chunkSize: Int
    var chunkOverlap: Int
    var lengthFunction: (String) -> Int
    var keepSeparator: Bool
    var addStartIndex: Bool
    
    init(
        chunkSize: Int = 4000,
        chunkOverlap: Int = 200,
        lengthFunction: @escaping (String) -> Int = { $0.count },
        keepSeparator: Bool = false,
        addStartIndex: Bool = false
    ) {
        guard chunkOverlap <= chunkSize else {
            fatalError("chunkOverlap should be less than or equal to chunkSize")
        }
        self.chunkSize = chunkSize
        self.chunkOverlap = chunkOverlap
        self.lengthFunction = lengthFunction
        self.keepSeparator = keepSeparator
        self.addStartIndex = addStartIndex
    }
    
    func splitText(_ text: String) -> [String] {
        // To be overridden by subclasses
        return []
    }
    
    private func joinDocs(_ docs: [String], with separator: String) -> String? {
        let text = docs.joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
        
    func mergeSplits(_ splits: [String], with separator: String) -> [String] {
        let separatorLength = lengthFunction(separator)
        
        var docs: [String] = []
        var currentDoc: [String] = []
        var totalLength = 0
        
        for doc in splits {
            let docLength = lengthFunction(doc)
            if totalLength + docLength + (currentDoc.isEmpty ? 0 : separatorLength) > chunkSize {
                if totalLength > chunkSize {
                    print("Warning: Created a chunk of size \(totalLength), which is longer than the specified \(chunkSize)")
                }
                if !currentDoc.isEmpty {
                    if let mergedDoc = joinDocs(currentDoc, with: separator) {
                        docs.append(mergedDoc)
                    }
                    while totalLength > chunkOverlap || (!currentDoc.isEmpty && totalLength + docLength + separatorLength > chunkSize) {
                        if let firstDoc = currentDoc.first {
                            totalLength -= lengthFunction(firstDoc) + (currentDoc.count > 1 ? separatorLength : 0)
                        }
                        currentDoc.removeFirst()
                    }
                }
            }
            currentDoc.append(doc)
            totalLength += docLength + (currentDoc.isEmpty ? 0 : separatorLength)
        }
        
        if let mergedDoc = joinDocs(currentDoc, with: separator) {
            docs.append(mergedDoc)
        }
        
        return docs
    }
}

class RecursiveCharacterTextSplitter: BaseTextSplitter {
    var separators: [String]
    var isSeparatorRegex: Bool
    
    init(
        separators: [String]? = nil,
        keepSeparator: Bool = true,
        isSeparatorRegex: Bool = false,
        chunkSize: Int = 4000,
        chunkOverlap: Int = 200
    ) {
        self.separators = separators ?? ["\n\n", "\n", " ", ""]
        self.isSeparatorRegex = isSeparatorRegex
        super.init(chunkSize: chunkSize, chunkOverlap: chunkOverlap, keepSeparator: keepSeparator)
    }
    
    func split(string: String, withRegex pattern: String, prependMatch: Bool = false) -> [String]? {
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let nsString = string as NSString
            let matches = regex.matches(in: string, options: [], range: NSRange(location: 0, length: nsString.length))
            
            var lastEnd = 0
            var results = [String]()
            
            for match in matches {
                let range = match.range
                
                if prependMatch {
                    let matchedString = nsString.substring(with: range)
                    let substring = nsString.substring(with: NSRange(location: lastEnd, length: range.location - lastEnd))
                    results.append(substring)
                    results.append(matchedString)
                } else {
                    let substring = nsString.substring(with: NSRange(location: lastEnd, length: range.location + range.length - lastEnd))
                    results.append(substring)
                }
                
                lastEnd = range.location + range.length
            }
            
            if lastEnd < nsString.length {
                let substring = nsString.substring(from: lastEnd)
                results.append(substring)
            }
            
            return results
        } catch {
            print("Invalid regex pattern: \(error.localizedDescription)")
            return nil
        }
    }

    
    private func splitText(_ text: String, _ separators: [String]) -> [String] {
        var finalChunks: [String] = []
        
        var separator = separators.last ?? ""
        var newSeparators: [String] = []
        
        for (i, _s) in separators.enumerated() {
            let _separator = isSeparatorRegex ? _s : NSRegularExpression.escapedPattern(for: _s)
            if _s.isEmpty {
                separator = _s
                break
            }
            if let _ = text.range(of: _separator, options: .regularExpression) {
                separator = _s
                newSeparators = Array(separators.dropFirst(i+1))
                break
            }
        }
        
        guard let splits = split(string: text, withRegex: separator, prependMatch: keepSeparator) else {
            return []
        }
        
        var goodSplits: [String] = []
        
        for s in splits {
            if s.count < chunkSize {
                goodSplits.append(s)
            } else {
                if !goodSplits.isEmpty {
                    let mergedText = mergeSplits(goodSplits, with: separator)
                    finalChunks.append(contentsOf: mergedText)
                    goodSplits.removeAll()
                }
                
                if newSeparators.isEmpty {
                    finalChunks.append(s)
                } else {
                    let otherInfo = splitText(s, newSeparators)
                    finalChunks.append(contentsOf: otherInfo)
                }
            }
        }
        
        if !goodSplits.isEmpty {
            let mergedText = mergeSplits(goodSplits, with: separator)
            finalChunks.append(contentsOf: mergedText)
        }
        
        return finalChunks
    }
    
    override func splitText(_ text: String) -> [String] {
        return splitText(text, separators)
    }
}

func getSeparators(forLanguage language: FileType) -> [String] {
    switch language {
    case .cpp:
        return ["\nclass ", "\nvoid ", "\nint ", "\nfloat ", "\ndouble ", "\nif ", "\nfor ", "\nwhile ", "\nswitch ", "\ncase ", "\n\n", "\n", " ", ""]
    case .go:
        return ["\nfunc ", "\nvar ", "\nconst ", "\ntype ", "\nif ", "\nfor ", "\nswitch ", "\ncase ", "\n\n", "\n", " ", ""]
    case .java:
        return ["\nclass ", "\npublic ", "\nprotected ", "\nprivate ", "\nstatic ", "\nif ", "\nfor ", "\nwhile ", "\nswitch ", "\ncase ", "\n\n", "\n", " ", ""]
    case .js, .ts:
        return ["\nfunction ", "\nconst ", "\nlet ", "\nvar ", "\nclass ", "\nif ", "\nfor ", "\nwhile ", "\nswitch ", "\ncase ", "\ndefault ", "\n\n", "\n", " ", ""]
    case .php:
        return ["\nfunction ", "\nclass ", "\nif ", "\nforeach ", "\nwhile ", "\ndo ", "\nswitch ", "\ncase ", "\n\n", "\n", " ", ""]
    case .proto, .pb:
        return ["\nmessage ", "\nservice ", "\nenum ", "\noption ", "\nimport ", "\nsyntax ", "\n\n", "\n", " ", ""]
    case .py:
        return ["\nclass ", "\ndef ", "\n\tdef ", "\n\n", "\n", " ", ""]
    case .rst:
        return ["\n=+\n", "\n-+\n", "\n\\*+\n", "\n\n.. *\n\n", "\n\n", "\n", " ", ""]
    case .rb:
        return ["\ndef ", "\nclass ", "\nif ", "\nunless ", "\nwhile ", "\nfor ", "\ndo ", "\nbegin ", "\nrescue ", "\n\n", "\n", " ", ""]
    case .rs:
        return ["\nfn ", "\nconst ", "\nlet ", "\nif ", "\nwhile ", "\nfor ", "\nloop ", "\nmatch ", "\nconst ", "\n\n", "\n", " ", ""]
    case .scala:
        return ["\nclass ", "\nobject ", "\ndef ", "\nval ", "\nvar ", "\nif ", "\nfor ", "\nwhile ", "\nmatch ", "\ncase ", "\n\n", "\n", " ", ""]
    case .swift:
        return ["\nfunc ", "\nclass ", "\nstruct ", "\nenum ", "\nif ", "\nfor ", "\nwhile ", "\ndo ", "\nswitch ", "\ncase ", "\n\n", "\n", " ", ""]
    case .md:
        return ["\n#{1,6} ", "```\n", "\n\\*\\*\\*+\n", "\n---+\n", "\n___+\n", "\n\n", "\n", " ", ""]
    case .tex:
        return ["\n\\\\chapter{", "\n\\\\section{", "\n\\\\subsection{", "\n\\\\subsubsection{", "\n\\\\begin{enumerate}", "\n\\\\begin{itemize}", "\n\\\\begin{description}", "\n\\\\begin{list}", "\n\\\\begin{quote}", "\n\\\\begin{quotation}", "\n\\\\begin{verse}", "\n\\\\begin{verbatim}", "\n\\\\begin{align}", "$$", "$", " ", ""]
    case .html:
        return ["<body", "<div", "<p", "<br", "<li", "<h1", "<h2", "<h3", "<h4", "<h5", "<h6", "<span", "<table", "<tr", "<td", "<th", "<ul", "<ol", "<header", "<footer", "<nav", "<head", "<style", "<script", "<meta", "<title", ""]
    case .sol:
        return ["\npragma ", "\nusing ", "\ncontract ", "\ninterface ", "\nlibrary ", "\nconstructor ", "\ntype ", "\nfunction ", "\nevent ", "\nmodifier ", "\nerror ", "\nstruct ", "\nenum ", "\nif ", "\nfor ", "\nwhile ", "\ndo while ", "\nassembly ", "\n\n", "\n", " ", ""]
    default:
        return ["\n\n", "\n", " ", ""]
    }
}
