//
//  DocumentPicker.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/7/23.
//

import UIKit
import MobileCoreServices
import SwiftUI
import PDFKit
import MobileCoreServices
import GPTEncoder
import OpenAI

let importedDocumentNotification = NotificationPublisher<[URL]>()
let showDocumentsNotification = NotificationPublisher<Bool>()
let showSaveNotification = NotificationPublisher<[URL]>()

class DocumentPickerPresenter: NSObject, UIDocumentPickerDelegate {
    
    private weak var parentViewController: UIViewController?
    
    init(parentViewController: UIViewController) {
        self.parentViewController = parentViewController
    }
    
    var isSaving = false
    
    func presentSaveDialog(urls: [URL]) {
        isSaving = true
        let documentPicker = UIDocumentPickerViewController(forExporting: urls)
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .fullScreen
        parentViewController?.present(documentPicker, animated: true, completion: nil)
    }
    
    func presentDocumentPicker() {
        isSaving = false
        let documentTypes: [String] = [
            kUTTypeFolder as String,
            kUTTypePDF as String,
            kUTTypePlainText as String,
            "com.microsoft.word.doc",
            "org.openxmlformats.wordprocessingml.document",
            "com.microsoft.excel.xls",
            "org.openxmlformats.spreadsheetml.sheet",
            "com.microsoft.powerpoint.ppt",
            "org.openxmlformats.presentationml.presentation",
            kUTTypeJSON as String,
            kUTTypeImage as String,
            kUTTypeMovie as String,
            kUTTypeSourceCode as String
        ]
        
        let documentPicker = UIDocumentPickerViewController(documentTypes: documentTypes, in: .import)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = true
        documentPicker.modalPresentationStyle = .fullScreen
        parentViewController?.present(documentPicker, animated: true, completion: nil)
    }
    
    // MARK: - UIDocumentPickerDelegate
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if isSaving {
            return
        }
        // Handle selected documents
        guard urls.first != nil else { return }
        
        var movedURLs = [URL]()
        
        for url in urls {
            if let newPath = Path.support.getPath(for: "imports/\(url.lastPathComponent)") {
                moveFile(from: url, to: newPath)
                movedURLs.append(newPath)
            }
        }
        
        importedDocumentNotification.send(movedURLs)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print("Document picker was cancelled")
    }
}
