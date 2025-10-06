//
//  DynamicIslandCalendar.swift
//  DynamicIsland
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import SwiftUI
import Defaults
import EventKit

struct Config: Equatable {
//    var count: Int = 10  // 3 days past + today + 7 days future
    var past: Int = 3
    var future: Int = 7
    var steps: Int = 1  // Each step is one day
    var spacing: CGFloat = 1
    var showsText: Bool = true
    var offset: Int = 2 // Number of dates to the left of the selected date
}

struct WheelPicker: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Binding var selectedDate: Date
    @State private var scrollPosition: Int?
    @State private var haptics: Bool = false
    @State private var byClick: Bool = false
    let config: Config
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: config.spacing) {
                let totalSteps = config.steps * (config.past + config.future)
                let spacerNum = config.offset
                ForEach(0..<totalSteps + 2 * spacerNum + 1, id: \.self) { index in
                    if(index < spacerNum || index > totalSteps + spacerNum - 1){
                        Spacer().frame(width: 24, height: 24).id(index)
                    } else {
                        let offset = -config.offset - config.past
                        let date = dateForIndex(index, offset: offset)
                        let isSelected = isDateSelected(index, offset: offset)
                        dateButton(date: date, isSelected: isSelected, offset: offset){
                            selectedDate = date
                            byClick = true
                            withAnimation{
                                scrollPosition = indexForDate(date, offset: offset) - config.offset
                            }
                            if (Defaults[.enableHaptics]) {
                                haptics.toggle()
                            }
                        }
                    }
                }
            }
            .frame(height: 50)
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollPosition(id: $scrollPosition, anchor: .leading)
        .scrollTargetBehavior(.viewAligned)   // Ensures scroll view snaps to button center
        .safeAreaPadding(.horizontal)
        .sensoryFeedback(.alignment, trigger: haptics)
        .onChange(of: scrollPosition) { oldValue, newValue in
            if(!byClick){
                handleScrollChange(newValue: newValue, config: config)
            }else{
                byClick = false
            }
        }
        .onAppear {
            scrollToToday(config: config)
        }
    }
    
    private func dateButton(date: Date, isSelected: Bool, offset: Int, onClick:@escaping()->Void) -> some View {
        Button(action: onClick) {
            VStack(spacing: 2) {
                dayText(date: dateToString(for: date), isSelected: isSelected)
                dateCircle(date: date, isSelected: isSelected)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .id(indexForDate(date, offset: offset))
    }
    
    private func dayText(date: String, isSelected: Bool) -> some View {
        Text(date)
            .font(.caption2)
            .foregroundStyle(isSelected ? Color.accentColor : .gray)
    }

    private func dateCircle(date: Date, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : .clear)
                .frame(width: 24, height: 24)
            Text("\(date.date)")
                .font(.title3)
                .foregroundStyle(isSelected ? .white : .gray)
        }
    }
    
    func handleScrollChange(newValue: Int?, config: Config) {
        let offset = -config.offset - config.past
        let todayIndex = indexForDate(Date(), offset: offset)
        guard let newIndex = newValue else { return }
        let targetDateIndex = newIndex + config.offset
        switch targetDateIndex {
        case todayIndex - config.past ..< todayIndex + config.future:
            selectedDate = dateForIndex(targetDateIndex, offset: offset)
            if (Defaults[.enableHaptics]) {
                haptics.toggle()
            }
        default:
            return
        }
    }

    private func scrollToToday(config: Config) {
        let today = Date()
        let todayIndex = indexForDate(today, offset: -config.offset - config.past)
        byClick = true
        scrollPosition = todayIndex - config.offset
        selectedDate = today
    }

    private func indexForDate(_ date: Date, offset: Int) -> Int {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date())
        let targetDate = calendar.startOfDay(for: date)
        let daysDifference = calendar.dateComponents([.day], from: startDate, to: targetDate).day ?? 0
        return daysDifference
    }

    private func dateForIndex(_ index: Int, offset: Int) -> Date {
        let startDate = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return Calendar.current.date(byAdding: .day, value: index, to: startDate) ?? Date()
    }

    private func dateToString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private func isDateSelected(_ index: Int, offset: Int) -> Bool {
        Calendar.current.isDate(dateForIndex(index, offset: offset), inSameDayAs: selectedDate)
    }
}

struct CalendarView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Date()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading) {
                    Text(selectedDate.formatted(.dateTime.month(.abbreviated)))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text(selectedDate.formatted(.dateTime.year()))
                        .font(.title3)
                        .fontWeight(.light)
                        .foregroundColor(Color(white: 0.65))
                }

                ZStack(alignment: .top) {
                    WheelPicker(selectedDate: $selectedDate, config: Config())
                    HStack(alignment: .top) {
                        LinearGradient(
                            colors: [Color.black, .clear], startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 20)
                        Spacer()
                        LinearGradient(
                            colors: [.clear, Color.black], startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 20)
                    }
                }
            }

            let filteredEvents = EventListView.filteredEvents(
                events: calendarManager.events
            )
            if filteredEvents.isEmpty {
                EmptyEventsView()
                Spacer(minLength: 0)
            } else {
                EventListView(events: calendarManager.events)
            }
        }
        .listRowBackground(Color.clear)
        .frame(height: 120)
        .onChange(of: selectedDate) {
            Task {
                await calendarManager.updateCurrentDate(selectedDate)
            }
        }
        .onChange(of: vm.notchState) { _, _ in
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
        .onAppear {
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
    }
}

struct EmptyEventsView: View {
    var body: some View {
        VStack {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title)
                .foregroundColor(Color(white: 0.65))
            Text("No events today")
                .font(.subheadline)
                .foregroundColor(.white)
            Text("Enjoy your free time!")
                .font(.caption)
                .foregroundColor(Color(white: 0.65))
        }
    }
}

struct EventListView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var calendarManager = CalendarManager.shared
    let events: [EventModel]


    static func filteredEvents(events: [EventModel]) -> [EventModel] {
        events.filter { event in
            // Filter out all-day events if setting is enabled
            if event.isAllDay && Defaults[.hideAllDayEvents] {
                return false
            }
            return true
        }
    }

    private var filteredEvents: [EventModel] {
        Self.filteredEvents(events: events)
    }

    var body: some View {
        List {
            ForEach(filteredEvents) { event in
                Button(action: {
                    if let url = event.calendarAppURL() {
                        openURL(url)
                    }
                }) {
                    eventRow(event)
                }
                .padding(.leading, -5)
                .buttonStyle(PlainButtonStyle())
                .listRowSeparator(.automatic)
                .listRowSeparatorTint(.gray.opacity(0.2))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollIndicators(.never)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        Spacer(minLength: 0)
    }

    private func eventRow(_ event: EventModel) -> some View {
        // Regular event row
        return AnyView(
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(event.calendar.color))
                    .frame(width: 8, height: 8)
                HStack {
                    Text(event.title)
                        .font(.callout)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        if event.isAllDay {
                            Text("All-day")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .lineLimit(1)
                        } else {
                            Text("\(event.start, style: .time)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text("\(event.end, style: .time)")
                                .font(.caption2)
                                .foregroundColor(Color(white: 0.65))
                                .lineLimit(1)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
        )
    }
}

#Preview {
    CalendarView()
        .frame(width: 250)
        .padding(.horizontal)
        .background(.black)
        .environmentObject(DynamicIslandViewModel.init())
}
