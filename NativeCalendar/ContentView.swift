import SwiftUI
import EventKit

public enum CalendarViewMode: String, CaseIterable, Identifiable {
    case month = "Month"
    case week = "Week"
    case day = "Day"
    case agenda = "Agenda"
    
    public var id: String { self.rawValue }
}

public struct ContentView: View {
    @StateObject private var eventKit = EventKitManager.shared
    @State private var currentDate: Date = Date()
    @State private var selectedDate: Date = Date()
    @State private var activeView: CalendarViewMode = .month
    
    @State private var isShowingAddEventSheet: Bool = false
    @State private var slideDirection: Edge = .trailing
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Ambient Dark Background
            Color(red: 0.04, green: 0.04, blue: 0.06)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Glassmorphic Header Navigation Bar
                headerView
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                
                // Calendar Main Content Viewport with Slow Transitions
                ZStack {
                    switch activeView {
                    case .month:
                        MonthCalendarView(currentDate: $currentDate, selectedDate: $selectedDate, events: eventKit.events)
                            .transition(.asymmetric(
                                insertion: .move(edge: slideDirection).combined(with: .opacity),
                                removal: .opacity
                            ))
                    case .week:
                        WeekCalendarView(currentDate: $currentDate, events: eventKit.events)
                            .transition(.opacity)
                    case .day:
                        DayCalendarView(currentDate: $currentDate, events: eventKit.events)
                            .transition(.opacity)
                    case .agenda:
                        AgendaCalendarView(events: eventKit.events)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.6), value: currentDate)
                .animation(.easeInOut(duration: 0.5), value: activeView)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $isShowingAddEventSheet) {
            AddEventSheet(selectedDate: selectedDate)
        }
        .onAppear {
            eventKit.checkPermission()
        }
    }
    
    // Top Glass Header View
    private var headerView: some View {
        HStack {
            // Logo & Title
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.blue)
                
                Text("Lumina")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Month Navigation
            HStack(spacing: 12) {
                Button(action: {
                    HapticManager.trigger(.light)
                    slideDirection = .leading
                    withAnimation(.easeInOut(duration: 0.6)) {
                        currentDate = Calendar.current.date(byAdding: .month, value: -1, to: currentDate) ?? currentDate
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                Button("Today") {
                    HapticManager.trigger(.medium)
                    withAnimation(.easeInOut(duration: 0.6)) {
                        currentDate = Date()
                        selectedDate = Date()
                    }
                }
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .cornerRadius(16)
                .foregroundColor(.white)
                .buttonStyle(.plain)
                
                Button(action: {
                    HapticManager.trigger(.light)
                    slideDirection = .trailing
                    withAnimation(.easeInOut(duration: 0.6)) {
                        currentDate = Calendar.current.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                Text(monthFormatter.string(from: currentDate))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(minWidth: 160, alignment: .leading)
            }
            
            Spacer()
            
            // View Switcher Segmented Control
            HStack(spacing: 4) {
                ForEach(CalendarViewMode.allCases) { mode in
                    Button(action: {
                        HapticManager.trigger(.medium)
                        withAnimation(.easeInOut(duration: 0.4)) {
                            activeView = mode
                        }
                    }) {
                        Text(mode.rawValue)
                            .font(.caption)
                            .fontWeight(activeView == mode ? .bold : .medium)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(activeView == mode ? Color.blue : Color.clear)
                            .foregroundColor(activeView == mode ? .white : .gray)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.black.opacity(0.3))
            .cornerRadius(12)
            
            // Add Event Button
            Button(action: {
                HapticManager.trigger(.medium)
                isShowingAddEventSheet = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text("New Event")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private var monthFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        return df
    }
}

// Month Grid Component
struct MonthCalendarView: View {
    @Binding var currentDate: Date
    @Binding var selectedDate: Date
    let events: [EKEvent]
    
    private let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    
    var body: some View {
        VStack(spacing: 12) {
            // Weekday Headers
            HStack {
                ForEach(daysOfWeek, id: \.self) { day in
                    Text(day.uppercased())
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
            
            // 6-row Day Grid
            let days = generateDaysInMonth(for: currentDate)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(days, id: \.self) { date in
                    DayCell(date: date, currentDate: currentDate, selectedDate: $selectedDate)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    private func generateDaysInMonth(for date: Date) -> [Date] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }
        
        var dates: [Date] = []
        var current = firstWeek.start
        for _ in 0..<42 {
            dates.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }
        return dates
    }
}

struct DayCell: View {
    let date: Date
    let currentDate: Date
    @Binding var selectedDate: Date
    
    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    var isCurrentMonth: Bool {
        Calendar.current.isDate(date, equalTo: currentDate, toGranularity: .month)
    }
    
    var body: some View {
        VStack {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.caption)
                .fontWeight(isToday ? .bold : .medium)
                .foregroundColor(isToday ? .white : isCurrentMonth ? .primary : .gray.opacity(0.4))
                .frame(width: 24, height: 24)
                .background(isToday ? Color.blue : Color.clear)
                .clipShape(Circle())
            
            Spacer()
        }
        .frame(height: 70)
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(Color.white.opacity(isCurrentMonth ? 0.02 : 0.005))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .onTapGesture {
            HapticManager.trigger(.light)
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedDate = date
            }
        }
    }
}

// Week View
struct WeekCalendarView: View {
    @Binding var currentDate: Date
    let events: [EKEvent]
    
    var body: some View {
        VStack {
            Text("Week Schedule View")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color.white.opacity(0.03))
        .cornerRadius(24)
    }
}

// Day View
struct DayCalendarView: View {
    @Binding var currentDate: Date
    let events: [EKEvent]
    
    var body: some View {
        VStack {
            Text("Day Schedule View")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color.white.opacity(0.03))
        .cornerRadius(24)
    }
}

// Agenda View
struct AgendaCalendarView: View {
    let events: [EKEvent]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Agenda & Timeline")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                if events.isEmpty {
                    Text("No native calendar events found for this range")
                        .foregroundColor(.gray)
                        .padding(.top, 20)
                } else {
                    ForEach(events, id: \.eventIdentifier) { evt in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(evt.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                Text(evt.startDate.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(14)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.03))
        .cornerRadius(24)
    }
}

// Sheet View for Creating Events
struct AddEventSheet: View {
    @Environment(\.dismiss) var dismiss
    let selectedDate: Date
    
    @State private var title: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    @State private var notes: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Event Details")) {
                    TextField("Title", text: $title)
                    DatePicker("Start", selection: $startDate)
                    DatePicker("End", selection: $endDate)
                }
                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(height: 80)
                }
            }
            .navigationTitle("New Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        HapticManager.trigger(.light)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        HapticManager.trigger(.success)
                        try? EventKitManager.shared.createEvent(title: title, startDate: startDate, endDate: endDate, notes: notes)
                        dismiss()
                    }
                }
            }
        }
    }
}
