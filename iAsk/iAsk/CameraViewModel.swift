//
//  CameraViewModel.swift
//  iAsk
//
//  Created by Sammy Yousif on 10/20/23.
//

import Foundation
import UIKit
import SwiftUI
import Combine
import AVFoundation
import NanoID

class CameraViewModel: NSObject, ObservableObject {
    let captureSession: AVCaptureSession
    
    let photoOutput = AVCapturePhotoOutput()
    
    var currentInput: AVCaptureDeviceInput?
    
    @Published var isActive = false
    
    @Published var currentImage: UIImage?
    
    override init() {
        self.captureSession = AVCaptureSession()
        super.init()
        
        
        
        if let input = getInput() {
            captureSession.beginConfiguration()
            currentInput = input
            captureSession.addInput(input)
            captureSession.sessionPreset = .photo
            captureSession.addOutput(photoOutput)
            captureSession.commitConfiguration()
        }
        else {
            return
        }
    }
    
    private func getInput() -> AVCaptureDeviceInput? {
        guard let cam = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: cam) else {
            return nil
        }
        
        return input
    }

    func startCamera() {
        DispatchQueue.global().async {
            self.captureSession.startRunning()
        }
    }

    func stopCamera() {
        DispatchQueue.global().async {
            self.captureSession.stopRunning()
        }
    }
    
    func takePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func clearPhoto() {
        currentImage = nil
    }
}

extension CameraViewModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        guard let imageData = photo.fileDataRepresentation(), let uiImage = UIImage(data: imageData) else { return }
        
        DispatchQueue.main.async {
            self.currentImage = uiImage
        }
        
        let id = ID(size: 6)
        
        guard let url = Disk.support.getPath(for: "imports/camera/\(id.generate()).jpg") else {
            return
        }
        
        writeImageToDisk(image: uiImage, url: url)
        
        importedDocumentNotification.send([url])
    }
}

func writeImageToDisk(image: UIImage, url: URL) {
    if let data = image.jpegData(compressionQuality: 1.0) {
        do {
            try data.write(to: url)
            print("Image saved successfully at \(url.absoluteString)")
        } catch {
            print("Error saving image: \(error.localizedDescription)")
        }
    }
}
