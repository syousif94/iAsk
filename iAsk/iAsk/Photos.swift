//
//  Photos.swift
//  iAsk
//
//  Created by Sammy Yousif on 9/14/23.
//

import UIKit
import SwiftUI
import PhotosUI
import NanoID

let showPhotoPickerNotification = NotificationPublisher<Bool>()
let showCameraNotification = NotificationPublisher<Bool>()

class CameraPresenter: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    private weak var parentViewController: UIViewController?
    
    init(parentViewController: UIViewController) {
        self.parentViewController = parentViewController
    }
    
    func present() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .camera
        parentViewController?.present(picker, animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        let url = info[.imageURL]
        
        if let image = info[.originalImage] as? UIImage {
//            parent.completionHandler(image)
        }
        
        picker.dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
    
}

class PhotoPickerPresenter: NSObject, PHPickerViewControllerDelegate {
    
    private weak var parentViewController: UIViewController?
    
    init(parentViewController: UIViewController) {
        self.parentViewController = parentViewController
    }
    
    func present() {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 0 // Set to 0 for unlimited selection
        configuration.filter = .images

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        parentViewController?.present(picker, animated: true, completion: nil)
    }
    
    func handleImages(results: [PHPickerResult]) async -> [URL]? {
        let urls = try? await withThrowingTaskGroup(of: URL?.self) { [results] group -> [URL] in
            
            var urls = [URL]()
            
            for result in results {
                group.addTask {
                    await withCheckedContinuation { continuation in
                        if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                            result.itemProvider.loadObject(ofClass: UIImage.self) {(image, error) in
                                if let image = image as? UIImage {
                                    let id = ID(size: 8)
                                    if let url = Disk.support.getPath(for: "imports/\(id.generate()).png"),
                                       let data = image.pngData() {
                                        try? data.write(to: url)
                                        continuation.resume(returning: url)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            for try await url in group {
                if let url = url {
                    urls.append(url)
                }
            }
            
            return urls
            
        }
        
        return urls
    }
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        
        Task {
            async let urlsPromise = handleImages(results: results)
            
            picker.dismiss(animated: true)
            if let urls = await urlsPromise {
                importedDocumentNotification.send(urls)
            }
        }
    }

//    func pickerDidCancel(_ picker: PHPickerViewController) {
//        picker.dismiss(animated: true)
//    }
    
}
