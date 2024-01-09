//
//  SubscriptionView.swift
//  iAsk
//
//  Created by Sammy Yousif on 12/10/23.
//

import SwiftUI
import OpenAI
import MarkdownUI

struct SubscriptionView: View {
    
    let chat: ChatViewModel
    
    @Environment(\.colorScheme) var colorScheme
    
    let spaceName = "scroll"
    @State var wholeSize: CGSize = .zero
    @State var scrollViewSize: CGSize = .zero
    @State var hasReachedBottom = false
    
    var imageName: String {
        colorScheme == .light ? "Intro" : "IntroDark"
    }
    
    var backgroundColor: SwiftUI.Color {
        colorScheme == .light ? .white : Color(hex: "#121212")
    }
    
    var blurStyle: UIBlurEffect.Style {
        colorScheme == .light ? .extraLight : .dark
    }
    
    func getCardWidth(width: CGFloat) -> CGFloat {
        return min(width - 60, 380)
    }
    
    var body: some View {
        ZStack {
            ChildSizeReader(size: $wholeSize) {
                GeometryReader { geometry in
                    let cardWidth = getCardWidth(width: geometry.size.width)
                    let maxWidth = cardWidth * 4 + 10 * 3 + 30
                    ScrollView {
                        ChildSizeReader(size: $scrollViewSize) {
                            VStack(spacing: 0) {
                                ZStack {
                                    Image(imageName)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: geometry.size.width, height: geometry.size.height * 0.5)
                                    VisualEffectView(effect: UIBlurEffect(style: blurStyle))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    Image(imageName)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .mask(LinearGradient(stops: [.init(color: backgroundColor, location: 0), .init(color: backgroundColor.opacity(0), location: 0.95)], startPoint: .top, endPoint: .bottom))
                                        .frame(width: geometry.size.width, height: geometry.size.height * 0.5)
                                    LinearGradient(stops: [.init(color: backgroundColor.opacity(0), location: 0.6), .init(color: backgroundColor, location: 1)], startPoint: .top, endPoint: .bottom)
                                }
                                .clipShape(Rectangle())
                                Text("Welcome to iAsk")
                                    .font(.largeTitle.weight(.light))
                                    .foregroundStyle(.primary)
                                Text("Your personal AI assistant and research partner")
                                    .frame(width: 220)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                                    .padding(.top)
                                    .padding(.bottom, 28)
                                
                                
                                
                                
                                HStack {
                                    Text("Get AI help with everything")
                                        .font(.title2.weight(.bold))
                                    Spacer()
                                }
                                .padding(.horizontal, 28)
                                .padding(.top, 28)
                                .frame(maxWidth: maxWidth)
                                
                                HStack {
                                    Text("Share, drag, or paste files and links into iAsk to get immediate help. It works with most text documents and web pages.")
                                    Spacer()
                                }
                                .padding(.top, 8)
                                .padding(.horizontal, 28)
                                .padding(.bottom, 24)
                                .frame(maxWidth: maxWidth)
                                
                                ScrollView(.horizontal) {
                                    LazyHStack(alignment: .top, spacing: 20) {
                                        
                                        AnalyzeExampleView()
                                            .frame(width: cardWidth, alignment: .leading)
                                        
                                        VisionExampleView()
                                            .frame(width: cardWidth, alignment: .leading)
                                        
                                        OrderExampleView()
                                            .frame(width: cardWidth, alignment: .leading)
                                        
                                        ConvertExampleView()
                                            .frame(width: cardWidth, alignment: .leading)
                                    }
                                    .padding(.horizontal)
                                    .scrollTargetLayout()
                                }
                                .scrollTargetBehavior(.viewAligned)
                                .frame(maxWidth: maxWidth)
                                
                                HStack {
                                    Text("Use realtime information")
                                        .font(.title2.weight(.bold))
                                    Spacer()
                                }
                                .padding(.horizontal, 28)
                                .padding(.top, 28)
                                .frame(maxWidth: maxWidth)
                                
                                HStack {
                                    Text("iAsk can execute search queries to retrieve information its missing.")
                                    Spacer()
                                }
                                .padding(.top, 8)
                                .padding(.horizontal, 28)
                                .padding(.bottom, 24)
                                .frame(maxWidth: maxWidth)
                                
                                ScrollView(.horizontal) {
                                    LazyHStack(alignment: .top, spacing: 20) {
                                        
                                        CodeExampleView()
                                            .frame(width: cardWidth, alignment: .leading)
                                        
                                        ResearchExampleView()
                                            .frame(width: cardWidth, alignment: .leading)
                                        
                                        ExplainExampleView()
                                            .frame(width: cardWidth, alignment: .leading)
                                    }
                                    .padding(.horizontal)
                                    .scrollTargetLayout()
                                }
                                .scrollTargetBehavior(.viewAligned)
                                .frame(maxWidth: maxWidth)
                                
                                Text("Subscribe to get unlimited access.\nNon subscribers are limited to 15 questions a month and may bankrupt Sammy.")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 40)
                                    .padding(.horizontal)
                                
                                Button(action: {
                                    Task {
                                        do {
                                            let _ = try await chat.store.purchase(chat.store.subscriptions.first!)
                                            await chat.store.updateCustomerProductStatus()
                                            if chat.store.purchasedSubscriptions.first != nil {
                                                chat.introShown = true
                                                showIntroNotification.send(false)
                                            }
                                        }
                                        catch {
                                            
                                        }
                                    }
                                }, label: {
                                    HStack {
                                        Text("Subscribe")
                                            .fontWeight(.bold)
                                            .padding()
                                        HStack() {
                                            Text("$4.99/mo").foregroundStyle(.white).fontWeight(.bold)
                                        }
                                        .frame(height: 38)
                                        .padding(.horizontal)
                                        .background(RoundedRectangle(cornerRadius: 19).fill(Color.black.opacity(0.1)))
                                    }
                                })
                                .buttonStyle(.borderedProminent)
                                .padding(.top, 40)
                                

                                
                                Button(action: {
                                    Task {
                                        await chat.store.updateCustomerProductStatus()
                                        if chat.store.purchasedSubscriptions.first != nil {
                                            chat.introShown = true
                                            showIntroNotification.send(false)
                                        }
                                    }
                                }, label: {
                                    Text("Restore Purchases")
                                        .padding()
                                })
                                .padding(.top, 60)
                                .padding(.bottom, 20)
                                
                            }
                            .frame(width: geometry.size.width)
                            .offset(y: -40)
                            .background(
                                GeometryReader { proxy in
                                    backgroundColor.preference(
                                            key: ViewOffsetKey.self,
                                            value: -1 * proxy.frame(in: .named(spaceName)).origin.y
                                        )
                                    }
                                )
                            .onPreferenceChange(
                                ViewOffsetKey.self,
                                perform: { value in
                                    print("offset: \(value)") // offset: 1270.3333333333333 when User has reached the bottom
                                    print("height: \(scrollViewSize.height)") // height: 2033.3333333333333
                                    
                                    if value > 1 {
                                        hasReachedBottom = true
                                    }
                                    else {
                                        hasReachedBottom = false
                                    }

//                                                        if value >= scrollViewSize.height - wholeSize.height - 40 {
//                                                            hasReachedBottom = true
//                                                            print("User has reached the bottom of the ScrollView.")
//                                                        } else {
//                                                            hasReachedBottom = false
//                                                            print("not reached.")
//                                                        }
                                }
                            )
                        }
                    }
                    .scrollIndicators(.hidden)
                    .background(backgroundColor)
                }
                .ignoresSafeArea()
            }
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        chat.introShown = true
                        showIntroNotification.send(false)
                    }, label: {
                        Text("Skip")
                            .padding(.vertical, 20)
                            .padding(.horizontal, 32)
                    })
                    
                }
                Spacer()
            }
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    HStack {
                        Image(systemName: "arrow.down")
                            .foregroundStyle(.white)
                            .fontWeight(.bold)
                        Text("Scroll Down")
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 16)
                    .frame(height: 19 * 2)
                    .background(
                        RoundedRectangle(cornerRadius: 19)
                            .fill(Color.black)
                            .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 2)
                    )
                    Spacer()
                }
                .padding(.bottom, 40)
            }
            .opacity(hasReachedBottom ? 0 : 1)
            .animation(.linear, value: hasReachedBottom)
        }
    }
}

