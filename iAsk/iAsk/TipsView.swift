//
//  TipsView.swift
//  iAsk
//
//  Created by Sammy Yousif on 12/19/23.
//

import Foundation
import SwiftUI
import NanoID

struct Tip: Identifiable {
    let id: String
    let texts: Text
    
    init(texts: Text) {
        let gen = NanoID.ID()
        self.id = gen.generate()
        self.texts = texts
    }
}

struct TipsView: View {
    
    @EnvironmentObject var chat: ChatViewModel
    
    var showTips: Bool {
        chat.showTips && chat.messages.count < 2
    }
    
    var showQuotaExceeded: Bool = true
    
    @Environment(\.colorScheme) var colorScheme
    
    var bgColor: Color {
        return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
    }
    
    let tips: [Tip] = Application.isCatalyst ? [
        Tip(texts: Text("Press ") + Text("⌘ + enter").foregroundStyle(.green) + Text(" to submit a question")),
        Tip(texts: Text("Press ") + Text("⌘ + n").foregroundStyle(.orange) + Text(" for a new chat")),
        Tip(texts: Text("Press ") + Text("⌘ + o").foregroundStyle(.blue) + Text(" or drop files anywhere in this window to add them")),
        Tip(texts: Text("Click  ") + Text(Image(systemName: "plus")).foregroundStyle(.blue) + Text("  for settings and more")),
        Tip(texts: Text("Scroll  ") + Text(Image(systemName: "chevron.right.2")).foregroundStyle(.blue) + Text("  for your question history")),
        Tip(texts: Text("Share anything with iAsk using  ") + Text(Image(systemName: "square.and.arrow.up")).foregroundStyle(.pink) + Text("  in any other app")),
//        Tip(texts: Text("GPT-4 ").foregroundStyle(.orange) + Text("is much smarter and can handle 4x as much information than the default model")),
        
    ] : [
        Tip(texts: Text("Tap  ") + Text(Image(systemName: "plus")).foregroundStyle(.blue) + Text("  to import documents and manage settings")),
        Tip(texts: Text("Share anything with iAsk using  ") + Text(Image(systemName: "square.and.arrow.up")).foregroundStyle(.pink) + Text("  in any other app")),
        Tip(texts: Text("Swipe  ") + Text(Image(systemName: "chevron.right.2")).foregroundStyle(.blue) + Text("  for your question history")),
        Tip(texts: Text("Tap  ") + Text(Image(systemName: "mic.fill")).foregroundStyle(.blue) + Text("  to speak your question")),
        Tip(texts: Text("Tap  ") + Text(Image(systemName: "play.fill")).foregroundStyle(.green) + Text("  to submit your request")),
        Tip(texts: Text("Swipe  ") + Text(Image(systemName: "chevron.left.2")).foregroundStyle(.blue) + Text("  to scan text with the  ") + Text(Image(systemName: "camera.fill")).foregroundStyle(.blue)),
//        Tip(texts: Text("GPT-4 ").foregroundStyle(.orange) + Text("is much smarter and can handle 4x as much information than the standard model")),
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            
            if showTips {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView(.horizontal) {
                        LazyHStack {
                            ForEach(tips) { tip in
                                TipView(tip: tip)
                            }
                            HStack(alignment: .center) {
                                Spacer()
                                Button(action: {
                                    withAnimation {
                                        chat.showTips = false
                                    }
                                    
                                }) {
                                    Image(systemName: "gearshape.fill")
                                        .foregroundStyle(.white)
                                    Text("Settings")
                                        .foregroundStyle(.white)
                                        .fontWeight(.bold)
                                }
                                .buttonStyle(.plain)
                                .frame(height: 38)
                                .padding(.horizontal)
                                .background(RoundedRectangle(cornerRadius: 19).fill(.blue))
                                
                                Spacer()
                            }
                            .frame(width: 220, height: 110)
                            .padding(.horizontal)
                            .background(RoundedRectangle(cornerRadius: 12).fill(bgColor))
                        }
                        .padding(.horizontal)
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: 110)
                }
                
            }
            
            if showQuotaExceeded {
                QuotaView()
                    .padding(.top)
            }
            
        }
        .padding(.bottom, 100)
    }
}

struct TipView: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    var bgColor: Color {
        return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
    }
    
    let tip: Tip
    
    var body: some View {
        HStack(alignment: .top) {
            tip.texts
                .fontWeight(.bold)
            Spacer()
        }
        .frame(width: 220, height: 110)
        .padding(.horizontal)
        .background(RoundedRectangle(cornerRadius: 12).fill(bgColor))
        
    }
}

struct TipsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TipsView()
        }
        .environmentObject(ChatViewModel())
    }
}

struct QuotaView: View {
    @EnvironmentObject var chat: ChatViewModel
    
    @Environment(\.colorScheme) var colorScheme
    
    var bgColor: Color {
        return .red
//        return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
    }
    
    var questionsThisMonth: Int {
        return chat.settings.gpt35Questions + chat.settings.gpt4Questions
    }
    
    var body: some View {
        if chat.store.purchasedSubscriptions.isEmpty && chat.store.subscriptionsLoaded {
            Button(action: {
                Task {
                    try? await chat.store.purchase(chat.store.subscriptions.first!)
                }
            }) {
                HStack {
                    Text("Please subscribe to support development and hide this message!")
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .padding(.trailing)
                    Spacer()
                    HStack() {
                        Text("$4.99/mo").foregroundStyle(.white).fontWeight(.bold)
                    }
                    .frame(height: 38)
                    .padding(.horizontal)
                    .background(RoundedRectangle(cornerRadius: 19).fill(Color.black.opacity(0.1)))
                }
                
            }
            .buttonStyle(.plain)
            .padding()
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(bgColor))
            .padding(.horizontal)
        }
    }
}
