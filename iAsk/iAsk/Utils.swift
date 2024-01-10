//
//  Utils.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/8/23.
//

import Foundation
import UIKit
import SwiftUI
import CryptoKit
import NanoID
import Combine

extension UIColor {
    static var backgroundColor: UIColor {
        let color = UIColor("#ffffff")
        if #available(iOS 12.0, *) {
            let currentStyle = UITraitCollection.current.userInterfaceStyle
            switch currentStyle {
            case .dark:
                return UIColor("#2b3136") // Or any other color for dark mode
            case .light, .unspecified:
                return color // Or any other color for light mode
            @unknown default:
                return color
            }
        } else {
            // Fallback for earlier versions than iOS 12.0
            return color
        }
    }
    
    static var borderColor: UIColor {
        let color = UIColor("#e0e0e0")
        if #available(iOS 12.0, *) {
            let currentStyle = UITraitCollection.current.userInterfaceStyle
            switch currentStyle {
            case .dark:
                return UIColor("#ffffff").withAlphaComponent(0.05) // Or any other color for dark mode
            case .light, .unspecified:
                return color // Or any other color for light mode
            @unknown default:
                return color
            }
        } else {
            // Fallback for earlier versions than iOS 12.0
            return color
        }
    }
    
    static var imageTint: UIColor {
        let color = UIColor.black
        if #available(iOS 12.0, *) {
            let currentStyle = UITraitCollection.current.userInterfaceStyle
            switch currentStyle {
            case .dark:
                return UIColor.white // Or any other color for dark mode
            case .light, .unspecified:
                return color // Or any other color for light mode
            @unknown default:
                return color
            }
        } else {
            // Fallback for earlier versions than iOS 12.0
            return color
        }
    }
}

extension Color {
    init(hex: String, alpha: Double = 1) {
        var cString:String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var rgbValue:UInt32 = 10066329 //color #999999 if string has wrong format

        if (cString.hasPrefix("#")) {
            cString.remove(at: cString.startIndex)
        }

        if ((cString.count) == 6) {
            Scanner(string: cString).scanHexInt32(&rgbValue)
        }
        
        self.init(
            .sRGB,
            red: Double((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: Double((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgbValue & 0x0000FF) / 255.0,
            opacity: alpha
        )
    }
}

extension UIColor {
    convenience init(_ hex: String, alpha: CGFloat = 1.0) {
        var cString:String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var rgbValue:UInt32 = 10066329 //color #999999 if string has wrong format

        if (cString.hasPrefix("#")) {
            cString.remove(at: cString.startIndex)
        }

        if ((cString.count) == 6) {
            Scanner(string: cString).scanHexInt32(&rgbValue)
        }

        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: alpha
        )
    }
}

struct Application {

    static let isCatalyst: Bool = {
    #if targetEnvironment(macCatalyst)
        true
    #else
        false
    #endif
    }()
    
    static let isPad: Bool = {
        return UIDevice.current.userInterfaceIdiom == .pad || isCatalyst
    }()
    
    static var keyWindow: UIWindow? {
      let allScenes = UIApplication.shared.connectedScenes
      for scene in allScenes {
        guard let windowScene = scene as? UIWindowScene else { continue }
        for window in windowScene.windows where window.isKeyWindow {
           return window
         }
       }
        return nil
    }

}

func createFoldersForURLPath(url: URL) throws {
    let fileManager = FileManager.default
    let folderPath = url.deletingLastPathComponent().path
    
    try fileManager.createDirectory(atPath: folderPath, withIntermediateDirectories: true, attributes: nil)
}

func hashString(_ string: String) -> String {
    let inputData = Data(string.utf8)
    let hashedData = SHA256.hash(data: inputData)
    let hashString = hashedData.compactMap { String(format: "%02x", $0) }.joined()
    return hashString
}

func copyToClipboard(text: String) {
    // Create a new instance of UIPasteboard
    let pasteboard = UIPasteboard.general

    // Set the string to be copied to the clipboard
    pasteboard.string = text

    // Check if the code was successfully copied to the clipboard
    #if DEBUG
    if let copiedCode = pasteboard.string {
        print("Code copied to clipboard: \(copiedCode)")
    } else {
        print("Failed to copy code to clipboard")
    }
    #endif
}

func fileExists(at url: URL) -> Bool {
    let fileManager = FileManager.default
    return fileManager.fileExists(atPath: url.path)
}

func moveFile(from sourceURL: URL, to destinationURL: URL) {
    let fileManager = FileManager.default
    
    do {
        // Remove the destination file if it exists
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        // Move the file
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        print("File moved successfully")
    } catch {
        print("Error moving file: \(error)")
    }
}

func copyFile(from sourceURL: URL, to destinationURL: URL) {
    let fileManager = FileManager.default
    
    do {
        // Remove the destination file if it exists
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        // Move the file
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        print("File moved successfully")
    } catch {
        print("Error moving file: \(error)")
    }
}

func changeFileExtension(url: URL, newExtension: String) -> URL? {
    let newURL = url.deletingPathExtension().appendingPathExtension(newExtension)
    
    do {
        let fileManager = FileManager.default
        try fileManager.moveItem(at: url, to: newURL)
        return newURL
    } catch {
        print("Error changing file extension: \(error)")
        return nil
    }
}

func downloadFile(from sourceURL: URL, to destinationURL: URL) async throws {
    let session = URLSession(configuration: .default)
    let (downloadedData, _) = try await session.data(from: sourceURL)
    try downloadedData.write(to: destinationURL)
}

func deleteFile(at url: URL) {
    let fileManager = FileManager.default
    
    do {
        try fileManager.removeItem(at: url)
        print("File deleted successfully")
    } catch {
        print("Error deleting file: \(error)")
    }
}

extension String {
    func toCache(ext: String = "md") throws -> URL? {
        let gen = ID(size: 8)
        let id = gen.generate()
        if let url = Disk.cache.getPath(for: "exports/\(id)/export.\(ext)") {
            try write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        return nil
    }
}

func showAlert(alert: UIAlertController) {
    if let rootController = Application.keyWindow?.rootViewController {
        rootController.present(alert, animated: true, completion: nil)
    }
}

struct RoundedCornersShape: Shape {
    func path(in rect: CGRect) -> Path {
        var bPath = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        var path = Path(bPath.cgPath)
        return path
    }
    
    var corners: UIRectCorner
    var radius: CGFloat
}

extension Array where Element: Hashable {
    func unique<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var uniqueValues = Set<T>()
        return filter { uniqueValues.insert($0[keyPath: keyPath]).inserted }
    }
}

func isSubstring(mainString: String, subString: String) -> Bool {
    return mainString.contains(subString)
}

func getLastWord(string: String) -> String {
    let words = string.split(separator: " ")
    return String(words.last ?? "")
}

func splitString(mainString: String, separator: String) -> [String] {
    return mainString.components(separatedBy: separator)
}

extension UIView {
    func screenshot() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(bounds.size, false, UIScreen.main.scale)
        drawHierarchy(in: bounds, afterScreenUpdates: true)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image!
    }
}

func extractJSONValue(from jsonString: String, forKey key: String) -> String? {
    // Pattern to capture values for a given key. This considers strings, numbers, booleans, and null as possible values.
    // This pattern also makes sure to capture incomplete values if they are at the end.
    let pattern = "\"\(key)\"\\s*:\\s*(?:(\"[^\"]*(?:\"|$))|([0-9]+(\\.[0-9]+)?)|(true|false|null))"
    
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return nil
    }
    
