//
//  Calendar.swift
//  iAsk
//
//  Created by Sammy Yousif on 10/9/23.
//

import Foundation
import EventKit
import SwiftDate

class Events {
    static let shared = Events()
    
    private let eventStore = EKEventStore()
    
    func requestAccess() async throws -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        
        switch status {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            return try await eventStore.requestFullAccessToEvents()
        default:
            return false
        }
    }

    func createEvent(args: CreateCalendarEventArgs) -> EKEvent? {
        let dateFormat = "yyyy-MM-dd HH:mm"
        guard let startDate = args.startDate.toDate(dateFormat, region: .current)?.date,
              let endDate = args.endDate.toDate(dateFormat, region: .current)?.date else {
            print("Failed to parse date")
            return nil
        }
        
        var url: URL? = nil
        if let urlString = args.url {
            url = URL(string: urlString)
        }
        
        return createEvent(title: args.title, startDate: startDate, endDate: endDate, location: args.location, notes: args.notes, url: url, allDay: args.allDay)
    }
    
    func createEvent(title: String, startDate: Date, endDate: Date, location: String? = nil, notes: String? = nil, url: URL? = nil, allDay: Bool? = nil) -> EKEvent {
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = allDay ?? false
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.location = location
        event.notes = notes
        event.url = url
        
        return event
    }
    
    func insertEvent(event: EKEvent) async {
        guard let access = try? await requestAccess(), access else {
            return
        }
        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            print("Failed to save event with error: \(error)")
        }
    }
}
