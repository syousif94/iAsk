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

class Events {
    static let shared = Events()
    
    private let eventStore = EKEventStore()
    
    func requestAccess(for entity: EKEntityType) async throws -> Bool {
        
        let status = EKEventStore.authorizationStatus(for: entity)
        
        switch status {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            if entity == .event {
                return try await eventStore.requestFullAccessToEvents()
            }
            if entity == .reminder {
                return try await eventStore.requestFullAccessToReminders()
            }
            
            return false
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
        guard let access = try? await requestAccess(for: .event), access else {
            return
        }
        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            print("saved event", event.eventIdentifier)
        } catch {
            print("Failed to save event with error: \(error)")
        }
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
}


class AddEventController: UIViewController, EKEventEditViewDelegate {
    let eventStore = EKEventStore()
    
    func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        controller.dismiss(animated: true, completion: nil)
        parent?.dismiss(animated: true, completion: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        eventStore.requestAccess( to: EKEntityType.event, completion: { (granted, error) in
            DispatchQueue.main.async {
                if (granted) && (error == nil) {
                    let eventController = EKEventEditViewController()
                    
                    eventController.eventStore = self.eventStore
                    eventController.editViewDelegate = self
                    eventController.modalPresentationStyle = .overCurrentContext
                    eventController.modalTransitionStyle = .crossDissolve
                    
                    self.present(eventController, animated: true, completion: nil)
                }
            }
        }
        )
    }
}

struct AddEvent: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> AddEventController {
        return AddEventController()
    }
    
    func updateUIViewController(_ uiViewController: AddEventController, context: Context) {
        // We need this to follow the protocol, but don't have to implement it
        // Edit here to update the state of the view controller with information from SwiftUI
    }
}
