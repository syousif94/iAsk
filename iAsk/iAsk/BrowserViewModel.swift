//
//  BrowserViewModel.swift
//  iAsk
//
//  Created by Sammy Yousif on 10/13/23.
//

import Foundation

import Combine

class BrowserViewModel: ObservableObject {
    
    @Published var browserUrl: URL? {
        didSet {
            if let url = browserUrl {
                inputText = url.absoluteString
            }
        }
    }
    
    @Published var isFocused = false
    
    @Published var history: [BrowserHistory] = []
    
    @Published var inputText: String? = ""
    
    @Published var inputSuggestion: String = ""
    
    var onURLLoad: ( (_ url: URL) -> Void )?
    
    var cancelables = Set<AnyCancellable>()
    
    init(browserUrl: URL? = nil, isFocused: Bool = false, history: [BrowserHistory] = [], inputText: String = "", inputSuggestion: String = "", onURLLoad: ( (_: URL) -> Void)? = nil) {
        
        self.browserUrl = browserUrl
        self.isFocused = isFocused
        self.history = history
        self.inputText = inputText
        self.inputSuggestion = inputSuggestion
        self.onURLLoad = onURLLoad
        
        
        setupURLListener()
        setupInputListener()
    }

    func setupURLListener() {
        $browserUrl.sink { [weak self] url in
            if let url = url {
                self?.onURLLoad?(url)
            }
            
        }.store(in: &cancelables)
    }
    
    func setupInputListener() {
        $inputText
            .debounce(for: .seconds(0.15), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [self] searchText in
                Task {
                    if let searchText = searchText,
                       let results = await BrowserHistory.search(input: searchText),
                       !results.isEmpty {
                        DispatchQueue.main.async {
                            self.inputSuggestion = results.first!.record.url
                        }
                        DispatchQueue.main.async {
                            self.history = results
                        }
                    }
                }
                
            }
            .store(in: &cancelables)
    }
    
    class BrowserHistory: ObservableObject {
        let record: BrowserHistoryRecord
        
        init(record: BrowserHistoryRecord) {
            self.record = record
        }
        
        static func search(input: String) async -> [BrowserHistory]? {
            if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return nil
            }
            
            let terms = input.split(separator: " ")
            
            let searchArgs = terms.compactMap { "%\($0.lowercased())%" }
            
            var sqlWheres = searchArgs.map { _ in "lower(url) LIKE ?" }.joined(separator: " AND ")
            
            sqlWheres += " ORDER BY lastVisited DESC"
            
            let records = try? await BrowserHistoryRecord.read(from: Database.shared.db, sqlWhere: sqlWheres, searchArgs)
            
            return records? .map(BrowserHistory.init)
        }
    }
}