struct ChatExampleView<Content: View>: View {
    
    struct Document: Hashable, Identifiable {
        var id: String {
            return "\(self.hashValue)"
        }
        
        let name: String
        let imageName: String
    }
    
    let documents: [Document]
    
    let outputDocuments: [Document]
    
    let userMessage: String
    
    let outputMessage: Content
    
    @Environment(\.colorScheme) var colorScheme
    
    var backgroundColor: SwiftUI.Color {
        colorScheme == .light ? Color(hex: "#000000", alpha: 0.05) : Color.white.opacity(0.05)
    }

    init(documents: [Document] = [], userMessage: String, outputDocuments: [Document] = [],  @ViewBuilder outputMessage: () -> Content) {
        self.documents = documents
        self.outputMessage = outputMessage()
        self.outputDocuments = outputDocuments
        self.userMessage = userMessage
    }
    
    var sideLength: CGFloat = 140
    
    @ViewBuilder func getDocumentView(documents: [Document]) -> some View {
        if !documents.isEmpty {
            HStack {
                ForEach(documents) { doc in
                    ZStack {
                        Image(doc.imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: sideLength, height: sideLength * 1.2)
                        
                        VStack(alignment: .leading) {
                            Spacer()
                            VStack(alignment: .leading, spacing: 0) {
                                Spacer()
                                HStack {
                                    Text(doc.name)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .padding(.bottom, 4)
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(3)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity)
                                
                            }
                            .padding(.horizontal, 4)
                            .frame(width: sideLength, height: sideLength * 0.75)
                            .background(
                                LinearGradient(gradient: Gradient(colors: [Color(hex: "#000000", alpha: 0), Color(hex: "#000000", alpha: 0.7)]), startPoint: .top, endPoint: .bottom)
                            )
                        }
                        .frame(width: sideLength, height: sideLength * 1.2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            getDocumentView(documents: documents)
            
            Text(userMessage)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                
                .font(.system(size: 24, weight: .bold))
                .padding(.horizontal)
                .padding(.bottom)
            
            outputMessage
            
            getDocumentView(documents: outputDocuments)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400, maxHeight: 400, alignment: .leading)
        .padding(8)
        .padding(.top)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 25))
    }
}

struct VisionExampleView: View {
    var body: some View {
        ChatExampleView(documents: [
            .init(name: "Invite.jpg", imageName: "Invite")
        ], userMessage: "Add this to my calendar") {
            NewEventMessageView(message:
                Message(record: .init(
                    chatId: "",
                    createdAt: .now,
                    content: """
                    {
                        "title": "Holiday Party",
                        "location": "421 Milford St, Glendale, CA",
                        "startDate": "2023-12-16 21:00",
                        "endDate": "2023-12-17 2:00"
                    }
                    """,
                    role: .function,
                    messageType: .newEvents)
                )
            )
        }
    }
}

struct AnalyzeExampleView: View {
    
    var messageView: some View {
        Markdown("""
        | Expense | Date | Amount |
        | --- | --- | --- |
        | Github | 11/01/23 | $9.99 |
        | OPENAI | 11/30/23 | $43,169.22 |
        | Total | 11/31/23 | $43,179.21 |
        """)
            .padding(.leading)
            .multilineTextAlignment(.leading)
            .markdownBlockStyle(\.table, body: { configuration in
                configuration.label
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )
            })
            .markdownTableBackgroundStyle(.alternatingRows(Color.white.opacity(0.1), Color.black.opacity(0.05), header: Color.black.opacity(0.1)))
            .markdownTableBorderStyle(.init(.allBorders, color: .clear, strokeStyle: .init(lineWidth: 0)))
            .tableStyle(.inset)
            .markdownBlockStyle(\.paragraph, body: { configuration in
                VStack {
                    configuration
                        .label
                        .relativeLineSpacing(.em( Application.isPad ? 0.25 : 0.08))
                }
            })
            .markdownTextStyle(\.code) {
                FontFamilyVariant(.monospaced)
                FontWeight(.bold)
            }
            .fixedSize(horizontal: false, vertical: true)
    }
    
    var body: some View {
        ChatExampleView(documents: [
            .init(name: "Bank Statement.pdf", imageName: "Analysis")
        ], userMessage: "What are my business expenses") {
            messageView
        }
    }
}

struct ResearchExampleView: View {
    var messageView: some View {
        Markdown("""
        * Warriors at Lakers, Tuesday 7:30pm
        
        * Clippers at Lakers, Friday 7:30pm
        """)
            .padding(.bottom)
            .padding(.leading)
            .multilineTextAlignment(.leading)
            .markdownBlockStyle(\.table, body: { configuration in
                configuration.label
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )
            })
            .markdownTableBackgroundStyle(.alternatingRows(.clear, .clear, header: Color.black.opacity(0.1)))
            .markdownTableBorderStyle(.init(.allBorders, color: .clear, strokeStyle: .init(lineWidth: 0)))
            .tableStyle(.inset)
            .markdownBlockStyle(\.paragraph, body: { configuration in
                VStack {
                    configuration
                        .label
                        .relativeLineSpacing(.em( Application.isPad ? 0.25 : 0.08))
                }
            })
            .markdownTextStyle(\.code) {
                FontFamilyVariant(.monospaced)
                FontWeight(.bold)
            }
            .fixedSize(horizontal: false, vertical: true)
    }
    
