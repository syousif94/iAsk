//
//  CameraView.swift
//  iAsk
//
//  Created by Sammy Yousif on 10/20/23.
//

import UIKit
import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var camera: CameraViewModel

    func makeUIView(context: Context) -> UIView {
        
        let view = UIView(frame: UIScreen.main.bounds)

        let previewLayer = AVCaptureVideoPreviewLayer(session: camera.captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.layer.bounds
        previewLayer.backgroundColor = UIColor.black.cgColor

        view.layer.addSublayer(previewLayer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct CameraView: View {
    @StateObject var camera = CameraViewModel()
    @State var blurAmount: Double = 1
    
    var backButton: some View {
        Button(action: {
            scrollToPageNotification.send((1, true))
        }) {
            Image(systemName: "chevron.backward")
                .tint(.white)
                .frame(width: 60, height: 60)
        }
        .buttonStyle(BorderlessButtonStyle())
    }
    
    var clearButton: some View {
        Button(action: {
            camera.clearPhoto()
        }) {
            Image(systemName: "xmark")
                .tint(.white)
                .frame(width: 60, height: 60)
        }
        .buttonStyle(BorderlessButtonStyle())
    }
    
    var controlsRow: some View {
        VStack {
            Spacer()
            ZStack {
//                if camera.currentImage != nil {
//                    HStack {
//                        Spacer()
//                        backButton
//                        Spacer()
//                        clearButton
//                        Spacer()
//                    }
//                }
                HStack {
                    Spacer()
                    CameraButton()
                    Spacer()
                }
            }
        }
        .padding(.bottom, 80)
    }

    var body: some View {
        ZStack {
            CameraPreviewView(camera: camera)
                .background(Color.black)
                
            VisualEffectView(effect: UIBlurEffect(style: .dark))
                .opacity(blurAmount)
            
            CameraPhotoViewer()
            
            controlsRow
                
        }
        .background(Color.black)
        .ignoresSafeArea()
        .environmentObject(camera)
        .onChange(of: camera.isActive) { oldValue, newValue in
            if newValue {
                camera.startCamera()
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                    withAnimation(.linear(duration: 0.15)) {
                        blurAmount = 0
                    }
                }
            }
            else {
                camera.stopCamera()
                withAnimation(.linear(duration: 0.15)) {
                    blurAmount = 1
                }
            }
        }
    }
}


struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?
    
    func makeUIView(context: UIViewRepresentableContext<Self>) -> UIVisualEffectView {
        return UIVisualEffectView(effect: effect)
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: UIViewRepresentableContext<Self>) {
        uiView.effect = effect
    }
}

struct CameraPhotoViewer: View {
    @EnvironmentObject var camera: CameraViewModel
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
            
                if let img = camera.currentImage {
                
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        
    }
}

struct CameraButton: View {
    @State private var isPressed = false
    @EnvironmentObject var camera: CameraViewModel

    var body: some View {
        Button(action: {
            if camera.currentImage != nil {
                camera.clearPhoto()
            }
            else {
                camera.takePhoto()
            }
        }) {
            Circle()
                .strokeBorder(Color.white, lineWidth: 4)
                .frame(width: 80, height: 80)
                .scaleEffect(isPressed ? 0.9 : 1.0)
                .animation(.spring(), value: isPressed)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged({ _ in
                    if !isPressed {
                        withAnimation {
                            isPressed = true
                        }
                    }
                })
                .onEnded({ _ in
                    withAnimation {
                        isPressed = false
                    }
                })
        )
    }
}
