//
//  Latex.swift
//  iAsk
//
//  Created by Sammy Yousif on 1/3/24.
//

import Foundation
import SwiftMath
import UIKit

func replaceLatexWithImage(in text: String) -> String {
    let pattern = "\\\\\\[(.*?)\\\\\\]|\\\\\\((.*?)\\\\\\)"
    var modifiedText = text

    do {
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(text.startIndex..., in: text)
        
        let matches = regex.matches(in: text, options: [], range: range).reversed()
        for match in matches {
            if let matchRange = Range(match.range, in: text) {
                let equation = String(text[matchRange])
                let imageName = hashString(equation)
                let markdownImage = "![equation](images/\(imageName).png)"
                modifiedText.replaceSubrange(matchRange, with: markdownImage)
            }
        }
    } catch {
        print("Invalid regex: \(error.localizedDescription)")
    }

    return modifiedText
}

class LaTeXImageMarkdownConverter {
    private let imageGenerator: LaTeXImageGenerator

    init(imageGenerator: LaTeXImageGenerator) {
        self.imageGenerator = imageGenerator
    }

    func convertLatexToMarkdown(in text: String) -> String {
        let pattern = "\\\\\\[(.*?)\\\\\\]|\\\\\\((.*?)\\\\\\)"
        var modifiedText = text

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let range = NSRange(text.startIndex..., in: text)
            
            let matches = regex.matches(in: text, options: [], range: range).reversed()
            for match in matches {
                if let matchRange = Range(match.range, in: text) {
                    let equation = String(text[matchRange])
                    if let _ = self.imageGenerator.image(from: equation) {
                        let fileURL = self.imageGenerator.cacheURL(for: equation)
                        let markdownImageLink = "![equation](\(fileURL.absoluteString.replacingOccurrences(of: "@\(Int(UIScreen.main.scale))x", with: "")))"
                        modifiedText = modifiedText.replacingOccurrences(of: equation, with: markdownImageLink)
                    }
                }
            }
        } catch {
            print("Invalid regex: \(error.localizedDescription)")
        }

        return modifiedText
    }
}

class LaTeXImageGenerator {
    private let cacheDirectory: URL
    
    init() {
        // Get the URL for the caches directory
        let fileManager = FileManager.default
        if let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            self.cacheDirectory = cacheDir
        } else {
            fatalError("Unable to access caches directory.")
        }
    }
    
    func cacheURL(for latex: String) -> URL {
        // Use a simple hashing function to create a unique filename for each LaTeX string
        let hashedName = hashString(latex)
        return Disk.cache.getPath(for: "latex/\(hashedName)@\(Int(UIScreen.main.scale))x.png")!
    }
    
    func image(from latex: String) -> UIImage? {
        let fileURL = cacheURL(for: latex)
        
        // Check if the image is already cached
        if let cachedImage = UIImage(contentsOfFile: fileURL.path) {
            return cachedImage
        }
        
        let text = latex
            .replacingOccurrences(of: "{{", with: "{")
            .replacingOccurrences(of: "}}", with: "}")
            .replacingOccurrences(of: "\\[", with: "")
            .replacingOccurrences(of: "\\]", with: "")
            .replacingOccurrences(of: "\\(", with: "")
            .replacingOccurrences(of: "\\)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        print(text)
        
        let mathImage = MTMathImage(latex: text, fontSize: 18, textColor: .label)
        mathImage.font = MTFontManager().termesFont(withSize: 18)
        mathImage.contentInsets = .init(top: 12, left: 4, bottom: 0, right: 4)
        
        let (_, image) = mathImage.asImage()
        
        if let imageData = image?.pngData() {
            do {
                try imageData.write(to: fileURL)
            } catch {
                print("Error saving image: \(error)")
                return nil
            }
        }
        
        return image
    }
}