    var body: some View {
        ChatExampleView(userMessage: "What home lakers games are this month?") {
            VStack(alignment: .leading) {
                SearchingMessageView(message: Message(record: .init(
                    chatId: "",
                    createdAt: .now,
                    content: "",
                    role: .assistant,
                    messageType: .text)
                ))
                messageView
            }
        }
    }
}

struct CodeExampleView: View {
    var text = """
    Start by creating a `KeyMap` object for keeping track of the pressed keys.
    
    ```typescript
    const keyMap = {
        w: false,
        a: false,
        s: false,
        d: false
    }
    ```
    """
    
    @Environment(\.colorScheme) var colorScheme
    
    var messageView: some View {
        Markdown(text)
            .padding(.horizontal)
            .multilineTextAlignment(.leading)
            .markdownCodeSyntaxHighlighter(.highlightr(theme: colorScheme == .dark ? "monokai" : "xcode"))
            .markdownBlockStyle(\.codeBlock, body: { configuration in
                ScrollView(.horizontal, showsIndicators: false) {
                    if Application.isPad {
                        configuration.label
                              .relativeLineSpacing(.em(0.25))
                              .padding()
                    }
                    else {
                        configuration.label
                              .relativeLineSpacing(.em(0.25))
                              .markdownTextStyle {
                                  FontSize(14)
                              }
                              .padding()
                    }
                }
                .background(Color(hex: "#000000", alpha: 0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .markdownMargin(top: .em(0.8), bottom: .em(0.8))
            })
            .markdownBlockStyle(\.table, body: { configuration in
                configuration.label
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )
            })
            .markdownTableBackgroundStyle(.alternatingRows(.clear, .clear, header: Color.black.opacity(0.1)))
            .markdownTableBorderStyle(.init(.allBorders, color: .clear, strokeStyle: .init(lineWidth: 0)))
            .tableStyle(.inset)
            .markdownBlockStyle(\.paragraph, body: { configuration in
                VStack {
                    configuration
                        .label
                        .relativeLineSpacing(.em( Application.isPad ? 0.25 : 0.08))
                }
            })
            .markdownTextStyle(\.code) {
                FontFamilyVariant(.monospaced)
                FontWeight(.bold)
            }
    }
    
    var body: some View {
        ChatExampleView(documents: [
            .init(name: "/example.html", imageName: "WebCode"),
            .init(name: "App.tsx", imageName: "Code")
        ], userMessage: "How do I integrate this code with my code?") {
            messageView
        }
    }
}

struct ConvertExampleView: View {
    var body: some View {
        ChatExampleView(documents: [
            .init(name: "Video.mp4", imageName: "Video")
        ], userMessage: "Crop this for social media", outputDocuments: [
            .init(name: "Video-cropped.mp4", imageName: "Video")
        ]) {
            
        }
    }
}

struct ExplainExampleView: View {
    
