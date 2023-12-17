//
//  SubscriptionView.swift
//  iAsk
//
//  Created by Sammy Yousif on 12/10/23.
//

import SwiftUI
import PagerTabStripView
import OpenAI
import MarkdownUI

struct SubscriptionView: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    var imageName: String {
        colorScheme == .light ? "Intro" : "IntroDark"
    }
    
    var backgroundColor: Color {
        colorScheme == .light ? .white : Color(hex: "#333333")
    }
    
    var blurStyle: UIBlurEffect.Style {
        colorScheme == .light ? .extraLight : .dark
    }
    
    var body: some View {
        GeometryReader { geometry in
            List {
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
                    Text("The smarter assistant")
                        .foregroundStyle(.secondary)
                        .padding(.top)
                    PagerView()
                        .padding(.top, 24)
                        
                    Button(action: {}, label: {
                        Text("Start 7 Day Free Trial")
                            .fontWeight(.bold)
                    })
                    .buttonStyle(.borderedProminent)
                    Text("Then just $2.99 per month")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top)
                    Button(action: {}, label: {
                        Text("Restore Purchase")
                    })
                    .buttonStyle(.borderless)
                    .padding(.top, 36)
                }
                .frame(width: geometry.size.width)
                .offset(y: -40)
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .background(backgroundColor)
                .listRowInsets(EdgeInsets())
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
            .background(backgroundColor)
        }
        .ignoresSafeArea()
    }
}

struct PagerView: View {
    enum Page: String {
        case vision
        case analysis
        case research
        case code
        case media
    }
    
    @State var selection = Page.vision
    
    var height: CGFloat = 450
    
    @Environment(\.colorScheme) var colorScheme
    
    var gradient: LinearGradient = LinearGradient(colors: [.blue, Color(hex: "#3ca1ff")], startPoint: .top, endPoint: .bottom)
    
    func getTabStyle(width: CGFloat) -> PagerStyle {
        if width > 550 {
            return .barButton(
                placedInToolbar: false,
                tabItemSpacing: 0,
                tabItemHeight: 44,
                padding: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
                indicatorViewHeight: 32,
                indicatorView: {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(gradient)
                        .offset(y: -16 - 6)
                        .padding(.horizontal, 12)
                        .zIndex(0.1)
                }
            )
        }
        
        return .scrollableBarButton(
            placedInToolbar: false,
            tabItemSpacing: 0,
            tabItemHeight: 44,
            padding: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
            indicatorViewHeight: 32,
            indicatorView: {
                RoundedRectangle(cornerRadius: 16)
                    .fill(gradient)
                    .offset(y: -16 - 6)
                    .padding(.horizontal, 12)
                    .zIndex(0.1)
            }
        )
    }
    
    @MainActor var body: some View {
        GeometryReader { g in
            PagerTabStripView(selection: $selection) {
                VisionExampleView()
                    .pagerTabItem(tag: Page.vision) {
                        SubscriptionNavBarItem(selection: $selection, tag: Page.vision, title: "Read")
                    }
                AnalyzeExampleView()
                    .pagerTabItem(tag: Page.analysis) {
                        SubscriptionNavBarItem(selection: $selection, tag: Page.analysis, title: "Analyze")
                    }
                ResearchExampleView()
                    .pagerTabItem(tag: Page.research) {
                        SubscriptionNavBarItem(selection: $selection, tag: Page.research, title: "Search")
                    }
                CodeExampleView()
                    .pagerTabItem(tag: Page.code) {
                        SubscriptionNavBarItem(selection: $selection, tag: Page.code, title: "Code")
                    }
                ConvertExampleView()
                    .pagerTabItem(tag: Page.media) {
                        SubscriptionNavBarItem(selection: $selection, tag: Page.media, title: "Edit")
                    }
            }
            .frame(height: height)
            .pagerTabStripViewStyle(getTabStyle(width: g.size.width))
        }
        .frame(height: height)
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
    
    let userMessage: String
    
    let outputMessage: Content
    
    @Environment(\.colorScheme) var colorScheme
    
    var backgroundColor: Color {
        colorScheme == .light ? .white : Color(hex: "#333333")
    }

    init(documents: [Document] = [], userMessage: String, @ViewBuilder outputMessage: () -> Content) {
        self.documents = documents
        self.outputMessage = outputMessage()
        self.userMessage = userMessage
    }
    
    var sideLength: CGFloat = 140
    
    func getHorizontalPadding(width: CGFloat) -> CGFloat {
        if width > 550 {
            return (width - 550) / 2
        }
        return 0
    }

    var body: some View {
        GeometryReader { g in
            VStack(alignment: .leading) {
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
                
                
                Text(userMessage)
                    .padding(.trailing, 40)
                    .font(.system(size: 20, weight: .bold))
                    .padding(.horizontal)
                    .padding(.bottom)
                
                outputMessage
            }
            .padding(.horizontal, getHorizontalPadding(width: g.size.width))
            .padding(.top, 32)
            .background(backgroundColor)
        }
    }
}

struct VisionExampleView: View {
    var body: some View {
        ChatExampleView(documents: [
            .init(name: "Invite.jpg", imageName: "Invite")
        ], userMessage: "Add this to my calendar") {
            EventsMessageView(message:
                Message(record: .init(
                    chatId: "",
                    createdAt: .now,
                    content: """
                    {
                        "title": "Christmas Party",
                        "location": "421 Milford St, Glendale, CA",
                        "startDate": "2023-12-16 21:00",
                        "endDate": "2023-12-17 2:00"
                    }
                    """,
                    role: .function,
                    messageType: .events)
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
        ChatExampleView(documents: [
            .init(name: "Bank Statement.pdf", imageName: "Analysis")
        ], userMessage: "What are my business expenses") {
            messageView
        }
    }
}

struct ResearchExampleView: View {
    var body: some View {
        ChatExampleView(userMessage: "What home lakers games are this month?") {
            VStack {
                SearchingMessageView(message: Message(record: .init(
                    chatId: "",
                    createdAt: .now,
                    content: "",
                    role: .assistant,
                    messageType: .text)
                ))
                
            }
        }
    }
}

struct CodeExampleView: View {
    var body: some View {
        ChatExampleView(userMessage: "How do i integrate the character control code with my code?") {
            
        }
    }
}

struct ConvertExampleView: View {
    var body: some View {
        ChatExampleView(userMessage: "Extract the audio") {
            
        }
    }
}

struct SubscriptionNavBarItem<SelectionType>: View where SelectionType: Hashable {
    @EnvironmentObject private var pagerSettings: PagerSettings<SelectionType>
    
    @Binding var selection: SelectionType
    let tag: SelectionType
    let title: String
    
    @Environment(\.colorScheme) var colorScheme
    
    var unselectedColor: Color {
        colorScheme == .light ? .blue : .blue
    }

    init(selection: Binding<SelectionType>, tag: SelectionType, title: String) {
        self.tag = tag
        _selection = selection
        self.title = title
    }

    @MainActor var body: some View {
        HStack(alignment: .center) {
            Text(self.title)
                .fontWeight(.medium)
                .padding(.horizontal, 28)
                .foregroundColor(unselectedColor.interpolateTo(color: Color(.white), fraction: pagerSettings.transition.progress(for: tag)))
                .animation(.easeInOut, value: selection)
        }
        
        .frame(height: 44)
        .offset(y: 16)
        .zIndex(1)
    }
}


struct SubscriptionView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SubscriptionView()
        }
    }
}
