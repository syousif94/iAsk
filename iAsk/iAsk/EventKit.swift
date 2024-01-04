//
//  Calendar.swift
//  iAsk
//
//  Created by Sammy Yousif on 10/9/23.
//

import Foundation
import EventKit
import SwiftDate
import UIKit
import EventKitUI
import SwiftUI

@MainActor
class Events {
    static let shared = Events()
    
    private let eventStore = EKEventStore()
    
    func requestAccess(for entity: EKEntityType) async throws -> Bool {
        
        let status = EKEventStore.authorizationStatus(for: entity)
        
        
        
        switch status {
        case .authorized:
            print("event kit authorized")
            return true
        case .denied:
            print("event kit denied")
            return false
        case .notDetermined:
            print("event kit not determined")
            if entity == .event {
                return try await eventStore.requestFullAccessToEvents()
            }
            if entity == .reminder {
                return try await eventStore.requestFullAccessToReminders()
            }
            
            return false
        default:
            print("event kit default")
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
    
    func insertEvent(event: EKEvent) async -> String? {
        guard let access = try? await requestAccess(for: .event), access else {
            print("no access to events")
            return nil
        }
        
        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        } catch {
            print("Failed to save event with error: \(error)")
        }
        
        return nil
    }
    
    func insertReminder(reminder: EKReminder) async {
        
        guard let access = try? await requestAccess(for: .reminder), access else {
            return
        }
        
        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            print("Failed to save event with error: \(error)")
        }
        
        
    }
    
    func createReminder(title: String, notes: String, date: Date) -> EKReminder {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        let alarm = EKAlarm(absoluteDate: date)
        reminder.addAlarm(alarm)
        
        return reminder
    }
    
    func getEvent(withIdentifier identifier: String) async -> EKEvent? {
        guard let access = try? await requestAccess(for: .event), access else {
            return nil
        }
        let event = eventStore.event(withIdentifier: identifier)
        return event
    }
    
    func getReminder(withIdentifier identifier: String) async -> EKReminder? {
        guard let access = try? await requestAccess(for: .reminder), access else {
            return nil
        }
        let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder
        return reminder
    }
    
    func getUpcomingEvents() async -> [EKEvent] {
        guard let access = try? await requestAccess(for: .event), access else {
            return []
        }
        
        let startDate = Date().dateAtStartOf(.hour)
        let endDate = Calendar.current.date(byAdding: .year, value: 1, to: startDate)

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate!, calendars: nil)

        let events = eventStore.events(matching: predicate)
        
        return []
    }
}


struct EventEditView: UIViewControllerRepresentable {
    @Binding var eventId: String?
    @Environment(\.presentationMode) var presentationMode
    var onEventDeleted: (() -> Void)?

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let editViewController = EKEventEditViewController()
        editViewController.editViewDelegate = context.coordinator
        return editViewController
    }
    
    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {
        let eventStore = EKEventStore()
        eventStore.requestFullAccessToEvents { granted, error in
            if granted && error == nil, let eventId = eventId, let event = eventStore.event(withIdentifier: eventId) {
                uiViewController.eventStore = eventStore
                uiViewController.event = event
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, EKEventEditViewDelegate {
        var parent: EventEditView
        
        init(_ parent: EventEditView) {
            self.parent = parent
        }
        
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            parent.presentationMode.wrappedValue.dismiss()
            
            if action == .deleted {
                // Notify SwiftUI that the event was deleted
                parent.onEventDeleted?()
            }
        }
    }
}
