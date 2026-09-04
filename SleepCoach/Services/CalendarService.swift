import EventKit
import Foundation

protocol CalendarProviding {
    func requestAccess() async throws -> Bool
    func firstCommitment(on date: Date) async throws -> CalendarCommitment?
    func createGymEvent(start: Date, end: Date, note: String) async throws
    func cancelGymEvent() throws
}

extension CalendarProviding {
    func cancelGymEvent() throws {}
}

final class CalendarService: CalendarProviding {
    private let eventStore: EKEventStore
    private let calendar: Calendar
    private let defaults: UserDefaults
    private let gymEventIDKey = "sleepCoachGymEventID"

    init(
        eventStore: EKEventStore = EKEventStore(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        self.eventStore = eventStore
        self.calendar = calendar
        self.defaults = defaults
    }

    func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    func firstCommitment(on date: Date) async throws -> CalendarCommitment? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let predicate = eventStore.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        let ownedEventID = defaults.string(forKey: gymEventIDKey)
        let events = eventStore.events(matching: predicate)
            .filter {
                Self.startsWithinRequestedDay($0.startDate, dayStart: dayStart, dayEnd: dayEnd)
                    && !$0.isAllDay
                    && $0.status != .canceled
                    && $0.availability != .free
                    && $0.eventIdentifier != ownedEventID
                    && $0.title != "Gym · Sleep Coach plan"
            }
            .sorted { $0.startDate < $1.startDate }
        guard let event = events.first else { return nil }
        return CalendarCommitment(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Calendar commitment",
            startDate: event.startDate,
            endDate: event.endDate,
            location: event.location
        )
    }

    static func startsWithinRequestedDay(_ startDate: Date, dayStart: Date, dayEnd: Date) -> Bool {
        startDate >= dayStart && startDate < dayEnd
    }

    func createGymEvent(start: Date, end: Date, note: String) async throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw CalendarError.accessRequired
        }
        let previousID = defaults.string(forKey: gymEventIDKey)
        let event = previousID.flatMap(eventStore.event(withIdentifier:)) ?? EKEvent(eventStore: eventStore)
        event.title = "Gym · Sleep Coach plan"
        event.startDate = start
        event.endDate = end
        event.notes = note
        event.calendar = eventStore.defaultCalendarForNewEvents
        try eventStore.save(event, span: .thisEvent, commit: true)
        if let eventIdentifier = event.eventIdentifier {
            defaults.set(eventIdentifier, forKey: gymEventIDKey)
        }
    }

    func cancelGymEvent() throws {
        guard let identifier = defaults.string(forKey: gymEventIDKey) else { return }
        if let event = eventStore.event(withIdentifier: identifier) {
            try eventStore.remove(event, span: .thisEvent, commit: true)
        }
        defaults.removeObject(forKey: gymEventIDKey)
    }
}

enum CalendarError: LocalizedError {
    case accessRequired

    var errorDescription: String? { "Calendar access is required to read commitments and add the gym event." }
}
