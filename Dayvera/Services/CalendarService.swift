import EventKit
import Foundation

struct CalendarDescriptor: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
    let sourceIdentifier: String
    let sourceTitle: String
    let allowsContentModifications: Bool
    let isDefault: Bool
    let supportsBusyAvailability: Bool

    static let legacyDefault = CalendarDescriptor(
        id: "sleep-coach-default-calendar",
        title: "Default Calendar",
        sourceIdentifier: "sleep-coach-default-source",
        sourceTitle: "Calendar",
        allowsContentModifications: true,
        isDefault: true,
        supportsBusyAvailability: true
    )
}

struct CalendarSourceDescriptor: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let calendars: [CalendarDescriptor]

    static let legacyDefault = CalendarSourceDescriptor(
        id: CalendarDescriptor.legacyDefault.sourceIdentifier,
        title: CalendarDescriptor.legacyDefault.sourceTitle,
        calendars: [.legacyDefault]
    )
}

struct CalendarSelectionPreferences: Codable, Equatable, Sendable {
    /// `nil` means every currently visible calendar, including calendars added later.
    var planningCalendarIdentifiers: Set<String>?
    var detailedCalendarIdentifier: String?
    var busyCalendarIdentifiers: Set<String>
    var hasInitializedDetailedCalendar: Bool

    static let `default` = CalendarSelectionPreferences(
        planningCalendarIdentifiers: nil,
        detailedCalendarIdentifier: nil,
        busyCalendarIdentifiers: [],
        hasInitializedDetailedCalendar: false
    )

    func includesInPlanning(_ identifier: String) -> Bool {
        planningCalendarIdentifiers?.contains(identifier) ?? true
    }

    @discardableResult
    mutating func normalizeDestinationOverlap() -> Bool {
        guard let detailedCalendarIdentifier,
              busyCalendarIdentifiers.remove(detailedCalendarIdentifier) != nil else {
            return false
        }
        return true
    }

    /// Resolves the initial destination once. A later deletion or permissions
    /// change deliberately leaves the old identifier selected so the app can
    /// report it instead of silently switching calendars.
    @discardableResult
    mutating func initializeDetailedDestinationIfNeeded(
        from sources: [CalendarSourceDescriptor]
    ) -> Bool {
        guard !hasInitializedDetailedCalendar else { return false }
        let calendars = sources.flatMap(\.calendars)
        guard !calendars.isEmpty else { return false }
        hasInitializedDetailedCalendar = true
        detailedCalendarIdentifier = calendars
            .first(where: { $0.isDefault && $0.allowsContentModifications })?
            .id
        return true
    }
}

struct CalendarEventDestinations: Codable, Equatable, Sendable {
    let detailedCalendarIdentifier: String?
    let busyCalendarIdentifiers: Set<String>

    var requestedCount: Int {
        (detailedCalendarIdentifier == nil ? 0 : 1) + busyCalendarIdentifiers.count
    }
}

enum CalendarEventRole: String, Codable, Equatable, Hashable, Sendable {
    case detailed
    case busy

    var displayTitle: String {
        switch self {
        case .detailed: "Workout details"
        case .busy: "Busy"
        }
    }
}

struct CalendarEventReceipt: Identifiable, Codable, Equatable, Hashable, Sendable {
    let eventIdentifier: String
    let externalIdentifier: String?
    let calendarIdentifier: String
    let calendarTitle: String
    let role: CalendarEventRole
    let startDate: Date?
    let endDate: Date?

    init(
        eventIdentifier: String,
        externalIdentifier: String? = nil,
        calendarIdentifier: String,
        calendarTitle: String,
        role: CalendarEventRole,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.calendarTitle = calendarTitle
        self.role = role
        self.startDate = startDate
        self.endDate = endDate
    }

    var id: String {
        if !eventIdentifier.isEmpty { return eventIdentifier }
        if let externalIdentifier, !externalIdentifier.isEmpty {
            return "external:\(externalIdentifier):\(role.rawValue):\(calendarIdentifier)"
        }
        return "unresolved:\(role.rawValue):\(calendarIdentifier)"
    }
}

struct CalendarEventOperationFailure: Equatable, Sendable {
    let calendarIdentifier: String
    let calendarTitle: String
    let role: CalendarEventRole
    let message: String

    var localizedSummary: String {
        "\(calendarTitle): \(message)"
    }
}

struct CalendarEventWriteRequest: Sendable {
    let start: Date
    let end: Date
    let detailedTitle: String
    let detailedNotes: String
    let destinations: CalendarEventDestinations
}

struct CalendarEventWriteResult: Equatable, Sendable {
    let activeReceipts: [CalendarEventReceipt]
    let writtenReceipts: [CalendarEventReceipt]
    let failures: [CalendarEventOperationFailure]
}

struct CalendarEventVerificationResult: Equatable, Sendable {
    let verifiedReceipts: [CalendarEventReceipt]
    let missingReceipts: [CalendarEventReceipt]
    let failures: [CalendarEventOperationFailure]
}

