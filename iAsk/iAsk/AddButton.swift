//
//  AddButton.swift
//  iAsk
//
//  Created by Sammy Yousif on 9/29/23.
//

import SwiftUI

struct AddButton<Content: View>: View {
    
    @EnvironmentObject var chat: ChatViewModel
    
    @Environment(\.colorScheme) var colorScheme
    
    let label: Content
    
    let bgPadding: CGFloat
    
    init(bgPadding: CGFloat = 0, @ViewBuilder label: () -> Content) {
        self.bgPadding = bgPadding
        self.label = label()
    }
    
    
    
    var bgColor: Color {
        return colorScheme == .dark ?
            Color(red: 1, green: 1, blue: 1, opacity: 0.1) :
            Color(red: 0, green: 0, blue: 0, opacity: 0.05)
    }
    
    var body: some View {
        Menu() {
            Button(action: {
                chat.menuShown = false
                Task {
                    await chat.resetChat()
                    DispatchQueue.main.async {
                        self.chat.scrollProxy?.scrollTo("top", anchor: .top)
                    }
                    
                }
            }) {
                Label("New Chat", systemImage: "plus.bubble")
            }
            
            Button(action: {
                if Application.isCatalyst {
                    chat.saveDialog()
                }
                else {
                    chat.shareDialog()
                }
                chat.menuShown = false
            }) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            
            Divider()
            
            Button(action: {
                showCameraNotification.send(true)
                chat.menuShown = false
            }) {
                Label("Camera", systemImage: "camera")
            }
            
            Button(action: {
                showDocumentsNotification.send(true)
                chat.menuShown = false
            }) {
                Label("Documents", systemImage: "doc.on.doc")
            }
            
            Button(action: {
                showPhotoPickerNotification.send(true)
                chat.menuShown = false
            }) {
                Label("Photos", systemImage: "photo.on.rectangle.angled")
            }
            
            Button(action: {
                showWebNotification.send(true)
                chat.menuShown = false
            }) {
                Label("Browser", systemImage: "safari")
            }
            
//                            Button(action: {
//                                startGoogleSignInNotification.send(())
//                                chat.menuShown = false
//                            }) {
//                                Label("Google Account", systemImage: "person.crop.circle")
//                            }
            
            Divider()
            
            Toggle(isOn: $chat.proMode) {
                Label("Use GPT4", systemImage: "brain.head.profile")
            }
            
            Button(action: {

            }) {
                Label("Settings", systemImage: "gearshape")
            }
            
        } label: {
            label
        }
        .simultaneousGesture(TapGesture().onEnded {
            chat.menuShown = !chat.menuShown
        })
        .menuStyle(.borderlessButton)
        .background(
            Circle()
                .fill(bgColor)
                .padding(bgPadding)
                
        )
    }
}
