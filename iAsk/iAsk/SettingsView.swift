//
//  SettingsView.swift
//  iAsk
//
//  Created by Sammy Yousif on 10/26/23.
//

import SwiftUI
import Charts
import SwiftDate
import Combine
import OpenAI

class SettingsViewModel: ObservableObject {
    
    @Published var stats: [Stats] = []
    
    @Published var gpt4Questions: Int = 0
    
    @Published var gpt35Questions: Int = 0
    
    var cancelables = Set<AnyCancellable>()
    
    init() {
        Task {
            await updateCountIndex()
            
            setupMessageListener()
        }
        
    }
    
    func setupMessageListener() {
        let messageRecordSubscription = MessageRecord.changePublisher(in: Database.shared.db).debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [self] changes in
            Task {
                await self.updateCountIndex()
            }
        }
        
        messageRecordSubscription.store(in: &cancelables)
    }
    
    func updateCountIndex() async {
        
        let now = Date()
        
        async let gpt35query = try? MessageRecord.read(from: Database.shared.db, sqlWhere: "model = ? AND role = ? AND updatedAt > ? ORDER BY updatedAt ASC", arguments: [Model.gpt3_5Turbo, Chat.Role.user.rawValue, now - 30.days])
        async let gpt4query = try? MessageRecord.read(from: Database.shared.db, sqlWhere: "model = ? AND role = ? AND updatedAt > ? ORDER BY updatedAt ASC", arguments: [Model.gpt4, Chat.Role.user.rawValue, now - 30.days])
        
        let gpt35questions = await gpt35query
        let gpt4questions = await gpt4query
        
        let gpt35count = gpt35questions?.count ?? 0
        let gpt4count = gpt4questions?.count ?? 0
        
        var stats: [Stats] = []
        
        for (index, questions) in [gpt4questions, gpt35questions].enumerated() {
            let groups = questions?.group(by: { record in
                return record.createdAt.in(region: .current).toFormat("M/d")
            })
            
            for i in 0...7 {
                let date = (now.in(region: .current) - i.days).toFormat("M/d")
                stats.append(Stats(date: date, questions: groups?[date]?.count ?? 0, model: index == 1 ? .gpt3 : .gpt4))
            }
        }
        
        stats.reverse()
        
        DispatchQueue.main.async { [stats] in
            self.gpt4Questions = gpt4count
            self.gpt35Questions = gpt35count
            self.stats = stats
        }
    }
    
    struct Stats {
        let date: String
        let questions: Int
        let model: Model
        
        enum Model: String, Plottable {
            case gpt3 = "GPT-3.5"
            case gpt4 = "GPT-4"
        }
    }
    
}

struct SettingsView: View {
    
    @EnvironmentObject var chat: ChatViewModel
    
    @StateObject var model = SettingsViewModel()
    
    var formView: some View {
        Form {
            Section(header: Text("Usage")) {
                VStack(alignment: .leading) {
                    Text("Questions Asked")
                        .font(.headline)
                    Chart {
                        ForEach(model.stats, id: \.date) { stat in
                            BarMark(
                                x: .value("Date", stat.date),
                                y: .value("Questions", stat.questions)
                            )
                            .foregroundStyle(by: .value("Model", stat.model))
                        }
                    }
                    .chartForegroundStyleScale([
                        SettingsViewModel.Stats.Model.gpt3.rawValue: .green,
                        SettingsViewModel.Stats.Model.gpt4.rawValue: .orange
                    ])
                    .padding(.vertical, 8)
                    HStack {
                        Text("GPT-3.5")
                        Spacer()
                        Text("\(model.gpt35Questions)")
                            .foregroundStyle(.secondary)
                        
                    }
                    .padding(.top, 8)
                    HStack {
                        Text("GPT-4")
                        Spacer()
                        Text("\(model.gpt4Questions)")
                            .foregroundStyle(.secondary)
                        
                    }
                    .padding(.top, 4)
                    
                }
                .padding(.vertical)
            }
            Section(header: Text("Subscription Settings")) {
                HStack {
                    Text("Current Subscription")
                    Spacer()
                    Text("None")
                        .foregroundStyle(.secondary)
                    
                }
                Button("Subscribe") {}
                
                Button("Restore purchase") {}
            }
            
            Section(header: Text("Chat Settings")) {
                Toggle(isOn: $chat.listenOnLaunch) {
                    Text("Listen on Launch")
                        .font(.headline)
                        .padding(.top, 2)
                    Text("Enable this to start listening for commands when the app is opened.")
                        .font(.caption)
                        .padding(.top, 1)
                }
                
                Toggle(isOn: $chat.proMode) {
                    Text("Use GPT-4")
                        .font(.headline)
                        .padding(.top, 2)
                    Text("GPT-4 is much better at making decisions than the default model. A pro subscription is required for unlimited usage.")
                        .font(.caption)
                        .padding(.top, 1)
                }
                .tint(.orange)
                
                Toggle(isOn: $chat.speakAnswer) {
                    Text("Speak Answers")
                        .font(.headline)
                        .padding(.top, 2)
                    Text("Use Apple's built in text to speech to read answers aloud.")
                        .font(.caption)
                        .padding(.top, 1)
                }
                
            }
        }
        
    }
    
    var body: some View {
        NavigationStack {
            if Application.isPad {
                formView.toolbar {
                    Button {
                        chat.showSettings = false
                    } label: {
                        Text("Done")
                    }

                }
            }
            else {
                formView
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    
    static var previews: some View {
        SettingsView()
            .environmentObject(ChatViewModel())
    }
}