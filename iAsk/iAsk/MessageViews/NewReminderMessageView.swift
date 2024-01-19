//
//  NewReminderMessageView.swift
//  iAsk
//
//  Created by Sammy Yousif on 1/10/24.
//

import SwiftUI

struct NewReminderMessageView: View {
    
    var message: Message
    
    @State var isCompleted: Bool = false
    
    @Environment(\.colorScheme) var colorScheme
    
    @State var answering: Bool = true
    
    @State var title: String = ""
    @State var dueDate: String = ""
    @State var notes: String = ""
    
    enum JsonKeys: String, CaseIterable {
        case title
        case dueDate
        case notes
    }
    
    var body: some View {
        VStack {
            HStack {
                Text(title)
                    .foregroundColor(Color.black.opacity(0.7))
                    .font(.headline)
                    .fontWeight(.bold)
                Text(dueDate)
                    .foregroundColor(Color.black.opacity(0.7))
                
                Spacer()
                
                ZStack {
                    if isCompleted {
                        Image(systemName: "checkmark")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .symbolRenderingMode(.monochrome)
                            .frame(width: 12, height: 12)
                            .fontWeight(.black)
                            .foregroundStyle(Color.black.opacity(0.3))
                    }
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round) )
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 20, height: 20)
                        
                }
            }
            .frame(maxWidth: .infinity)
            if !notes.isEmpty {
                Text(notes).font(.caption)
                    .foregroundStyle(Color.black.opacity(0.3))
            }
            
        }
        .padding()
        .frame(maxWidth: .infinity)
        
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#d7eafc", alpha: 1)))
        .padding(.horizontal)
        .padding(.bottom)
        .onReceive(message.$content.debounce(for: 0.016, scheduler: DispatchQueue.main)) { text in
            for key in JsonKeys.allCases {
                if let extracted = extractJSONValue(from: String(text), forKey: key.rawValue) {
                    switch key {
                    case .title:
                        self.title = extracted
                    case .dueDate:
                        if let date = extracted.toDate() {
                            if date.isToday || date.isTomorrow {
                                dueDate = date.toFormat("h:mma ") + (date.isToday ? "Today" : "Tomorrow")
                            }
                            else {
                                dueDate = date.toFormat("h:mma EEE MMM d, yyyy")
                            }
                        }
                    case .notes:
                        self.notes = extracted
                    }
                }
            }
        }
    }
}
