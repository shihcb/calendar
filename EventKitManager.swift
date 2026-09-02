import Foundation
import EventKit

/// Manages direct native integration with Apple Calendar (EventKit) and iCloud Calendars
@MainActor
public class EventKitManager: ObservableObject {
    public static let shared = EventKitManager()
    
    private let eventStore = EKEventStore()
    
    @Published public var isAuthorized: Bool = false
    @Published public var events: [EKEvent] = []
    @Published public var selectedDateEvents: [EKEvent] = []
    @Published public var userCalendars: [EKCalendar] = []
    
    private init() {
        checkPermission()
    }
    
    /// Check system calendar permissions
    public func checkPermission() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess:
            self.isAuthorized = true
            self.fetchUserCalendars()
            self.fetchEventsForCurrentMonth()
        default:
            self.isAuthorized = false
            Task {
                await self.requestAccess()
            }
        }
    }
    
    /// Request full access to system calendars (iCloud & Local)
    public func requestAccess() async {
        do {
            if #available(iOS 17.0, macOS 14.0, *) {
                let granted = try await eventStore.requestFullAccessToEvents()
                self.isAuthorized = granted
            } else {
                let granted = try await eventStore.requestAccess(to: .event)
                self.isAuthorized = granted
            }
            if self.isAuthorized {
                self.fetchUserCalendars()
                self.fetchEventsForCurrentMonth()
            }
        } catch {
            print("EventKit authorization failed: \(error.localizedDescription)")
            self.isAuthorized = false
        }
    }

    /// Retrieve list of all iCloud and system calendars
    public func fetchUserCalendars() {
        guard isAuthorized else { return }
        let cals = eventStore.calendars(for: .event)
        DispatchQueue.main.async {
            self.userCalendars = cals
        }
    }
    
    /// Fetch all events for a given month range
    public func fetchEvents(for date: Date = Date()) {
        guard isAuthorized else { return }
        
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return }
        
        let cals = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: monthInterval.start, end: monthInterval.end, calendars: cals.isEmpty ? nil : cals)
        let fetched = eventStore.events(matching: predicate)
        
        DispatchQueue.main.async {
            self.userCalendars = cals
            self.events = fetched.sorted(by: { $0.startDate < $1.startDate })
        }
    }
    
    public func fetchEventsForCurrentMonth() {
        fetchEvents(for: Date())
    }
    
    /// Add a new native event directly to Apple System Calendar / iCloud
    public func createEvent(title: String, startDate: Date, endDate: Date, notes: String? = nil, location: String? = nil) throws {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        event.location = location
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        try eventStore.save(event, span: .thisEvent)
        fetchEvents(for: startDate)
    }
    
    /// Remove native event from Apple System Calendar
    public func deleteEvent(_ event: EKEvent) throws {
        try eventStore.remove(event, span: .thisEvent)
        fetchEvents(for: event.startDate)
    }
}
