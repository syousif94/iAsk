//
//  Photos.swift
//  iAsk
//
//  Created by Sammy Yousif on 9/14/23.
//

import UIKit
import SwiftUI
import PhotosUI

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
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        var images = [UIImage]()

        for result in results {
            if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                result.itemProvider.loadObject(ofClass: UIImage.self) { (image, error) in
                    if let image = image as? UIImage {
                        images.append(image)
                    }
                }
            }
        }
        
        picker.dismiss(animated: true)

    }

//    func pickerDidCancel(_ picker: PHPickerViewController) {
//        picker.dismiss(animated: true)
//    }
    
}
