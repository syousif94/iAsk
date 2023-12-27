//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Sammy Yousif on 10/28/23.
//

import UIKit
import Social
import UniformTypeIdentifiers
import SwiftUI

@objc(ShareViewController)
class ShareViewController: UINavigationController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        
        retrieveSharedURLs { [weak self] urls in
            
            guard let urls = urls else {
                let error = NSError(domain: "me.syousif.iAsk", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to retrieve the url"])
                self?.extensionContext?.cancelRequest(withError: error)
                return
            }

            guard var components = URLComponents(string: "iask://share_extension") else {
                let error = NSError(domain: "me.syousif.iAsk", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create the components"])
                self?.extensionContext?.cancelRequest(withError: error)
                return

            }
            
            components.queryItems = urls.map { URLQueryItem(name: "share_url", value: $0.absoluteString) } 
            guard let deepLinkURL = components.url else {
                let error = NSError(domain: "me.syousif.iAsk", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create the deep-link url"])
                self?.extensionContext?.cancelRequest(withError: error)
                return

            }
            
            if let `self` = self {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.extensionContext?.completeRequest(returningItems: [], completionHandler: { _ in
                        
                        _ = self.openURL(deepLinkURL)
                    })
                    
                }
                
            }
            
            
        }
    }
    
    func retrieveSharedURLs(_ completion: @escaping ([URL]?) -> ()) {
        let attachments = (extensionContext?.inputItems as? [NSExtensionItem])?
            .reduce([], { $0 + ($1.attachments ?? []) }) ?? []
        
        var urls = [URL]()
        
        let fileManager = FileManager.default
        let appGroupDirectory = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.me.syousif.iAsk")!
        
        let group = DispatchGroup()

        for attachment in attachments {
            if let fileType = attachment.registeredTypeIdentifiers.first {
                group.enter()
                print("file type", fileType)
                
                if fileType == UTType.url.identifier {
                    print("its a url")
                    print("pause")
                    let _ = attachment.loadObject(ofClass: URL.self, completionHandler: { url, error in
                        if let url = url {
                            urls.append(url)
                        }
                        
                        group.leave()
                    })
                    break
                }
                else if fileType == "public.image" {
                    let _ = attachment.loadItem(forTypeIdentifier: fileType) { data, error in
                        var contentData: Data? = nil

                        if let data = data as? Data {
                            contentData = data
                        } else if let url = data as? URL {
                            contentData = try? Data(contentsOf: url)
                        }
                        else if let imageData = data as? UIImage {
                            contentData = imageData.pngData()
                        }
                        
                        if let data = contentData, let image = UIImage(data: data) {
                            let destinationURL = appGroupDirectory.appendingPathComponent(generateRandomString(length: 6)).appendingPathExtension("png")
                            try? image.pngData()?.write(to: destinationURL, options: [.atomic])
                            urls.append(destinationURL)
                        }
                        
                        group.leave()
                    }
                }
                else {
                    attachment.loadFileRepresentation(forTypeIdentifier: fileType) { (url, error) in
                        guard let url = url else {
                            print("Error loading file representation: \(String(describing: error))")
                            group.leave()
                            return
                        }
                        
                        let _ = url.startAccessingSecurityScopedResource()
                        
                        let destinationURL = appGroupDirectory.appendingPathComponent(url.lastPathComponent)
                        do {
                            if fileManager.fileExists(atPath: destinationURL.path) {
                                try fileManager.removeItem(at: destinationURL)
                            }
                            try fileManager.copyItem(at: url, to: destinationURL)
                            urls.append(destinationURL)
                        } catch {
                            print("Error moving file to app group: \(error)")
                        }
                        url.stopAccessingSecurityScopedResource()
                        group.leave()
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            completion(urls)
        }
    }
    
    @objc func openURL(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                return application.perform(#selector(openURL(_:)), with: url) != nil
            }
            responder = responder?.next
        }
        return false
    }
}

func generateRandomString(length: Int) -> String {
    let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    let randomCharacters = (0..<length).compactMap { _ in characters.randomElement() }
    return String(randomCharacters)
}