    guard let match = regex.firstMatch(in: jsonString, options: [], range: NSRange(location: 0, length: jsonString.utf16.count)) else {
        return nil
    }
    
    for i in 1..<match.numberOfRanges {
        if let range = Range(match.range(at: i), in: jsonString) {
            var result = String(jsonString[range])
            if result.hasPrefix("\"") {
                result = String(result.dropFirst())
            }
            if result.hasSuffix("\"") {
                result = String(result.dropLast())
            }
            return result
        }
    }
    return nil
}

extension Sequence {
    func group<T: Hashable>(by keyFunc: (Element) -> T) -> [T: [Element]] {
        var dict = [T: [Element]]()
        for element in self {
            let key = keyFunc(element)
            if case nil = dict[key]?.append(element) { dict[key] = [element] }
        }
        return dict
    }
}

func isURLPrecededByColon(url: String, in text: String) -> Bool {
    // Escape the URL to safely include it in the regex pattern
    let escapedURL = NSRegularExpression.escapedPattern(for: url)
    // Pattern to match a colon followed by zero or more spaces and then the URL
    let pattern = ":(\\s*)\(escapedURL)"
    
    do {
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        
        // If we find at least one match, return true
        return !matches.isEmpty
    } catch {
        print("Invalid regex: \(error.localizedDescription)")
        return false
    }
}

extension Color {

    var components: (r: Double, g: Double, b: Double, o: Double)? {
        let uiColor: UIColor
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var o: CGFloat = 0

        if self.description.contains("NamedColor") {
            let lowerBound = self.description.range(of: "name: \"")!.upperBound
            let upperBound = self.description.range(of: "\", bundle")!.lowerBound
            let assetsName = String(self.description[lowerBound..<upperBound])

            uiColor = UIColor(named: assetsName)!
        } else {
            uiColor = UIColor(self)
        }

        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &o) else { return nil }
        return (Double(r), Double(g), Double(b), Double(o))
    }

    func interpolateTo(color: Color, fraction: Double) -> Color {
        let s = self.components!
        let t = color.components!

        let r: Double = s.r + (t.r - s.r) * fraction
        let g: Double = s.g + (t.g - s.g) * fraction
        let b: Double = s.b + (t.b - s.b) * fraction
        let o: Double = s.o + (t.o - s.o) * fraction

        return Color(red: r, green: g, blue: b, opacity: o)
    }
}

struct ChildSizeReader<Content: View>: View {
    @Binding var size: CGSize
    let content: () -> Content
    var body: some View {
        ZStack {
            content()
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: SizePreferenceKey.self, value: proxy.size)
                    }
                )
        }
        .onPreferenceChange(SizePreferenceKey.self) { preferences in
            self.size = preferences
        }
    }
}

struct SizePreferenceKey: PreferenceKey {
    typealias Value = CGSize
    static var defaultValue: Value = .zero

    static func reduce(value _: inout Value, nextValue: () -> Value) {
        _ = nextValue()
    }
}

struct ViewOffsetKey: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue = CGFloat.zero
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value += nextValue()
    }
}

class TextDetector {
    private let detector: NSDataDetector
    
    init?() {
        let types: NSTextCheckingResult.CheckingType = [.address]
           guard let detector = try? NSDataDetector(types: types.rawValue) else {
               return nil
           }
        
        self.detector = detector
    }
    
    func replaceAddresses(in text: String) -> NSMutableString {
        let mutableText = NSMutableString(string: text) // Create a mutable copy of the text
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        
        // Iterate over the matches in reverse order
        for match in matches.reversed() {
            if let range = Range(match.range, in: text),
               let matchText = text[range].addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "http://maps.apple.com/?q=\(matchText)") {
                let markdownLink = "[\(text[range])](\(url))"
                mutableText.replaceCharacters(in: match.range, with: markdownLink)
            }
        }
        
        return mutableText
    }
}
