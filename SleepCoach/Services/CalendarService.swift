import EventKit
import Foundation

protocol CalendarProviding {
    var authorizationLabel: String { get }
    func requestAccess() async throws -> Bool
    func firstCommitment(on date: Date) async throws -> CalendarCommitment?
    func createGymEvent(start: Date, end: Date, note: String) async throws
    func hasGymEvent(start: Date, end: Date) throws -> Bool
    func cancelGymEvent(start: Date, end: Date) throws
}

extension CalendarProviding {
    func cancelGymEvent(start: Date, end: Date) throws {}
}

final class CalendarService: CalendarProviding {
    private let eventStore: EKEventStore
    private let calendar: Calendar
    private let defaults: UserDefaults
    private let gymEventIDKey = "sleepCoachGymEventID"
    private static let gymEventTitle = "Gym · Sleep Coach plan"
    private static let gymEventNote = "Created by Sleep Coach."

    init(
        eventStore: EKEventStore = EKEventStore(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        self.eventStore = eventStore
        self.calendar = calendar
        self.defaults = defaults
    }

    var authorizationLabel: String {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess { return "Connected" }
        if status == .denied || status == .restricted { return "Denied" }
        return "Not connected"
    }

    func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    func firstCommitment(on date: Date) async throws -> CalendarCommitment? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw CalendarError.accessRequired
        }
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
                    && $0.title != Self.gymEventTitle
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
        event.title = Self.gymEventTitle
        event.startDate = start
        event.endDate = end
        event.notes = note
        event.calendar = eventStore.defaultCalendarForNewEvents
        try eventStore.save(event, span: .thisEvent, commit: true)
        if let eventIdentifier = event.eventIdentifier {
            defaults.set(eventIdentifier, forKey: gymEventIDKey)
        }
    }

    func hasGymEvent(start: Date, end: Date) throws -> Bool {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw CalendarError.accessRequired
        }
        if let identifier = defaults.string(forKey: gymEventIDKey),
           let event = eventStore.event(withIdentifier: identifier) {
            // Keep the identifier even when the user edits the event. It remains
            // the only unambiguous ownership handle for a later Undo.
            return event.status != .canceled
                && abs(event.startDate.timeIntervalSince(start)) < 1
                && abs(event.endDate.timeIntervalSince(end)) < 1
        }

        // Recover from termination after EventKit committed the event but before
        // its identifier reached UserDefaults. Exact title, generic note, and
        // exact planned interval avoid adopting an unrelated Calendar item.
        let recovered = ownedGymEvents(start: start, end: end)
        guard recovered.count == 1, let identifier = recovered[0].eventIdentifier else {
            return false
        }
        defaults.set(identifier, forKey: gymEventIDKey)
        return true
    }

    func cancelGymEvent(start: Date, end: Date) throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw CalendarError.accessRequired
        }

        if let identifier = defaults.string(forKey: gymEventIDKey),
           let identifiedEvent = eventStore.event(withIdentifier: identifier) {
            try eventStore.remove(identifiedEvent, span: .thisEvent, commit: true)
            defaults.removeObject(forKey: gymEventIDKey)
            return
        }

        let recovered = ownedGymEvents(start: start, end: end)
        guard recovered.count <= 1 else {
            // Exact duplicates can be user-created copies. Refuse to guess which
            // one the app owns and preserve the Undo state for manual recovery.
            throw CalendarError.ambiguousOwnedEvent
        }
        if let event = recovered.first {
            try eventStore.remove(event, span: .thisEvent, commit: true)
        }
        defaults.removeObject(forKey: gymEventIDKey)
    }

    static func isFallbackOwnedGymEvent(
        title: String?,
        note: String?,
        startDate: Date,
        endDate: Date,
        expectedStart: Date,
        expectedEnd: Date
    ) -> Bool {
        title == gymEventTitle
            && note == gymEventNote
            && abs(startDate.timeIntervalSince(expectedStart)) < 1
            && abs(endDate.timeIntervalSince(expectedEnd)) < 1
    }

    private func ownedGymEvents(start: Date, end: Date) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(
            withStart: start.addingTimeInterval(-1),
            end: end.addingTimeInterval(1),
            calendars: nil
        )
        return eventStore.events(matching: predicate).filter {
            $0.status != .canceled
                && Self.isFallbackOwnedGymEvent(
                    title: $0.title,
                    note: $0.notes,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    expectedStart: start,
                    expectedEnd: end
                )
        }
    }
}

enum CalendarError: LocalizedError {
    case accessRequired
    case ambiguousOwnedEvent

    var errorDescription: String? {
        switch self {
        case .accessRequired:
            "Calendar access is required to read commitments and add or remove the gym event."
        case .ambiguousOwnedEvent:
            "More than one matching gym event exists, so Sleep Coach did not remove either one. Delete the duplicate in Calendar, then try Undo again."
        }
    }
}
