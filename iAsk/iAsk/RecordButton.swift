//
//  RecordButton.swift
//  iAsk
//
//  Created by Sammy Yousif on 9/3/23.
//

import SwiftUI

struct RecordButton: View {
    
    @EnvironmentObject var chat: ChatViewModel
    
    @Environment(\.colorScheme) var colorScheme
    
    @Binding var isExpanded: Bool
    
    @State private var isPressed: Bool = false
    
    let circleRadius: CGFloat
    
    var onRecord: (() -> Void)?
    
    var onPause: (() -> Void)?
    
    var onSend: (() -> Void)?

    var body: some View {
        ZStack {
            // Background Shape
            Capsule()
                .foregroundColor(colorScheme == .dark ?
                            Color(red: 1, green: 1, blue: 1, opacity: 0.1) :
                            Color(red: 0, green: 0, blue: 0, opacity: 0.05)
                )
                .frame(width: isExpanded ? circleRadius * 4.5 : circleRadius * 2, height: circleRadius * 2)
                .scaleEffect(isPressed ? 0.95 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: isExpanded)
                .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: isPressed)


            // Icons
            if isExpanded {
                DecibelMeterView(circleRadius: circleRadius, onPause: onPause, onSend: onSend)
                    .transition(.opacity)
                    .transition(.scale)
                    .scaleEffect(isPressed ? 0.95 : 1)
                    .animation(.linear(duration: 0.2), value: isExpanded)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: isPressed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                Button(action: {
                    onRecord?()
                }, label: {
                    VStack {
                        Image(systemName: "mic.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: circleRadius * 1.05, height: circleRadius * 1.05)
                            .tint(chat.proMode ? .orange : .blue)
                            .animation(Animation.linear, value: chat.proMode)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .transition(.scale)
                .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: isPressed)
                .animation(.linear(duration: 0.2), value: isExpanded)
                .background(Color.clear)
                .scaleEffect(isPressed ? 0.95 : 1)
            }
        }
        .frame(width: isExpanded ? circleRadius * 4.5 : circleRadius * 2, height: circleRadius * 2)
        .clipped()
        .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: isExpanded)
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


struct RecordButton_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            RecordButton_Test(isExpanded: false)
            RecordButton_Test(isExpanded: true)
        }
        
    }
    
    struct RecordButton_Test: View {
        @State var isExpanded: Bool
        var body: some View {
            return RecordButton(isExpanded: $isExpanded, circleRadius: 44)
        }
    }
}

struct DecibelMeterView: View {
    @EnvironmentObject var chat: ChatViewModel

    let circleRadius: CGFloat
    
    @State var height: CGFloat = 0
    
    var onPause: (() -> Void)?
    
    var onSend: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                onPause?()
            }, label: {
                VStack {
                    Image(systemName: "pause.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: circleRadius * 1.05)
                        .padding(.leading)
                        .foregroundColor(.orange)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    VStack {
                        HStack(alignment: .bottom) {
                            HStack(alignment: .bottom) {
                                Image(systemName: "pause.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: circleRadius * 1.05, alignment: .bottom)
                                    .foregroundColor(.white)
                                    .padding(.leading)
                                    .opacity(0.2)
                            }
                            .frame(height: height, alignment: .bottom)
                            .clipped()
                        }
                        .frame(height: circleRadius * 1.05, alignment: .bottom)
                        .clipped()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)

            Button(action: {
                onSend?()
            }, label: {
                VStack {
                    Image(systemName: "play.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: circleRadius * 1.05)
                        .padding(.trailing)
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    VStack {
                        HStack(alignment: .bottom) {
                            HStack(alignment: .bottom) {
                                Image(systemName: "play.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: circleRadius * 1.05, alignment: .bottom)
                                    .foregroundColor(.white)
                                    .padding(.trailing)
                                    .opacity(0.2)
                            }
                            .frame(height: height, alignment: .bottom)
                            .clipped()
                        }
                        .frame(height: circleRadius * 1.05, alignment: .bottom)
                        .clipped()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(chat.$decibles, perform: { newValue in
            self.height = max(0, computeHeight(decibles: newValue, radius: circleRadius))
        })
    }

    // Compute height based on dBValue
    func computeHeight(decibles: CGFloat, radius: CGFloat) -> CGFloat {
        let normalizedValue = (decibles + 160) / 160
        let expo = pow(normalizedValue, 2)
        return expo * radius
    }
}