    var text = """
    Sure, here is a breakdown:
    
    ### Monthly Rent
    - **Who Pays**: Tenant
    - **Amount**: $2000/month
    """
    
    var messageView: some View {
        Markdown(text)
            .padding(.leading)
            .multilineTextAlignment(.leading)
            .markdownBlockStyle(\.table, body: { configuration in
                configuration.label
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )
            })
            .markdownTableBackgroundStyle(.alternatingRows(.clear, .clear, header: Color.black.opacity(0.1)))
            .markdownTableBorderStyle(.init(.allBorders, color: .clear, strokeStyle: .init(lineWidth: 0)))
            .tableStyle(.inset)
            .markdownBlockStyle(\.paragraph, body: { configuration in
                VStack {
                    configuration
                        .label
                        .relativeLineSpacing(.em( Application.isPad ? 0.25 : 0.08))
                }
            })
            .markdownTextStyle(\.code) {
                FontFamilyVariant(.monospaced)
                FontWeight(.bold)
            }
    }
    
    var body: some View {
        ChatExampleView(documents: [
            .init(name: "Lease Agreement.pdf", imageName: "Lease")
        ], userMessage: "Who pays what?") {
            messageView
        }
    }
}

struct OrderExampleView: View {
    let text = """
    Here are some suggestions:
    
    ### Appetizers
    1. **Vegetable Spring Rolls** - $6.00: Crispy rolls filled with vegetables like cabbage, carrots, and mushrooms.
    2. **Steamed Vegetable Dumplings** - $7.00: Dumplings filled with a mix of vegetables and sometimes tofu, served with soy or ginger sauce.
    """
    
    var messageView: some View {
        Markdown(text)
            .padding(.horizontal)
            .multilineTextAlignment(.leading)
            .markdownBlockStyle(\.table, body: { configuration in
                configuration.label
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )
            })
            .markdownTableBackgroundStyle(.alternatingRows(.clear, .clear, header: Color.black.opacity(0.1)))
            .markdownTableBorderStyle(.init(.allBorders, color: .clear, strokeStyle: .init(lineWidth: 0)))
            .tableStyle(.inset)
            .markdownBlockStyle(\.paragraph, body: { configuration in
                VStack {
                    configuration
                        .label
                        .relativeLineSpacing(.em( Application.isPad ? 0.25 : 0.08))
                }
            })
            .markdownTextStyle(\.code) {
                FontFamilyVariant(.monospaced)
                FontWeight(.bold)
            }
    }
    
    var body: some View {
        ChatExampleView(documents: [.init(name: "Menu.jpg", imageName: "Menu")], userMessage: "What should I order? I'm vegan.") {
            messageView
        }
    }
}


struct SubscriptionView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SubscriptionView(chat: ChatViewModel())
        }
    }
}
