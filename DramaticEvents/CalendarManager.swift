import EventKit

final class CalendarManager {

    private let store = EKEventStore()

    func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, _ in completion(granted) }
        } else {
            store.requestAccess(to: .event)   { granted, _ in completion(granted) }
        }
    }

    /// Returns the soonest non-all-day event starting in the next 24 hours.
    func fetchNextEvent(completion: @escaping (EKEvent?) -> Void) {
        fetchUpcomingEvents(limit: 1) { completion($0.first) }
    }

    /// Returns up to `limit` non-all-day events starting in the future,
    /// ordered by start time (soonest first). `withinHours` defines the
    /// horizon (default 24 h).
    func fetchUpcomingEvents(limit: Int,
                             withinHours hours: Double = 24,
                             completion: @escaping ([EKEvent]) -> Void) {
        let now = Date()
        let end = now.addingTimeInterval(hours * 3600)
        let cals = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: now, end: end,
                                                 calendars: cals.isEmpty ? nil : cals)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
        completion(Array(events.prefix(limit)))
    }
}
