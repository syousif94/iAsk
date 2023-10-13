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

func isiOSAppOnMac() -> Bool {
    if #available(iOS 14.0, *) {
        return ProcessInfo.processInfo.isiOSAppOnMac
    }
    return false
}

let runningOnMac = isiOSAppOnMac()

extension UIColor {
    static var backgroundColor: UIColor {
        let color = UIColor("#ffffff")
        if #available(iOS 12.0, *) {
            let currentStyle = UITraitCollection.current.userInterfaceStyle
            switch currentStyle {
            case .dark:
                return UIColor("#333333") // Or any other color for dark mode
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
    let (downloadedData, _) = try await URLSession.shared.data(from: sourceURL)
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