struct CalendarEventUndoResult: Equatable, Sendable {
    let removedReceipts: [CalendarEventReceipt]
    let remainingReceipts: [CalendarEventReceipt]
    let failures: [CalendarEventOperationFailure]
}

@MainActor
protocol CalendarProviding: AnyObject {
    var authorizationLabel: String { get }
    func requestAccess() async throws -> Bool
    func firstCommitment(on date: Date) async throws -> CalendarCommitment?
    func createGymEvent(start: Date, end: Date, note: String) async throws
    func hasGymEvent(start: Date, end: Date) throws -> Bool
    func cancelGymEvent(start: Date, end: Date) throws

    func availableCalendarSources() throws -> [CalendarSourceDescriptor]
    func firstCommitment(
        on date: Date,
        calendarIdentifiers: Set<String>?
    ) async throws -> CalendarCommitment?
    func createGymEvents(_ request: CalendarEventWriteRequest) async throws -> CalendarEventWriteResult
    func verifyGymEvents(
        receipts: [CalendarEventReceipt],
        start: Date,
        end: Date
    ) throws -> CalendarEventVerificationResult
    func cancelGymEvents(
        receipts: [CalendarEventReceipt],
        start: Date,
        end: Date
    ) throws -> CalendarEventUndoResult
    func setEventStoreChangeHandler(_ handler: @escaping () -> Void)
}

extension CalendarProviding {
    func cancelGymEvent(start: Date, end: Date) throws {}

    func availableCalendarSources() throws -> [CalendarSourceDescriptor] {
        authorizationLabel == "Connected" ? [.legacyDefault] : []
    }

    func firstCommitment(
        on date: Date,
        calendarIdentifiers: Set<String>?
    ) async throws -> CalendarCommitment? {
        guard calendarIdentifiers?.isEmpty != true else { return nil }
        return try await firstCommitment(on: date)
    }

    func createGymEvents(_ request: CalendarEventWriteRequest) async throws -> CalendarEventWriteResult {
        guard request.destinations.requestedCount > 0 else {
            return CalendarEventWriteResult(activeReceipts: [], writtenReceipts: [], failures: [])
        }
        try await createGymEvent(
            start: request.start,
            end: request.end,
            note: request.detailedNotes
        )
        let descriptor = CalendarDescriptor.legacyDefault
        let receipt = CalendarEventReceipt(
            eventIdentifier: "legacy-app-owned-gym-event",
            calendarIdentifier: request.destinations.detailedCalendarIdentifier ?? descriptor.id,
            calendarTitle: descriptor.title,
            role: .detailed
        )
        return CalendarEventWriteResult(
            activeReceipts: [receipt],
            writtenReceipts: [receipt],
            failures: []
        )
    }

    func verifyGymEvents(
        receipts: [CalendarEventReceipt],
        start: Date,
        end: Date
    ) throws -> CalendarEventVerificationResult {
        let present = try hasGymEvent(start: start, end: end)
        let resolvedReceipts = receipts.isEmpty
            ? [CalendarEventReceipt(
                eventIdentifier: "legacy-app-owned-gym-event",
                calendarIdentifier: CalendarDescriptor.legacyDefault.id,
                calendarTitle: CalendarDescriptor.legacyDefault.title,
                role: .detailed
            )]
            : receipts
        return CalendarEventVerificationResult(
            verifiedReceipts: present ? resolvedReceipts : [],
            missingReceipts: present ? [] : resolvedReceipts,
            failures: []
        )
    }

    func cancelGymEvents(
        receipts: [CalendarEventReceipt],
        start: Date,
        end: Date
    ) throws -> CalendarEventUndoResult {
        try cancelGymEvent(start: start, end: end)
        return CalendarEventUndoResult(
            removedReceipts: receipts,
            remainingReceipts: [],
            failures: []
        )
    }

    func setEventStoreChangeHandler(_ handler: @escaping () -> Void) {}
}

@MainActor
final class CalendarService: CalendarProviding {
    struct ExternalMatchCandidate: Equatable, Sendable {
        let calendarIdentifier: String
        let startDate: Date
        let endDate: Date
    }

    private let eventStore: EKEventStore
    private let calendar: Calendar
    private let defaults: UserDefaults
    private let receiptStore: PrivateAppStatePersisting
    private let legacyGymEventIDKey = LegacyCompatibility.gymEventID
    private let gymEventReceiptsKey = LegacyCompatibility.gymEventReceipts
    private var eventStoreObserver: NSObjectProtocol?
    private var eventStoreChangeHandler: (() -> Void)?
    private static let legacyGymEventTitle = LegacyCompatibility.gymEventTitle
    private static let gymEventNoteMarker = AppBrand.calendarMarker
    static let busyEventTitle = "Busy"

