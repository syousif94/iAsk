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
    
    static let dateFormat = "yyyy-MM-dd HH:mm"
    
    static func getDate(_ str: String?) -> Date? {
        return str?.toDate(Self.dateFormat, region: .current)?.date
    }

    func createEvent(args: CreateCalendarEventArgs) -> EKEvent? {
        guard let startDate = Self.getDate(args.startDate),
              let endDate = Self.getDate(args.endDate) else {
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
    
    func createReminder(title: String, notes: String?, date: Date) -> EKReminder {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        let alarm = EKAlarm(absoluteDate: date)
        reminder.addAlarm(alarm)
        
        return reminder
    }
    
    func updateReminder(reminder: EKReminder) async {
        do {
            try eventStore.save(reminder, commit: true)
        } catch let error {
            print("Error saving reminder: \(error)")
        }
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
    
    func getEvents(startDate: String? = nil, endDate: String? = nil) async -> [EKEvent] {
        guard let access = try? await requestAccess(for: .event), access else {
            return []
        }
        
        let start = Self.getDate(startDate)?.dateAtStartOf(.hour) ?? Date().dateAtStartOf(.hour)
        let end = Self.getDate(endDate) ?? start.dateAtEndOf(.month)

        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)

        let events = eventStore.events(matching: predicate)
        
        return events
    }
    
    func getReminders() async -> [EKReminder] {
        guard let access = try? await requestAccess(for: .reminder), access else {
            return []
        }
        
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
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

struct SortedEvents {
    let remindersWithoutDueDates: [EKReminder]
    let groupedByYearMonth: [YearMonthEvents]
}

struct YearMonthEvents: Hashable {
    let year: Int
    let month: Int
    let dailyEvents: [DailyEvents]
}

struct DailyEvents: Hashable {
    let date: Date
    let reminders: [EKReminder]
    let events: [EKEvent]
}

func groupAndSortEventsAndReminders(events: [EKEvent], reminders: [EKReminder]) -> SortedEvents {
    // Filter reminders without due dates
    let remindersWithoutDueDates = reminders.filter { $0.alarms?.isEmpty ?? true }
    
    let calendar = Calendar.current
    
    // Group events by year, month, and day
    let groupedEvents = Dictionary(grouping: events) { (event) -> DateComponents in
        return calendar.dateComponents([.year, .month, .day], from: event.startDate)
    }
    
    // Group reminders by year, month, and day
    let groupedRemindersWithDueDates = Dictionary(grouping: reminders.filter { !($0.alarms?.isEmpty ?? true) }) { (reminder) -> DateComponents in
        return calendar.dateComponents([.year, .month, .day], from: reminder.alarms!.first!.absoluteDate!)
    }
    
    // Combine event and reminder groups into DailyEvents, grouped by year and month
    var allDates = Set(groupedEvents.keys).union(groupedRemindersWithDueDates.keys)
    var yearlyMonthlyEvents: [Int: [Int: [DailyEvents]]] = [:]
    
    for dateComponents in allDates {
        guard let date = calendar.date(from: dateComponents) else { continue }
        let eventsForDay = groupedEvents[dateComponents]?.sorted(by: { $0.startDate < $1.startDate }) ?? []
        let remindersForDay = groupedRemindersWithDueDates[dateComponents]?.sorted(by: {
            if let dueDate1 = $0.dueDateComponents, let dueDate2 = $1.dueDateComponents,
               let date1 = calendar.date(from: dueDate1), let date2 = calendar.date(from: dueDate2) {
                return date1 < date2
            }
            return false
        }) ?? []
        let dailyEvent = DailyEvents(date: date, reminders: remindersForDay, events: eventsForDay)
        
        let year = dateComponents.year!
        let month = dateComponents.month!
        yearlyMonthlyEvents[year, default: [:]][month, default: []].append(dailyEvent)
    }
    
    // Sort DailyEvents within each month and year
    for (year, monthlyEvents) in yearlyMonthlyEvents {
        for (month, dailyEvents) in monthlyEvents {
            yearlyMonthlyEvents[year]?[month] = dailyEvents.sorted { $0.date < $1.date }
        }
    }
    
    // Create YearMonthEvents array and sort by year and month
    let sortedYearlyMonthlyEvents = yearlyMonthlyEvents.flatMap { year, months in
        months.sorted { $0.key < $1.key }.map { YearMonthEvents(year: year, month: $0.key, dailyEvents: $0.value) }
    }.sorted { ($0.year, $0.month) < ($1.year, $1.month) }
    
    return SortedEvents(remindersWithoutDueDates: remindersWithoutDueDates, groupedByYearMonth: sortedYearlyMonthlyEvents)
}
