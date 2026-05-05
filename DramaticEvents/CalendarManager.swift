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
        let now = Date()
        let end = now.addingTimeInterval(24 * 60 * 60)
        let cals = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: now, end: end,
                                                 calendars: cals.isEmpty ? nil : cals)
        let event = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate > now }
            .min { $0.startDate < $1.startDate }
        completion(event)
    }
}