    init(
        eventStore: EKEventStore = EKEventStore(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard,
        receiptStore: PrivateAppStatePersisting? = nil
    ) {
        self.eventStore = eventStore
        self.calendar = calendar
        self.defaults = defaults
        self.receiptStore = receiptStore ?? ApplicationSupportPrivateAppStateStore()
        eventStoreObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // EventKit invalidates previously fetched objects after this
                // notification. Refresh and make consumers rebuild descriptors
                // from identifiers rather than retaining fetched objects.
                self.eventStore.refreshSourcesIfNecessary()
                self.eventStoreChangeHandler?()
            }
        }
        _ = persistedReceipts()
    }

    deinit {
        if let eventStoreObserver {
            NotificationCenter.default.removeObserver(eventStoreObserver)
        }
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

    func setEventStoreChangeHandler(_ handler: @escaping () -> Void) {
        eventStoreChangeHandler = handler
    }

    func availableCalendarSources() throws -> [CalendarSourceDescriptor] {
        try requireAccess()
        eventStore.refreshSourcesIfNecessary()
        let defaultIdentifier = eventStore.defaultCalendarForNewEvents?.calendarIdentifier
        let descriptors = eventStore.calendars(for: .event).map { item in
            CalendarDescriptor(
                id: item.calendarIdentifier,
                title: item.title,
                sourceIdentifier: item.source.sourceIdentifier,
                sourceTitle: item.source.title,
                allowsContentModifications: item.allowsContentModifications,
                isDefault: item.calendarIdentifier == defaultIdentifier,
                supportsBusyAvailability: item.supportedEventAvailabilities.contains(.busy)
            )
        }
        let grouped = Dictionary(grouping: descriptors, by: \.sourceIdentifier)
        return grouped.values.map { calendars in
            let sorted = calendars.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return CalendarSourceDescriptor(
                id: sorted[0].sourceIdentifier,
                title: sorted[0].sourceTitle,
                calendars: sorted
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func firstCommitment(on date: Date) async throws -> CalendarCommitment? {
        try await firstCommitment(on: date, calendarIdentifiers: nil)
    }

    func firstCommitment(
        on date: Date,
        calendarIdentifiers: Set<String>?
    ) async throws -> CalendarCommitment? {
        try requireAccess()
        let selectedCalendars: [EKCalendar]?
        if let calendarIdentifiers {
            guard !calendarIdentifiers.isEmpty else { return nil }
            let resolved = calendarIdentifiers.compactMap(eventStore.calendar(withIdentifier:))
            guard !resolved.isEmpty else { return nil }
            selectedCalendars = resolved
        } else {
            selectedCalendars = nil
        }

        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let predicate = eventStore.predicateForEvents(
            withStart: dayStart,
            end: dayEnd,
            calendars: selectedCalendars
        )
        let receipts = persistedReceipts()
        let ownedEventIDs = Set(receipts.compactMap { receipt -> String? in
            switch resolveEvent(
                for: receipt,
                expectedStart: receipt.startDate ?? dayStart,
                expectedEnd: receipt.endDate ?? dayEnd
            ) {
            case .found(let event):
                return event.eventIdentifier ?? event.calendarItemIdentifier
            case .missing, .ambiguous:
                return nil
            }
        })
        let events = eventStore.events(matching: predicate)
            .filter {
                Self.startsWithinRequestedDay($0.startDate, dayStart: dayStart, dayEnd: dayEnd)
                    && !$0.isAllDay
                    && $0.status != .canceled
                    && $0.availability != .free
                    && !ownedEventIDs.contains($0.eventIdentifier ?? $0.calendarItemIdentifier)
                    && !Self.hasOwnedMarker(title: $0.title, note: $0.notes)
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

    static func eventContent(
        role: CalendarEventRole,
        detailedTitle: String,
        detailedNotes: String
    ) -> (title: String, notes: String?) {
        switch role {
        case .detailed:
            return (detailedTitle, detailedNotes)
        case .busy:
            return (busyEventTitle, nil)
        }
    }

    static func configureOwnedEvent(
        _ event: EKEvent,
        role: CalendarEventRole,
        detailedTitle: String,
        detailedNotes: String,
        start: Date,
        end: Date,
        supportsBusyAvailability: Bool
    ) {
        let content = eventContent(
            role: role,
            detailedTitle: detailedTitle,
            detailedNotes: detailedNotes
        )
        event.title = content.title
        event.notes = content.notes
        event.startDate = start
        event.endDate = end
        event.isAllDay = false
        event.alarms = nil
        event.recurrenceRules = nil
        event.structuredLocation = nil
        event.location = nil
        event.url = nil
        if let availability = ownedEventAvailability(
            supportsBusyAvailability: supportsBusyAvailability
        ) {
            event.availability = availability
        }
    }

    static func ownedEventAvailability(
        supportsBusyAvailability: Bool
    ) -> EKEventAvailability? {
        supportsBusyAvailability ? .busy : nil
    }

    func createGymEvents(_ request: CalendarEventWriteRequest) async throws -> CalendarEventWriteResult {
        try requireAccess()
        var activeReceipts = persistedReceipts()
        var writtenReceipts: [CalendarEventReceipt] = []
        var failures: [CalendarEventOperationFailure] = []
        var targets: [(CalendarEventRole, String)] = []
        if let identifier = request.destinations.detailedCalendarIdentifier {
            targets.append((.detailed, identifier))
        }
        targets.append(contentsOf: request.destinations.busyCalendarIdentifiers.sorted().map { (.busy, $0) })

        for (role, identifier) in targets {
            if role == .busy,
               identifier == request.destinations.detailedCalendarIdentifier {
                failures.append(CalendarEventOperationFailure(
                    calendarIdentifier: identifier,
                    calendarTitle: calendarTitle(for: identifier),
                    role: role,
                    message: "Workout details already use this calendar. Choose a different Busy destination."
                ))
                continue
            }
            guard let destination = eventStore.calendar(withIdentifier: identifier) else {
                failures.append(CalendarEventOperationFailure(
                    calendarIdentifier: identifier,
                    calendarTitle: "Selected calendar",
                    role: role,
                    message: "This calendar is no longer available. Choose another calendar in Settings."
                ))
                continue
            }
            guard destination.allowsContentModifications else {
                failures.append(CalendarEventOperationFailure(
                    calendarIdentifier: identifier,
                    calendarTitle: displayTitle(for: destination),
                    role: role,
                    message: "This calendar is read-only. Choose a writable calendar in Settings."
                ))
                continue
            }

            let activeReceiptsBeforeWrite = activeReceipts
            let existingReceipt = activeReceipts.first {
                $0.role == role && $0.calendarIdentifier == identifier
            }
            let event: EKEvent
            var createdNewEvent = false
            if let existingReceipt {
                switch resolveEvent(
                    for: existingReceipt,
                    expectedStart: request.start,
                    expectedEnd: request.end
                ) {
                case .found(let resolvedEvent):
                    event = resolvedEvent
                case .missing:
                    event = EKEvent(eventStore: eventStore)
                    createdNewEvent = true
                case .ambiguous:
                    failures.append(CalendarEventOperationFailure(
                        calendarIdentifier: identifier,
                        calendarTitle: displayTitle(for: destination),
                        role: role,
                        message: "More than one calendar item matches the saved identity, so Dayvera did not update or duplicate it. Use Undo after resolving the duplicate."
                    ))
                    continue
                }
            } else {
                event = EKEvent(eventStore: eventStore)
                createdNewEvent = true
            }
            event.calendar = destination
            Self.configureOwnedEvent(
                event,
                role: role,
                detailedTitle: request.detailedTitle,
                detailedNotes: request.detailedNotes,
                start: request.start,
                end: request.end,
                supportsBusyAvailability: destination.supportedEventAvailabilities.contains(.busy)
            )

            do {
                try eventStore.save(event, span: .thisEvent, commit: true)
                let eventIdentifier = event.eventIdentifier ?? event.calendarItemIdentifier
                let externalIdentifier = Self.nonempty(event.calendarItemExternalIdentifier)
                guard !eventIdentifier.isEmpty || externalIdentifier != nil else {
                    do {
                        try eventStore.remove(event, span: .thisEvent, commit: true)
                    } catch {
                        failures.append(CalendarEventOperationFailure(
                            calendarIdentifier: identifier,
                            calendarTitle: displayTitle(for: destination),
                            role: role,
                            message: "The event was saved without a usable identifier and could not be removed safely: \(error.localizedDescription)"
                        ))
                        continue
                    }
                    failures.append(CalendarEventOperationFailure(
                        calendarIdentifier: identifier,
                        calendarTitle: displayTitle(for: destination),
                        role: role,
                        message: "Calendar did not return a usable identifier, so Dayvera removed the untrackable event."
                    ))
                    continue
                }
                let receipt = CalendarEventReceipt(
                    eventIdentifier: eventIdentifier,
                    externalIdentifier: externalIdentifier,
                    calendarIdentifier: identifier,
                    calendarTitle: displayTitle(for: destination),
                    role: role,
                    startDate: request.start,
                    endDate: request.end
                )
                activeReceipts.removeAll {
                    (!eventIdentifier.isEmpty && $0.eventIdentifier == eventIdentifier)
                        || ($0.role == role && $0.calendarIdentifier == identifier)
                }
                activeReceipts.append(receipt)
                // Save after each external write so an interruption between
                // destinations still leaves an exact, independent Undo handle.
                if persistReceipts(activeReceipts) {
                    writtenReceipts.append(receipt)
                } else if createdNewEvent {
                    do {
                        try eventStore.remove(event, span: .thisEvent, commit: true)
                        activeReceipts = activeReceiptsBeforeWrite
                        failures.append(CalendarEventOperationFailure(
                            calendarIdentifier: identifier,
                            calendarTitle: displayTitle(for: destination),
                            role: role,
                            message: "Dayvera couldn’t securely save the Undo receipt, so it rolled back the Calendar event."
                        ))
                    } catch {
                        writtenReceipts.append(receipt)
                        failures.append(CalendarEventOperationFailure(
                            calendarIdentifier: identifier,
                            calendarTitle: displayTitle(for: destination),
                            role: role,
                            message: "The event was created, but its protected Undo receipt could not be saved or rolled back: \(error.localizedDescription)"
                        ))
                    }
                } else {
                    writtenReceipts.append(receipt)
                    failures.append(CalendarEventOperationFailure(
                        calendarIdentifier: identifier,
                        calendarTitle: displayTitle(for: destination),
                        role: role,
                        message: "The event was updated, but Dayvera couldn’t securely refresh its Undo receipt. The prior exact receipt was retained."
                    ))
                }
            } catch {
                failures.append(CalendarEventOperationFailure(
                    calendarIdentifier: identifier,
                    calendarTitle: displayTitle(for: destination),
                    role: role,
                    message: error.localizedDescription
                ))
            }
        }

        let obsoleteReceipts = activeReceipts.filter { receipt in
            !targets.contains {
                $0.0 == receipt.role && $0.1 == receipt.calendarIdentifier
            }
        }
        for receipt in obsoleteReceipts {
            // A detailed event is replaced only after the new detailed write
            // succeeds. Busy destinations are independent, so removing one is
            // honored even if a write to another Busy calendar fails.
            if receipt.role == .detailed,
               !writtenReceipts.contains(where: { $0.role == .detailed }) {
                continue
            }
            let event: EKEvent
            switch resolveEvent(
                for: receipt,
                expectedStart: request.start,
                expectedEnd: request.end
            ) {
            case .found(let resolvedEvent):
                event = resolvedEvent
            case .missing:
                activeReceipts.removeAll { $0.id == receipt.id }
                if !persistReceipts(activeReceipts) {
                    activeReceipts.append(receipt)
                    failures.append(CalendarEventOperationFailure(
                        calendarIdentifier: receipt.calendarIdentifier,
                        calendarTitle: receipt.calendarTitle,
                        role: receipt.role,
                        message: "The previous event is already absent, but its protected Undo receipt could not be cleared. Use Undo to retry."
                    ))
                }
                continue
            case .ambiguous:
                failures.append(CalendarEventOperationFailure(
                    calendarIdentifier: receipt.calendarIdentifier,
                    calendarTitle: receipt.calendarTitle,
                    role: receipt.role,
                    message: "The previous app-owned event has an ambiguous external identity. Dayvera retained its Undo receipt and did not remove any matching item."
                ))
                continue
            }
            do {
                try eventStore.remove(event, span: .thisEvent, commit: true)
                activeReceipts.removeAll { $0.id == receipt.id }
                if !persistReceipts(activeReceipts) {
                    activeReceipts.append(receipt)
                    failures.append(CalendarEventOperationFailure(
                        calendarIdentifier: receipt.calendarIdentifier,
                        calendarTitle: receipt.calendarTitle,
                        role: receipt.role,
                        message: "The previous event was removed, but its protected Undo receipt could not be cleared. Use Undo to retry."
                    ))
                }
            } catch {
                failures.append(CalendarEventOperationFailure(
                    calendarIdentifier: receipt.calendarIdentifier,
                    calendarTitle: receipt.calendarTitle,
                    role: receipt.role,
                    message: "The previous app-owned event could not be removed: \(error.localizedDescription) Use Undo to retry it."
                ))
            }
        }

        return CalendarEventWriteResult(
            activeReceipts: Self.sortedReceipts(activeReceipts),
            writtenReceipts: Self.sortedReceipts(writtenReceipts),
            failures: failures
        )
    }

    func verifyGymEvents(
        receipts: [CalendarEventReceipt],
        start: Date,
        end: Date
    ) throws -> CalendarEventVerificationResult {
        try requireAccess()
        // The service persists each receipt immediately after the corresponding
        // EventKit write. Merge those handles with AppModel's journal so a
        // termination between the two persistence boundaries does not strand an
        // event outside verification or Undo.
        var receipts = Self.sortedReceipts(Array(Set(receipts + persistedReceipts())))
        if receipts.isEmpty {
            let recovered = ownedGymEvents(start: start, end: end)
            guard recovered.count <= 1 else { throw CalendarError.ambiguousOwnedEvent }
            if let event = recovered.first {
                receipts = [receipt(for: event, role: .detailed)]
            } else {
                return CalendarEventVerificationResult(
                    verifiedReceipts: [],
                    missingReceipts: [],
                    failures: [CalendarEventOperationFailure(
                        calendarIdentifier: "",
                        calendarTitle: "Calendar",
                        role: .detailed,
                        message: "The saved legacy Workout event could not be found. It may have been edited or removed."
                    )]
                )
            }
        }
        var verified: [CalendarEventReceipt] = []
        var missing: [CalendarEventReceipt] = []
        var failures: [CalendarEventOperationFailure] = []
        for receipt in receipts {
            let event: EKEvent
            switch resolveEvent(for: receipt, expectedStart: start, expectedEnd: end) {
            case .found(let resolvedEvent):
                event = resolvedEvent
            case .missing:
                missing.append(receipt)
                continue
            case .ambiguous:
                missing.append(receipt)
                failures.append(CalendarEventOperationFailure(
                    calendarIdentifier: receipt.calendarIdentifier,
                    calendarTitle: receipt.calendarTitle,
                    role: receipt.role,
                    message: "More than one calendar item matches the saved external identifier. Dayvera did not choose between them."
                ))
                continue
            }
            guard event.status != .canceled,
                  abs(event.startDate.timeIntervalSince(start)) < 1,
                  abs(event.endDate.timeIntervalSince(end)) < 1,
                  receipt.calendarIdentifier.isEmpty
                    || event.calendar.calendarIdentifier == receipt.calendarIdentifier else {
                missing.append(receipt)
                continue
            }
            // Legacy single-ID receipts may have been migrated before Calendar
            // access was granted. Refresh their destination metadata from the
            // newly fetched event without ever searching for or redirecting it.
            verified.append(self.receipt(for: event, role: receipt.role))
        }
        if !persistReceipts(verified + missing) {
            failures.append(CalendarEventOperationFailure(
                calendarIdentifier: "",
                calendarTitle: "Calendar",
                role: .detailed,
                message: "Dayvera verified the events but couldn’t securely refresh their Undo receipts."
            ))
        }
        return CalendarEventVerificationResult(
            verifiedReceipts: Self.sortedReceipts(verified),
            missingReceipts: Self.sortedReceipts(missing),
            failures: failures
        )
    }

    func cancelGymEvents(
        receipts requestedReceipts: [CalendarEventReceipt],
        start: Date,
        end: Date
    ) throws -> CalendarEventUndoResult {
        try requireAccess()
        let storedReceipts = persistedReceipts()
        // Include service-persisted receipts that AppModel may not have journaled
        // yet if the process stopped immediately after an EventKit save.
        var receipts = Self.sortedReceipts(Array(Set(requestedReceipts + storedReceipts)))
        if receipts.isEmpty {
            let recovered = ownedGymEvents(start: start, end: end)
            guard recovered.count <= 1 else { throw CalendarError.ambiguousOwnedEvent }
            if let event = recovered.first {
                receipts = [receipt(for: event, role: .detailed)]
            }
        }
        var removed: [CalendarEventReceipt] = []
        var remaining: [CalendarEventReceipt] = []
        var failures: [CalendarEventOperationFailure] = []

        for receipt in receipts {
            let event: EKEvent
            switch resolveEvent(for: receipt, expectedStart: start, expectedEnd: end) {
            case .found(let resolvedEvent):
                event = resolvedEvent
            case .missing:
                // An externally deleted event is already undone. Do not search by
                // title or redirect the operation to any other calendar.
                removed.append(receipt)
                continue
            case .ambiguous:
                remaining.append(receipt)
                failures.append(CalendarEventOperationFailure(
                    calendarIdentifier: receipt.calendarIdentifier,
                    calendarTitle: receipt.calendarTitle,
                    role: receipt.role,
                    message: "More than one calendar item matches the saved external identifier. Dayvera did not remove either one."
                ))
                continue
            }
            do {
                try eventStore.remove(event, span: .thisEvent, commit: true)
                removed.append(receipt)
            } catch {
                remaining.append(receipt)
                failures.append(CalendarEventOperationFailure(
                    calendarIdentifier: receipt.calendarIdentifier,
                    calendarTitle: receipt.calendarTitle,
                    role: receipt.role,
                    message: error.localizedDescription
                ))
            }
        }

        remaining = Self.sortedReceipts(remaining)
        if !persistReceipts(remaining) {
            remaining = Self.sortedReceipts(remaining + removed)
            failures.append(contentsOf: removed.map { receipt in
                CalendarEventOperationFailure(
                    calendarIdentifier: receipt.calendarIdentifier,
                    calendarTitle: receipt.calendarTitle,
                    role: receipt.role,
                    message: "The event is absent, but its protected Undo receipt could not be cleared. Try Undo again."
                )
            })
        }
        return CalendarEventUndoResult(
            removedReceipts: Self.sortedReceipts(removed),
            remainingReceipts: remaining,
            failures: failures
        )
    }

    // MARK: - Legacy single-event API

    func createGymEvent(start: Date, end: Date, note: String) async throws {
        try requireAccess()
        guard let destination = eventStore.defaultCalendarForNewEvents else {
            throw CalendarError.destinationUnavailable("Default Calendar")
        }
        let result = try await createGymEvents(CalendarEventWriteRequest(
            start: start,
            end: end,
            detailedTitle: Self.legacyGymEventTitle,
            detailedNotes: note,
            destinations: CalendarEventDestinations(
                detailedCalendarIdentifier: destination.calendarIdentifier,
                busyCalendarIdentifiers: []
            )
        ))
        if let failure = result.failures.first {
            throw CalendarError.operationFailed(failure.localizedSummary)
        }
    }

    func hasGymEvent(start: Date, end: Date) throws -> Bool {
        try requireAccess()
        let receipts = persistedReceipts()
        if !receipts.isEmpty {
            let result = try verifyGymEvents(receipts: receipts, start: start, end: end)
            return result.missingReceipts.isEmpty
        }

        let recovered = ownedGymEvents(start: start, end: end)
        guard recovered.count == 1, let event = recovered.first else { return false }
        let receipt = receipt(for: event, role: .detailed)
        persistReceipts([receipt])
        return true
    }

    func cancelGymEvent(start: Date, end: Date) throws {
        try requireAccess()
        let receipts = persistedReceipts()
        if !receipts.isEmpty {
            let result = try cancelGymEvents(receipts: receipts, start: start, end: end)
            if let failure = result.failures.first {
                throw CalendarError.operationFailed(failure.localizedSummary)
            }
            return
        }

        let recovered = ownedGymEvents(start: start, end: end)
        guard recovered.count <= 1 else { throw CalendarError.ambiguousOwnedEvent }
        if let event = recovered.first {
            try eventStore.remove(event, span: .thisEvent, commit: true)
        }
    }

    static func isFallbackOwnedGymEvent(
        title: String?,
        note: String?,
        startDate: Date,
        endDate: Date,
        expectedStart: Date,
        expectedEnd: Date
    ) -> Bool {
        title == legacyGymEventTitle
            && note == LegacyCompatibility.calendarMarker
            && abs(startDate.timeIntervalSince(expectedStart)) < 1
            && abs(endDate.timeIntervalSince(expectedEnd)) < 1
    }

    static func requiresLegacyMarkerRecovery(_ receipt: CalendarEventReceipt) -> Bool {
        receipt.role == .detailed
            && !receipt.eventIdentifier.isEmpty
            && nonempty(receipt.externalIdentifier) == nil
            && receipt.calendarIdentifier.isEmpty
            && receipt.startDate == nil
            && receipt.endDate == nil
    }

    static func uniqueExactExternalMatchIndex(
        in candidates: [ExternalMatchCandidate],
        calendarIdentifier: String,
        startDate: Date,
        endDate: Date
    ) -> Int? {
        // A duplicated external identifier is not enough to establish identity.
        // Both pieces of durable receipt context must be present and uniquely
        // identify one candidate; interval-only or calendar-only matches are
        // deliberately ambiguous.
        guard !calendarIdentifier.isEmpty else { return nil }
        let matches = candidates.indices.filter { index in
            candidates[index].calendarIdentifier == calendarIdentifier
                && abs(candidates[index].startDate.timeIntervalSince(startDate)) < 1
                && abs(candidates[index].endDate.timeIntervalSince(endDate)) < 1
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    private func requireAccess() throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw CalendarError.accessRequired
        }
    }

    private func calendarTitle(for identifier: String) -> String {
        guard let calendar = eventStore.calendar(withIdentifier: identifier) else {
            return "Selected calendar"
        }
        return displayTitle(for: calendar)
    }

    enum ReceiptEventResolution {
        case found(EKEvent)
        case missing
        case ambiguous
    }

    func resolveEvent(
        for receipt: CalendarEventReceipt,
        expectedStart: Date,
        expectedEnd: Date
    ) -> ReceiptEventResolution {
        if !receipt.eventIdentifier.isEmpty {
            if let event = eventStore.event(withIdentifier: receipt.eventIdentifier)
                ?? eventStore.calendarItem(withIdentifier: receipt.eventIdentifier) as? EKEvent {
                return .found(event)
            }
        }
        if Self.requiresLegacyMarkerRecovery(receipt) {
            let recovered = ownedGymEvents(start: expectedStart, end: expectedEnd)
            if recovered.count == 1, let event = recovered.first { return .found(event) }
            return recovered.isEmpty ? .missing : .ambiguous
        }
        guard let externalIdentifier = receipt.externalIdentifier,
              !externalIdentifier.isEmpty else { return .missing }
        let events = eventStore.calendarItems(withExternalIdentifier: externalIdentifier)
            .compactMap { $0 as? EKEvent }
        guard events.count != 1 else { return .found(events[0]) }
        guard !events.isEmpty else { return .missing }

        // External IDs can legitimately map to more than one item. Require one
        // unique exact calendar-and-interval match; never degrade to matching
        // only one half of that identity or a user-visible title.
        let receiptStart = receipt.startDate ?? expectedStart
        let receiptEnd = receipt.endDate ?? expectedEnd
        let candidates = events.map {
            ExternalMatchCandidate(
                calendarIdentifier: $0.calendar.calendarIdentifier,
                startDate: $0.startDate,
                endDate: $0.endDate
            )
        }
        guard let index = Self.uniqueExactExternalMatchIndex(
            in: candidates,
            calendarIdentifier: receipt.calendarIdentifier,
            startDate: receiptStart,
            endDate: receiptEnd
        ) else { return .ambiguous }
        return .found(events[index])
    }

    private func receipt(for event: EKEvent, role: CalendarEventRole) -> CalendarEventReceipt {
        CalendarEventReceipt(
            eventIdentifier: event.eventIdentifier ?? event.calendarItemIdentifier,
            externalIdentifier: Self.nonempty(event.calendarItemExternalIdentifier),
            calendarIdentifier: event.calendar.calendarIdentifier,
            calendarTitle: displayTitle(for: event.calendar),
            role: role,
            startDate: event.startDate,
            endDate: event.endDate
        )
    }

    private func displayTitle(for calendar: EKCalendar) -> String {
        let duplicateTitleCount = eventStore.calendars(for: .event).reduce(into: 0) {
            if $1.title.localizedCaseInsensitiveCompare(calendar.title) == .orderedSame {
                $0 += 1
            }
        }
        guard duplicateTitleCount > 1 else { return calendar.title }
        return "\(calendar.title) (\(calendar.source.title))"
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func hasOwnedMarker(title: String?, note: String?) -> Bool {
        guard title?.hasPrefix("Gym ·") == true else { return false }
        return note?.contains(gymEventNoteMarker) == true || note?.contains(LegacyCompatibility.calendarMarker) == true
    }

    private func persistedReceipts() -> [CalendarEventReceipt] {
        var receipts: [CalendarEventReceipt] = []
        if let data = receiptStore.data(forKey: gymEventReceiptsKey),
           let decoded = try? JSONDecoder().decode([CalendarEventReceipt].self, from: data) {
            receipts.append(contentsOf: decoded)
        }

        let legacyReceiptData = defaults.data(forKey: gymEventReceiptsKey)
        let legacyReceipts = legacyReceiptData.flatMap {
            try? JSONDecoder().decode([CalendarEventReceipt].self, from: $0)
        } ?? []
        receipts.append(contentsOf: legacyReceipts)

        let legacyIdentifier = defaults.string(forKey: legacyGymEventIDKey)
        if let legacyIdentifier {
            if !receipts.contains(where: { $0.eventIdentifier == legacyIdentifier }) {
                let legacyEvent = eventStore.event(withIdentifier: legacyIdentifier)
                receipts.append(CalendarEventReceipt(
                    eventIdentifier: legacyIdentifier,
                    externalIdentifier: Self.nonempty(
                        legacyEvent?.calendarItemExternalIdentifier
                    ),
                    calendarIdentifier: legacyEvent?.calendar.calendarIdentifier ?? "",
                    calendarTitle: legacyEvent?.calendar.title ?? "Calendar",
                    role: .detailed,
                    startDate: legacyEvent?.startDate,
                    endDate: legacyEvent?.endDate
                ))
            }
        }

        receipts = Self.sortedReceipts(receipts)
        if legacyReceiptData != nil || legacyIdentifier != nil,
           persistReceipts(receipts) {
            if !legacyReceipts.isEmpty {
                defaults.removeObject(forKey: gymEventReceiptsKey)
            }
            defaults.removeObject(forKey: legacyGymEventIDKey)
        }
        return receipts
    }

    @discardableResult
    private func persistReceipts(_ receipts: [CalendarEventReceipt]) -> Bool {
        let receipts = Self.sortedReceipts(Array(Set(receipts)))
        if receipts.isEmpty {
            return receiptStore.removeData(forKey: gymEventReceiptsKey)
        } else if let data = try? JSONEncoder().encode(receipts) {
            return receiptStore.set(data, forKey: gymEventReceiptsKey)
        }
        return false
    }

    private static func sortedReceipts(
        _ receipts: [CalendarEventReceipt]
    ) -> [CalendarEventReceipt] {
        Array(Set(receipts)).sorted {
            if $0.role != $1.role { return $0.role == .detailed }
            let titleComparison = $0.calendarTitle.localizedCaseInsensitiveCompare($1.calendarTitle)
            if titleComparison != .orderedSame { return titleComparison == .orderedAscending }
            return $0.eventIdentifier < $1.eventIdentifier
        }
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
    case destinationUnavailable(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessRequired:
            "Calendar access is required to read commitments and add or remove plan events."
        case .ambiguousOwnedEvent:
            "More than one matching gym event exists, so Dayvera did not remove either one. Delete the duplicate in Calendar, then try Undo again."
        case .destinationUnavailable(let name):
            "\(name) is no longer available. Choose another calendar in Settings."
        case .operationFailed(let message):
            message
        }
    }
}
