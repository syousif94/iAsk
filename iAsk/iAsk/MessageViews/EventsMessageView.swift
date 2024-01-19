//
//  EventsMessageView.swift
//  iAsk
//
//  Created by Sammy Yousif on 1/10/24.
//

import SwiftUI
import EventKit
import SwiftDate

struct EventsMessageView: View {
    var message: Message
    
    @State var events: SortedEvents = SortedEvents(remindersWithoutDueDates: [], groupedByYearMonth: [])
    
    func getEvents() async {
        
        let decoder = JSONDecoder()
        
        let json = try? decoder.decode(GetCalendarArgs.self, from: message.content.data(using: .utf8)!)
        
        async let events = Events.shared.getEvents(startDate: json?.startDate, endDate: json?.endDate)
        async let reminders = Events.shared.getReminders()
        
        let grouped = groupAndSortEventsAndReminders(events: await events, reminders: await reminders)
        
        DispatchQueue.main.async {
            self.events = grouped
        }
    }
    
    func getInterval(start: Date, end: Date) -> String {
        return start.timeIntervalSince(end).toString {
            $0.maximumUnitCount = 4
            $0.allowedUnits = [.hour, .minute]
            $0.collapsesLargestUnit = true
            $0.unitsStyle = .short
        }
    }
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(events.remindersWithoutDueDates, id: \.self) { reminder in
                ReminderView(reminder: reminder)
            }
            ForEach(events.groupedByYearMonth, id: \.self) { monthEvents in
                HStack {
                    Rectangle().fill(.gray).frame(height: 1)
                    Text("\(monthEvents.month) \(monthEvents.year)".toDate("M yyyy")?.toFormat("MMM yyyy") ?? "")
                        .font(.caption)
                    Rectangle().fill(.gray).frame(height: 1)
                }
                .frame(maxWidth: .infinity)
                
                ForEach(monthEvents.dailyEvents, id: \.self) { events in
                    LazyVStack(alignment: .leading) {
                        if events.date.isToday || events.date.isTomorrow {
                            Text(events.date.isToday ? "TODAY" : "TOMORROW")
                                .font(.caption)
                                .padding(.leading, 60)
                                .padding(.leading)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                        }
                        HStack(alignment: .top) {
                            VStack {
                                Text(events.date.toFormat("EEE"))
                                Text(events.date.toFormat("d"))
                            }
                            .padding(.top, 4)
                            .frame(width: 60)
                            VStack(alignment: .leading) {
                                ForEach(events.reminders, id: \.self) { reminder in
                                    ReminderView(reminder: reminder)
                                }
                                ForEach(Array(events.events.enumerated()), id: \.1) { (index, event) in
                                    VStack(alignment: .leading) {
                                        if !event.isAllDay, index > 0 {
                                            HStack {
                                                Rectangle().fill(.gray).frame(height: 1)
                                                Text(getInterval(start: event.startDate, end: events.events[index - 1].endDate))
                                                    .font(.caption)
                                                Rectangle().fill(.gray).frame(height: 1)
                                            }
                                            .padding(.horizontal)
                                            .frame(maxWidth: .infinity)
                                        }
                                        EventView(event: event)
                                    }
                                }
                            }
                        }
                        
                        
                    }
                    
                }
            }
            
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
        
        .onReceive(message.$answering) { answering in
            
            
            if !answering {
                print("loading events")
                Task {
                    await self.getEvents()
                }
            }
        }
    }
}

struct ReminderView: View {
    
    var reminder: EKReminder
    
    @State var isCompleted: Bool
    
    init(reminder: EKReminder) {
        self.reminder = reminder
        self.isCompleted = reminder.isCompleted
    }
    
    var alarmDate: DateInRegion? {
        if let alarm = reminder.alarms?.first {
            return alarm.absoluteDate?.in(region: .current)
        }
        return nil
    }
    
    var alarmString: String? {
        alarmDate?.toFormat("h:mma")
    }
    
    var isPastDue: Bool {
        alarmDate?.isInPast ?? false
    }
    
    var body: some View {
        HStack {
            Text(reminder.title)
                .foregroundColor(Color.black.opacity(0.7))
                .font(.headline)
                .fontWeight(.bold)
            if let time = alarmString {
                Text(time)
                    .foregroundColor(Color.black.opacity(0.7))
            }
            
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
        .padding()
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: isPastDue ? "fcd7d9" : "#d7eafc", alpha: 1)))
        .onTapGesture {
            reminder.isCompleted = !reminder.isCompleted
            isCompleted = reminder.isCompleted
            Task {
                await Events.shared.updateReminder(reminder: reminder)
            }
        }
    }
}

struct EventView: View {
    var event: EKEvent
    
    @State private var eventId: String?
    @State private var showingEventEditView = false
    @State var showMissingEventAlert = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(event.title)
                    .foregroundColor(Color.black.opacity(0.7))
                    .font(.headline)
                    .fontWeight(.bold)
                if let location = event.location {
                    Text(location)
                        .foregroundColor(Color.black.opacity(0.7))
                }
                if !event.isAllDay {
                    Text("\(event.startDate.in(region: .current).toFormat("h:mma")) - \(event.endDate.in(region: .current).toFormat("h:mma"))")
                        .foregroundColor(Color.black.opacity(0.7))
                }
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: event.isAllDay ? "#fbe6d1" : "#e0f5d6", alpha: 1)))
        .onTapGesture {
            if let identifier = event.eventIdentifier {
                eventId = identifier
                showingEventEditView = true
                
            }
        }
        .sheet(isPresented: $showingEventEditView) {
            EventEditView(eventId: $eventId) {

            }
        }
    }
}
