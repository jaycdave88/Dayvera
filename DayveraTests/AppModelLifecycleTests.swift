import EventKit
import SwiftData
import XCTest
@testable import Dayvera

@MainActor
final class AppModelLifecycleTests: XCTestCase {
    func testCalendarCommitmentMustStartInsideRequestedDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayStart = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        XCTAssertFalse(CalendarService.startsWithinRequestedDay(dayStart.addingTimeInterval(-60), dayStart: dayStart, dayEnd: dayEnd))
        XCTAssertTrue(CalendarService.startsWithinRequestedDay(dayStart, dayStart: dayStart, dayEnd: dayEnd))
        XCTAssertTrue(CalendarService.startsWithinRequestedDay(dayEnd.addingTimeInterval(-60), dayStart: dayStart, dayEnd: dayEnd))
        XCTAssertFalse(CalendarService.startsWithinRequestedDay(dayEnd, dayStart: dayStart, dayEnd: dayEnd))
    }

    func testCalendarFallbackOwnershipRequiresExactGenericMarkerAndInterval() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(60 * 60)

        XCTAssertTrue(CalendarService.isFallbackOwnedGymEvent(
            title: "Gym · Sleep Coach plan",
            note: "Created by Sleep Coach.",
            startDate: start,
            endDate: end,
            expectedStart: start,
            expectedEnd: end
        ))
        XCTAssertFalse(CalendarService.isFallbackOwnedGymEvent(
            title: "Gym · Sleep Coach plan",
            note: "My own event",
            startDate: start,
            endDate: end,
            expectedStart: start,
            expectedEnd: end
        ))
        XCTAssertFalse(CalendarService.isFallbackOwnedGymEvent(
            title: "Gym · Sleep Coach plan",
            note: "Created by Sleep Coach.",
            startDate: start.addingTimeInterval(60),
            endDate: end,
            expectedStart: start,
            expectedEnd: end
        ))
    }

    func testDuplicateExternalCalendarIdentityRequiresUniqueExactCalendarAndInterval() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(3_600)
        let candidates = [
            CalendarService.ExternalMatchCandidate(
                calendarIdentifier: "other",
                startDate: start,
                endDate: end
            ),
            CalendarService.ExternalMatchCandidate(
                calendarIdentifier: "personal",
                startDate: start.addingTimeInterval(60),
                endDate: end.addingTimeInterval(60)
            )
        ]

        XCTAssertNil(CalendarService.uniqueExactExternalMatchIndex(
            in: candidates,
            calendarIdentifier: "personal",
            startDate: start,
            endDate: end
        ))

        let exactCandidates = candidates + [CalendarService.ExternalMatchCandidate(
            calendarIdentifier: "personal",
            startDate: start,
            endDate: end
        )]
        XCTAssertEqual(CalendarService.uniqueExactExternalMatchIndex(
            in: exactCandidates,
            calendarIdentifier: "personal",
            startDate: start,
            endDate: end
        ), 2)
        XCTAssertNil(CalendarService.uniqueExactExternalMatchIndex(
            in: exactCandidates + [exactCandidates[2]],
            calendarIdentifier: "personal",
            startDate: start,
            endDate: end
        ))
    }

    func testStaleMigratedLegacyCalendarReceiptUsesExactMarkerRecovery() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let eventStore = StubEventStore()
        let receiptStore = MockPrivateAppStateStore()
        let service = CalendarService(
            eventStore: eventStore,
            defaults: defaults,
            receiptStore: receiptStore
        )
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(3_600)
        let migrated = CalendarEventReceipt(
            eventIdentifier: "stale-legacy-identifier",
            calendarIdentifier: "",
            calendarTitle: "Calendar",
            role: .detailed
        )
        XCTAssertTrue(CalendarService.requiresLegacyMarkerRecovery(migrated))

        let exactLegacyEvent = EKEvent(eventStore: eventStore)
        exactLegacyEvent.title = "Gym · Sleep Coach plan"
        exactLegacyEvent.notes = "Created by Sleep Coach."
        exactLegacyEvent.startDate = start
        exactLegacyEvent.endDate = end
        eventStore.matchingEvents = [exactLegacyEvent]
        if case .found(let recovered) = service.resolveEvent(
            for: migrated,
            expectedStart: start,
            expectedEnd: end
        ) {
            XCTAssertIdentical(recovered, exactLegacyEvent)
        } else {
            XCTFail("Expected the exact legacy marker and interval to recover the stale receipt")
        }

        let unownedEvent = EKEvent(eventStore: eventStore)
        unownedEvent.title = "Gym · Sleep Coach plan"
        unownedEvent.notes = "User-created event"
        unownedEvent.startDate = start
        unownedEvent.endDate = end
        eventStore.matchingEvents = [unownedEvent]
        if case .missing = service.resolveEvent(
            for: migrated,
            expectedStart: start,
            expectedEnd: end
        ) {
            // Expected: marker recovery never broadens to title/time alone.
        } else {
            XCTFail("A non-owned event must not recover a stale legacy receipt")
        }

        let modern = CalendarEventReceipt(
            eventIdentifier: "stale-modern-identifier",
            externalIdentifier: "external-id",
            calendarIdentifier: "personal",
            calendarTitle: "Personal",
            role: .detailed,
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600)
        )
        XCTAssertFalse(CalendarService.requiresLegacyMarkerRecovery(modern))
    }

    func testBusyCalendarContentNeverContainsWorkoutOrHealthDetails() {
        let sensitiveNotes = "Workout: Lower body\nReadiness: 42/100\nData confidence: Low"

        let detailed = CalendarService.eventContent(
            role: .detailed,
            detailedTitle: "Gym · Lower body",
            detailedNotes: sensitiveNotes
        )
        let busy = CalendarService.eventContent(
            role: .busy,
            detailedTitle: "Gym · Lower body",
            detailedNotes: sensitiveNotes
        )

        XCTAssertEqual(detailed.title, "Gym · Lower body")
        XCTAssertEqual(detailed.notes, sensitiveNotes)
        XCTAssertEqual(busy.title, "Busy")
        XCTAssertNil(busy.notes)
    }

    func testCalendarEventNormalizationClearsEditsThatCouldLeakOrRepeat() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        event.title = "Edited"
        event.notes = "Sensitive"
        event.isAllDay = true
        event.location = "Gym"
        event.url = URL(string: "https://example.com/private")
        event.structuredLocation = EKStructuredLocation(title: "Private place")
        event.alarms = [EKAlarm(relativeOffset: -300)]
        event.recurrenceRules = [EKRecurrenceRule(
            recurrenceWith: .daily,
            interval: 1,
            end: nil
        )]

        CalendarService.configureOwnedEvent(
            event,
            role: .busy,
            detailedTitle: "Gym · Lower body",
            detailedNotes: "Readiness: 42/100",
            start: start,
            end: start.addingTimeInterval(3_600),
            supportsBusyAvailability: true
        )

        XCTAssertEqual(event.title, "Busy")
        XCTAssertNil(event.notes)
        XCTAssertFalse(event.isAllDay)
        XCTAssertNil(event.location)
        XCTAssertNil(event.url)
        XCTAssertNil(event.structuredLocation)
        XCTAssertTrue(event.alarms?.isEmpty ?? true)
        XCTAssertTrue(event.recurrenceRules?.isEmpty ?? true)
        // An unattached EKEvent reports `.notSupported`; the pure decision
        // verifies that CalendarService opts into Busy only after the selected
        // destination advertises support.
        XCTAssertEqual(
            CalendarService.ownedEventAvailability(supportsBusyAvailability: true),
            .busy
        )
        XCTAssertNil(
            CalendarService.ownedEventAvailability(supportsBusyAvailability: false)
        )
    }

    func testCalendarDefaultsUseAllForPlanningDefaultForDetailsAndNoBusyCopies() {
        var preferences = CalendarSelectionPreferences.default
        let sources = calendarSourcesFixture()

        XCTAssertTrue(preferences.initializeDetailedDestinationIfNeeded(from: sources))

        XCTAssertNil(preferences.planningCalendarIdentifiers)
        XCTAssertTrue(preferences.includesInPlanning("personal"))
        XCTAssertTrue(preferences.includesInPlanning("work"))
        XCTAssertEqual(preferences.detailedCalendarIdentifier, "personal")
        XCTAssertTrue(preferences.busyCalendarIdentifiers.isEmpty)
    }

    func testLegacyAppliedStatusDecodesWithoutReceiptFields() throws {
        let json = """
        {
          "wakeTime": 796435200,
          "gymStart": 796438800,
          "gymEnd": 796442400,
          "wakeAlarmApplied": true,
          "calendarEventApplied": true,
          "calendarEventRequested": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppliedPlanStatus.self, from: json)

        XCTAssertTrue(decoded.calendarEventReceipts.isEmpty)
        XCTAssertEqual(decoded.appliedCalendarEventCount, 1)
        XCTAssertEqual(decoded.requestedCalendarEventCount, 1)
        XCTAssertTrue(decoded.calendarEventsComplete)
    }

    func testLegacySingleCalendarEventIdentifierMigratesToReceiptArray() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("legacy-event-id", forKey: "sleepCoachGymEventID")
        let privateState = MockPrivateAppStateStore()

        _ = CalendarService(defaults: defaults, receiptStore: privateState)

        XCTAssertNil(defaults.string(forKey: "sleepCoachGymEventID"))
        XCTAssertNil(defaults.data(forKey: "sleepCoachGymEventReceipts"))
        let data = try XCTUnwrap(privateState.data(forKey: "sleepCoachGymEventReceipts"))
        let receipts = try JSONDecoder().decode([CalendarEventReceipt].self, from: data)
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts.first?.eventIdentifier, "legacy-event-id")
        XCTAssertEqual(receipts.first?.role, .detailed)
    }

    func testInterruptedReceiptMigrationMergesPrivateAndLegacyJournals() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let privateState = MockPrivateAppStateStore()
        let protectedReceipt = CalendarEventReceipt(
            eventIdentifier: "protected-event",
            calendarIdentifier: "personal",
            calendarTitle: "Personal",
            role: .detailed
        )
        let legacyReceipt = CalendarEventReceipt(
            eventIdentifier: "legacy-event",
            calendarIdentifier: "work",
            calendarTitle: "Work",
            role: .busy
        )
        XCTAssertTrue(privateState.set(
            try JSONEncoder().encode([protectedReceipt]),
            forKey: "sleepCoachGymEventReceipts"
        ))
        defaults.set(
            try JSONEncoder().encode([legacyReceipt]),
            forKey: "sleepCoachGymEventReceipts"
        )

        _ = CalendarService(defaults: defaults, receiptStore: privateState)

        let protectedData = try XCTUnwrap(
            privateState.data(forKey: "sleepCoachGymEventReceipts")
        )
        let receipts = try JSONDecoder().decode(
            [CalendarEventReceipt].self,
            from: protectedData
        )
        XCTAssertEqual(Set(receipts), Set([protectedReceipt, legacyReceipt]))
        XCTAssertNil(defaults.data(forKey: "sleepCoachGymEventReceipts"))
    }

    func testHealthAdjacentLegacyDefaultsMigrateToPrivateStateStore() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = WellnessPreferences(sleepNeedMinutes: 510)
        let applied = AppliedPlanStatus(
            wakeTime: Date(timeIntervalSince1970: 1_800_000_000),
            gymStart: Date(timeIntervalSince1970: 1_800_001_200),
            gymEnd: Date(timeIntervalSince1970: 1_800_004_800),
            wakeAlarmApplied: true,
            calendarEventApplied: true,
            calendarEventRequested: true
        )
        defaults.set(try JSONEncoder().encode(preferences), forKey: "wellnessPreferences")
        defaults.set(try JSONEncoder().encode(applied), forKey: "appliedPlanStatus")
        defaults.set(true, forKey: "healthAuthorizationRequested")
        let privateState = MockPrivateAppStateStore()

        let model = AppModel(
            health: MockHealthService(),
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults,
            privateStateStore: privateState
        )

        XCTAssertEqual(model.preferences, preferences)
        XCTAssertEqual(model.appliedPlanStatus, applied)
        XCTAssertNil(defaults.data(forKey: "wellnessPreferences"))
        XCTAssertNil(defaults.data(forKey: "appliedPlanStatus"))
        XCTAssertNil(defaults.object(forKey: "healthAuthorizationRequested"))
        XCTAssertNotNil(privateState.data(forKey: "wellnessPreferences"))
        XCTAssertNotNil(privateState.data(forKey: "appliedPlanStatus"))
        let migratedHealthSetup = try JSONDecoder().decode(
            Bool.self,
            from: XCTUnwrap(privateState.data(forKey: "healthAuthorizationRequested"))
        )
        XCTAssertTrue(migratedHealthSetup)

        model.preferences.sleepNeedMinutes = 525
        let savedPreferences = try JSONDecoder().decode(
            WellnessPreferences.self,
            from: XCTUnwrap(privateState.data(forKey: "wellnessPreferences"))
        )
        XCTAssertEqual(savedPreferences.sleepNeedMinutes, 525)
    }

    func testPrivateStateStoreWritesInsideBackupExcludedDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dayvera-private-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ApplicationSupportPrivateAppStateStore(directoryURL: directory)
        let payload = Data("private state".utf8)

        XCTAssertTrue(store.set(payload, forKey: "testState"))
        XCTAssertEqual(store.data(forKey: "testState"), payload)
        XCTAssertEqual(
            try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
            true
        )
        let fileURL = directory.appendingPathComponent("testState.json", isDirectory: false)
        XCTAssertEqual(
            try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
            true
        )
        XCTAssertTrue(store.removeData(forKey: "testState"))
        XCTAssertNil(store.data(forKey: "testState"))
    }

    func testMeaningfulUseAndMotivationReceiptsUseInjectedPrivateStore() {
        let privateState = MockPrivateAppStateStore()
        let model = AppModel(
            health: MockHealthService(),
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            privateStateStore: privateState,
            demoMode: true
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let previousUse = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 18))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 8))!

        XCTAssertEqual(model.returningExperience(now: now, calendar: calendar), .none)
        XCTAssertTrue(model.recordMeaningfulUse(at: previousUse))
        XCTAssertEqual(model.returningExperience(now: now, calendar: calendar), .welcomeBack)

        XCTAssertFalse(model.hasAcknowledgedMotivationReceipt("training-week-2026-09-01"))
        XCTAssertTrue(model.acknowledgeMotivationReceipt("training-week-2026-09-01"))
        XCTAssertTrue(model.hasAcknowledgedMotivationReceipt("training-week-2026-09-01"))

        let reloaded = AppModel(
            health: MockHealthService(),
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            privateStateStore: privateState,
            demoMode: true
        )
        XCTAssertEqual(reloaded.returningExperience(now: now, calendar: calendar), .welcomeBack)
        XCTAssertTrue(reloaded.hasAcknowledgedMotivationReceipt("training-week-2026-09-01"))
    }

    func testFailedPrivateWriteDoesNotClaimMotivationReceiptWasSaved() {
        let privateState = MockPrivateAppStateStore()
        privateState.failWrites = true
        let model = AppModel(
            health: MockHealthService(),
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            privateStateStore: privateState,
            demoMode: true
        )

        XCTAssertFalse(model.recordMeaningfulUse(at: .now))
        XCTAssertFalse(model.acknowledgeMotivationReceipt("training-week"))
        XCTAssertFalse(model.hasAcknowledgedMotivationReceipt("training-week"))
    }

    func testApplyStopsBeforeSystemWritesWhenPrivateJournalCannotBeSaved() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        let alarms = MockAlarmService()
        let privateState = MockPrivateAppStateStore()
        privateState.failWrites = true
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: alarms,
            defaults: defaults,
            privateStateStore: privateState,
            demoMode: true
        )

        await model.applyPlan()

        XCTAssertEqual(calendar.gymEventCreationCount, 0)
        XCTAssertEqual(alarms.scheduleCount, 0)
        XCTAssertNil(model.appliedPlanStatus)
        XCTAssertEqual(
            model.notice,
            "Dayvera couldn’t securely save the plan before applying it. No system changes were requested."
        )
    }

    func testFirstRunDoesNotFetchOrClaimHealthIsConnectedBeforeAuthorization() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let health = MockHealthService()
        let calendar = MockCalendarService()
        let alarms = MockAlarmService()
        let model = AppModel(
            health: health,
            calendar: calendar,
            alarms: alarms,
            defaults: defaults
        )

        await model.start()

        XCTAssertEqual(health.authorizationRequestCount, 0)
        XCTAssertEqual(health.fetchCount, 0)
        XCTAssertEqual(health.observerConfigurationCount, 0)
        XCTAssertEqual(model.healthConnectionState, .notRequested)
        XCTAssertEqual(model.healthStatus, "Not requested")
        XCTAssertTrue(model.snapshot.samples.isEmpty)
    }

    func testLegacyHealthSetupRecommendsReviewForExpandedAuthorizationSchema() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")
        let health = MockHealthService()
        health.authorizationRequestSchema = HealthAuthorizationRequestSchema(
            version: 2,
            readTypeIdentifiers: ["expanded"]
        )
        health.accessRequestStatus = .shouldRequest
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )

        await model.start()

        XCTAssertTrue(model.healthAccessReviewRecommended)
        XCTAssertEqual(health.authorizationStatusRequestCount, 1)
        XCTAssertEqual(health.authorizationRequestCount, 0)
    }

    func testReviewingHealthAccessPersistsCurrentSchemaVersion() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")
        let health = MockHealthService()
        health.authorizationRequestSchema = HealthAuthorizationRequestSchema(
            version: 2,
            readTypeIdentifiers: ["expanded"]
        )
        health.accessRequestStatus = .shouldRequest
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )
        await model.start()
        XCTAssertTrue(model.healthAccessReviewRecommended)

        let connected = await model.connectHealth()

        XCTAssertTrue(connected)
        XCTAssertFalse(model.healthAccessReviewRecommended)
        XCTAssertEqual(defaults.integer(forKey: "healthAuthorizationSchemaVersion"), 2)
        XCTAssertEqual(health.authorizationRequestCount, 1)
    }

    func testHealthAuthorizationFailureKeepsSetupRetryable() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let health = MockHealthService()
        health.authorizationError = StubError.healthAuthorizationFailed
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )

        let connected = await model.connectHealth()

        XCTAssertFalse(connected)
        XCTAssertEqual(health.authorizationRequestCount, 1)
        XCTAssertEqual(health.fetchCount, 0)
        XCTAssertEqual(model.healthConnectionState, .notRequested)
        XCTAssertFalse(defaults.bool(forKey: "healthAuthorizationRequested"))
        XCTAssertEqual(model.notice, "Health authorization failed.")
    }

    func testAutomaticBackgroundDeliveryFailureIsNonModalAndCanRecover() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")
        let health = MockHealthService()
        health.backgroundDeliveryError = StubError.backgroundDeliveryFailed
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )

        await model.start()

        XCTAssertEqual(health.observerConfigurationCount, 1)
        XCTAssertEqual(health.fetchCount, 1)
        XCTAssertEqual(model.healthBackgroundDeliveryFailure, "Background delivery failed.")
        XCTAssertNil(model.notice)
        XCTAssertEqual(model.healthStatus, "No readable samples · Background updates unavailable")

        health.backgroundDeliveryError = nil
        await model.refresh()

        XCTAssertEqual(health.observerConfigurationCount, 2)
        XCTAssertNil(model.healthBackgroundDeliveryFailure)
        XCTAssertNil(model.notice)
    }

    func testExplicitHealthConnectionSurfacesBackgroundDeliveryFailureAsNotice() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let health = MockHealthService()
        health.backgroundDeliveryError = StubError.backgroundDeliveryFailed
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )

        let connected = await model.connectHealth()

        XCTAssertTrue(connected)
        XCTAssertEqual(health.authorizationRequestCount, 1)
        XCTAssertEqual(health.observerConfigurationCount, 1)
        XCTAssertEqual(model.healthBackgroundDeliveryFailure, "Background delivery failed.")
        XCTAssertEqual(model.notice, "Background delivery failed.")
    }

    func testLaunchPreparationInstallsObserversWithoutWaitingForTheRootView() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")
        let health = MockHealthService()
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )

        await model.prepareHealthObservationAtLaunch()

        XCTAssertEqual(health.observerConfigurationCount, 1)
        XCTAssertEqual(health.fetchCount, 0)
    }

    func testLaunchPreparationFailureRemainsNonModal() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")
        let health = MockHealthService()
        health.backgroundDeliveryError = StubError.backgroundDeliveryFailed
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )

        await model.prepareHealthObservationAtLaunch()

        XCTAssertEqual(health.observerConfigurationCount, 1)
        XCTAssertEqual(health.fetchCount, 0)
        XCTAssertEqual(model.healthBackgroundDeliveryFailure, "Background delivery failed.")
        XCTAssertNil(model.notice)
        XCTAssertEqual(model.healthStatus, "Access requested · Background updates unavailable")
    }

    func testBackgroundUpdateRetriesWhenItsTriggeringMetricQueryFails() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")
        let health = MockHealthService()
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )
        await model.start()
        let failure = HealthQueryFailure(
            kind: .heartRateVariability,
            typeIdentifier: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
            message: "HRV query failed."
        )
        health.queryFailures = [failure]

        await health.emitBackgroundEvent(.dataChanged(
            kind: .heartRateVariability,
            typeIdentifier: failure.typeIdentifier
        ))

        XCTAssertEqual(health.fetchCount, 2)
        XCTAssertEqual(model.healthQueryFailures, [failure])
    }

    func testBackgroundUpdateAcknowledgesWhenOnlyAnotherMetricQueryFails() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")
        let health = MockHealthService()
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )
        await model.start()
        health.queryFailures = [HealthQueryFailure(
            kind: .heartRateVariability,
            typeIdentifier: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
            message: "HRV query failed."
        )]

        await health.emitBackgroundEvent(.dataChanged(
            kind: .sleep,
            typeIdentifier: "HKCategoryTypeIdentifierSleepAnalysis"
        ))

        XCTAssertEqual(health.fetchCount, 2)
    }

    func testObserverRuntimeFailureDoesNotCreateAReconfigurationLoopAndRemainsRetryable() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")
        let health = MockHealthService()
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )
        await model.start()
        await health.emitBackgroundEvent(.observerFailed(
            kind: .sleep,
            typeIdentifier: "HKCategoryTypeIdentifierSleepAnalysis",
            message: "Observer failed."
        ))
        await health.emitBackgroundEvent(.observerFailed(
            kind: .sleep,
            typeIdentifier: "HKCategoryTypeIdentifierSleepAnalysis",
            message: "Observer failed again."
        ))

        XCTAssertEqual(health.observerConfigurationCount, 1)
        XCTAssertNotNil(model.healthBackgroundDeliveryFailure)
        XCTAssertNil(model.notice)

        await model.refresh()

        XCTAssertEqual(health.observerConfigurationCount, 2)
        XCTAssertNil(model.healthBackgroundDeliveryFailure)
    }

    func testFailedWorkoutExportKeepsLocalRecordAndRetryUsesNextSyncVersion() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let health = MockHealthService()
        health.workoutSaveError = StubError.workoutExportFailed
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )
        let container = try workoutModelContainer()
        let context = ModelContext(container)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
        let session = workoutSession(id: id)
        context.insert(session)
        try context.save()

        await model.recordStrengthWorkout(session, in: context)

        XCTAssertEqual(session.healthExportState, .failed)
        XCTAssertEqual(session.healthExportSyncVersion, 1)
        XCTAssertEqual(session.healthExportErrorMessage, "Workout export failed.")
        XCTAssertEqual(health.workoutSaveRequests.map(\.sessionID), [id])
        XCTAssertEqual(health.workoutSaveRequests.map(\.syncVersion), [1])
        XCTAssertEqual(health.workoutSaveRequests.first?.start, session.startedAt)
        XCTAssertEqual(health.workoutSaveRequests.first?.end, session.endedAt)

        let afterFailureContext = ModelContext(container)
        let afterFailure = try XCTUnwrap(try afterFailureContext.fetch(FetchDescriptor<WorkoutSessionRecord>()).first)
        XCTAssertEqual(afterFailure.id, id)
        XCTAssertEqual(afterFailure.healthExportState, .failed)
        XCTAssertEqual(afterFailure.healthExportSyncVersion, 1)

        health.workoutSaveError = nil
        await model.retryStrengthWorkoutExport(session, in: context)

        XCTAssertEqual(session.healthExportState, .exported)
        XCTAssertEqual(session.healthExportSyncVersion, 2)
        XCTAssertNil(session.healthExportErrorMessage)
        XCTAssertEqual(health.workoutSaveRequests.map(\.sessionID), [id, id])
        XCTAssertEqual(health.workoutSaveRequests.map(\.syncVersion), [1, 2])

        let afterRetryContext = ModelContext(container)
        let records = try afterRetryContext.fetch(FetchDescriptor<WorkoutSessionRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.healthExportState, .exported)
        XCTAssertEqual(records.first?.healthExportSyncVersion, 2)
    }

    func testPendingCrashRetryAdvancesPersistedSyncVersionAndExportedRetryIsNoOp() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let health = MockHealthService()
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )
        let container = try workoutModelContainer()
        let context = ModelContext(container)
        let session = workoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!,
            healthExportSyncVersion: 7
        )
        context.insert(session)
        try context.save()

        await model.retryStrengthWorkoutExport(session, in: context)

        XCTAssertEqual(health.workoutSaveRequests.map(\.syncVersion), [8])
        XCTAssertEqual(session.healthExportState, .exported)
        XCTAssertEqual(session.healthExportSyncVersion, 8)

        await model.retryStrengthWorkoutExport(session, in: context)

        XCTAssertEqual(health.workoutSaveRequests.map(\.syncVersion), [8])

        let legacy = WorkoutSessionRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000045")!,
            templateID: nil,
            templateName: "Legacy workout",
            startedAt: Date(timeIntervalSince1970: 5_000),
            endedAt: Date(timeIntervalSince1970: 8_600),
            readiness: .moderate,
            readinessScore: 65,
            sets: [],
            healthExportState: .unknown
        )
        context.insert(legacy)
        try context.save()

        await model.retryStrengthWorkoutExport(legacy, in: context)

        XCTAssertEqual(legacy.healthExportState, .unknown)
        XCTAssertEqual(health.workoutSaveRequests.map(\.syncVersion), [8])
    }

    func testOverlappingWorkoutExportsAreCoalescedWithoutAdvancingVersion() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let health = MockHealthService()
        health.suspendNextWorkoutSave = true
        let saveStarted = expectation(description: "The first workout export reached HealthKit")
        health.onWorkoutSaveStarted = { saveStarted.fulfill() }
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )
        let container = try workoutModelContainer()
        let context = ModelContext(container)
        let session = workoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000044")!
        )
        context.insert(session)
        try context.save()

        let initialExport = Task {
            await model.recordStrengthWorkout(session, in: context)
        }
        await fulfillment(of: [saveStarted], timeout: 2)

        XCTAssertTrue(model.isExportingWorkout(session.id))
        await model.retryStrengthWorkoutExport(session, in: context)
        XCTAssertEqual(health.workoutSaveRequests.count, 1)
        XCTAssertEqual(session.healthExportSyncVersion, 1)

        health.resumeWorkoutSave()
        await initialExport.value

        XCTAssertFalse(model.isExportingWorkout(session.id))
        XCTAssertEqual(session.healthExportState, .exported)
        XCTAssertEqual(health.workoutSaveRequests.count, 1)
    }

    func testForegroundRefreshReloadsHealthCalendarAndPlan() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")

        let health = MockHealthService()
        let calendar = MockCalendarService()
        let alarms = MockAlarmService()
        calendar.commitment = commitment(id: "initial", hour: 9)
        let model = AppModel(
            health: health,
            calendar: calendar,
            alarms: alarms,
            defaults: defaults
        )
        XCTAssertEqual(model.healthConnectionState, .accessRequested)

        await model.start()
        XCTAssertEqual(health.fetchCount, 1)
        XCTAssertEqual(calendar.commitmentQueryCount, 1)
        XCTAssertEqual(model.plan.firstCommitment?.id, "initial")
        XCTAssertEqual(model.healthConnectionState, .noReadableSamples)

        health.samples = [recentSleepSample()]
        calendar.commitment = commitment(id: "updated", hour: 10)

        await model.refreshForForeground()

        XCTAssertEqual(health.fetchCount, 2)
        XCTAssertEqual(calendar.commitmentQueryCount, 2)
        XCTAssertTrue(model.snapshot.readinessAvailable)
        XCTAssertEqual(model.snapshot.latestSleep?.sourceName, "Eight Sleep")
        XCTAssertEqual(model.plan.firstCommitment?.id, "updated")
        XCTAssertEqual(model.healthConnectionState, .dataReceived(sampleCount: 1))
        XCTAssertEqual(model.healthStatus, "Data received · 1 samples")
    }

    func testCalendarSelectionsSeparatePlanningDetailsAndBusyDestinations() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.calendarSources = calendarSourcesFixture()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: MockAlarmService(),
            defaults: defaults,
            demoMode: true
        )

        XCTAssertNil(model.calendarPreferences.planningCalendarIdentifiers)
        XCTAssertEqual(model.calendarPreferences.detailedCalendarIdentifier, "personal")
        XCTAssertTrue(model.calendarPreferences.busyCalendarIdentifiers.isEmpty)

        model.setCalendar("work", includedInPlanning: false)
        model.setCalendar("work", sharesBusy: true)
        await model.refresh()

        XCTAssertEqual(calendar.lastPlanningCalendarIdentifiers, ["personal"])
        let request = model.planApplicationRequest()
        XCTAssertEqual(request.calendarDestinations?.detailedCalendarIdentifier, "personal")
        XCTAssertEqual(request.calendarDestinations?.busyCalendarIdentifiers, ["work"])
        XCTAssertEqual(request.calendarDestinations?.requestedCount, 2)
        XCTAssertEqual(
            model.calendarApplicationSummary(for: request.calendarDestinations!),
            "add Workout with readiness and confidence details to Personal and block Work as Busy"
        )
    }

    func testLoadedCalendarPreferencesRemoveDetailedBusyOverlap() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let privateState = MockPrivateAppStateStore()
        let saved = CalendarSelectionPreferences(
            planningCalendarIdentifiers: nil,
            detailedCalendarIdentifier: "personal",
            busyCalendarIdentifiers: ["personal", "work"],
            hasInitializedDetailedCalendar: true
        )
        XCTAssertTrue(privateState.set(
            try JSONEncoder().encode(saved),
            forKey: "calendarPreferences"
        ))
        let calendar = MockCalendarService()
        calendar.calendarSources = calendarSourcesFixture()

        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: MockAlarmService(),
            defaults: defaults,
            privateStateStore: privateState,
            demoMode: true
        )

        XCTAssertEqual(model.calendarPreferences.detailedCalendarIdentifier, "personal")
        XCTAssertEqual(model.calendarPreferences.busyCalendarIdentifiers, ["work"])
        let normalizedData = try XCTUnwrap(privateState.data(forKey: "calendarPreferences"))
        let normalized = try JSONDecoder().decode(
            CalendarSelectionPreferences.self,
            from: normalizedData
        )
        XCTAssertEqual(normalized.busyCalendarIdentifiers, ["work"])
    }

    func testCalendarSummaryDisambiguatesDuplicateTitlesByAccount() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.calendarSources = [
            CalendarSourceDescriptor(
                id: "icloud",
                title: "iCloud",
                calendars: [CalendarDescriptor(
                    id: "personal",
                    title: "Calendar",
                    sourceIdentifier: "icloud",
                    sourceTitle: "iCloud",
                    allowsContentModifications: true,
                    isDefault: true,
                    supportsBusyAvailability: true
                )]
            ),
            CalendarSourceDescriptor(
                id: "exchange",
                title: "Work Account",
                calendars: [CalendarDescriptor(
                    id: "work",
                    title: "Calendar",
                    sourceIdentifier: "exchange",
                    sourceTitle: "Work Account",
                    allowsContentModifications: true,
                    isDefault: false,
                    supportsBusyAvailability: true
                )]
            )
        ]
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: MockAlarmService(),
            defaults: defaults,
            demoMode: true
        )
        model.setCalendar("work", sharesBusy: true)

        XCTAssertEqual(
            model.calendarApplicationSummary(for: model.writableCalendarEventDestinations),
            "add Workout with readiness and confidence details to Calendar (iCloud) and block Calendar (Work Account) as Busy"
        )
    }

    func testCalendarSetupRoleSummariesExposeSelectionsWithoutExpandingSources() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.calendarSources = calendarSourcesFixture()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: MockAlarmService(),
            defaults: defaults,
            demoMode: true
        )
        await model.refresh()

        XCTAssertEqual(model.planningCalendarSelectionSummary, "All visible calendars")
        XCTAssertEqual(model.detailedCalendarSelectionSummary, "Personal")
        XCTAssertEqual(model.busyCalendarSelectionSummary, "No Busy calendars")

        model.setCalendar("work", sharesBusy: true)
        XCTAssertEqual(model.busyCalendarSelectionSummary, "Work")
    }

    func testUnavailablePlanningSelectionCanBeRemovedWithoutFallingBackSilently() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.calendarSources = calendarSourcesFixture()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: MockAlarmService(),
            defaults: defaults,
            demoMode: true
        )
        model.setCalendar("personal", includedInPlanning: false)
        calendar.calendarSources = calendarSourcesFixture(includesWork: false)
        await model.refresh()

        XCTAssertEqual(model.unavailablePlanningCalendarIdentifiers, ["work"])
        XCTAssertEqual(calendar.lastPlanningCalendarIdentifiers, ["work"])

        model.setCalendar("work", includedInPlanning: false)
        XCTAssertTrue(model.unavailablePlanningCalendarIdentifiers.isEmpty)
        XCTAssertEqual(model.calendarPreferences.planningCalendarIdentifiers, [])
    }

    func testBusyOnlyWritableSelectionIsCountedAsBusyNotWorkout() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.calendarSources = [CalendarSourceDescriptor(
            id: "account",
            title: "Account",
            calendars: [
                CalendarDescriptor(
                    id: "readonly-default",
                    title: "Default",
                    sourceIdentifier: "account",
                    sourceTitle: "Account",
                    allowsContentModifications: false,
                    isDefault: true,
                    supportsBusyAvailability: true
                ),
                CalendarDescriptor(
                    id: "work",
                    title: "Work",
                    sourceIdentifier: "account",
                    sourceTitle: "Account",
                    allowsContentModifications: true,
                    isDefault: false,
                    supportsBusyAvailability: true
                )
            ]
        )]
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: MockAlarmService(),
            defaults: defaults,
            demoMode: true
        )
        model.setCalendar("work", sharesBusy: true)

        let request = model.planApplicationRequest()
        XCTAssertTrue(request.includesCalendarEvent)
        XCTAssertNil(request.calendarDestinations?.detailedCalendarIdentifier)
        XCTAssertEqual(request.calendarDestinations?.busyCalendarIdentifiers, ["work"])
        XCTAssertEqual(request.calendarDestinations?.requestedCount, 1)
        XCTAssertEqual(
            model.calendarApplicationSummary(for: request.calendarDestinations!),
            "block Work as Busy"
        )
    }

    func testEventStoreChangeRefetchesDescriptorsWithoutReplacingStaleDestination() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.calendarSources = calendarSourcesFixture()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: MockAlarmService(),
            defaults: defaults,
            demoMode: true
        )
        model.selectDetailedCalendar("work")

        let sourcesRefetched = expectation(description: "Calendar descriptors refetched")
        calendar.onCalendarSourcesRequested = {
            if calendar.calendarSourceRequestCount == 2 {
                sourcesRefetched.fulfill()
            }
        }
        calendar.calendarSources = calendarSourcesFixture(includesWork: false)
        calendar.emitEventStoreChange()
        await fulfillment(of: [sourcesRefetched], timeout: 2)
        await Task.yield()

        XCTAssertEqual(model.calendarPreferences.detailedCalendarIdentifier, "work")
        XCTAssertTrue(model.selectedDetailedCalendarIsUnavailable)
        XCTAssertEqual(model.calendarEventDestinations.detailedCalendarIdentifier, "work")
        XCTAssertNil(model.planApplicationRequest().calendarDestinations?.detailedCalendarIdentifier)
        XCTAssertFalse(model.planApplicationRequest().includesCalendarEvent)
        XCTAssertFalse(model.calendarDescriptors.contains { $0.id == "work" })
    }

    func testCalendarReadFailureIsSurfacedAndFallbackIsExplicit() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.commitmentError = StubError.calendarReadFailed
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: MockAlarmService(),
            defaults: defaults,
            demoMode: true
        )

        await model.start()

        XCTAssertEqual(model.calendarReadFailure, "Calendar read failed.")
        XCTAssertNil(model.plan.firstCommitment)
        XCTAssertTrue(model.plan.warnings.contains {
            $0.hasPrefix("No calendar commitment was found")
        })

        calendar.commitmentError = nil
        calendar.commitment = commitment(id: "recovered", hour: 9)
        await model.refresh()

        XCTAssertNil(model.calendarReadFailure)
        XCTAssertEqual(model.plan.firstCommitment?.id, "recovered")
    }

    func testCalendarNotConnectedUsesFallbackWithoutReportingAReadFailure() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.authorizationLabel = "Not connected"
        calendar.commitmentError = CalendarError.accessRequired
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: MockAlarmService(),
            defaults: defaults
        )

        await model.start()

        XCTAssertNil(model.calendarReadFailure)
        XCTAssertNil(model.plan.firstCommitment)
        XCTAssertEqual(calendar.commitmentQueryCount, 1)
    }

    func testRefreshQueuesAnotherPassWhenTriggeredDuringAnActiveRefresh() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")
        let health = MockHealthService()
        health.suspendNextFetch = true
        let fetchStarted = expectation(description: "The first Health fetch started")
        health.onFetchStarted = { fetchStarted.fulfill() }
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )

        let firstRefresh = Task { await model.refresh() }
        await fulfillment(of: [fetchStarted], timeout: 2)
        XCTAssertTrue(model.isRefreshing)

        var secondRefreshReturned = false
        let secondRefreshStarted = expectation(description: "The second refresh reached AppModel")
        let secondRefresh = Task { @MainActor in
            secondRefreshStarted.fulfill()
            await model.refresh()
            secondRefreshReturned = true
        }
        await fulfillment(of: [secondRefreshStarted], timeout: 2)
        await Task.yield()

        XCTAssertEqual(health.fetchCount, 1)
        XCTAssertFalse(secondRefreshReturned)

        health.resumeFetch()
        await firstRefresh.value
        await secondRefresh.value

        XCTAssertEqual(health.fetchCount, 2)
        XCTAssertTrue(secondRefreshReturned)
        XCTAssertFalse(model.isRefreshing)
    }

    func testQueuedRefreshPreservesBackgroundDeliveryRetryIntent() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")
        let health = MockHealthService()
        health.backgroundDeliveryError = StubError.backgroundDeliveryFailed
        health.suspendNextFetch = true
        let fetchStarted = expectation(description: "The initial refresh reached HealthKit")
        health.onFetchStarted = { fetchStarted.fulfill() }
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )

        let initialRefresh = Task { @MainActor in await model.start() }
        await fulfillment(of: [fetchStarted], timeout: 2)
        XCTAssertEqual(health.observerConfigurationCount, 1)
        XCTAssertEqual(model.healthBackgroundDeliveryFailure, "Background delivery failed.")

        health.backgroundDeliveryError = nil
        var queuedRefreshReturned = false
        let queuedRefreshStarted = expectation(description: "The retrying refresh reached AppModel")
        let queuedRefresh = Task { @MainActor in
            queuedRefreshStarted.fulfill()
            await model.refresh()
            queuedRefreshReturned = true
        }
        await fulfillment(of: [queuedRefreshStarted], timeout: 2)
        await Task.yield()

        XCTAssertFalse(queuedRefreshReturned)
        XCTAssertEqual(health.fetchCount, 1)

        health.resumeFetch()
        await initialRefresh.value
        await queuedRefresh.value

        XCTAssertTrue(queuedRefreshReturned)
        XCTAssertEqual(health.fetchCount, 2)
        XCTAssertEqual(health.observerConfigurationCount, 2)
        XCTAssertNil(model.healthBackgroundDeliveryFailure)
        XCTAssertNil(model.notice)
        XCTAssertFalse(model.isRefreshing)
    }

    func testPartialHealthRefreshPublishesSuccessfulSamplesAndFailures() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")

        let health = MockHealthService()
        let failedHRV = HealthQueryFailure(
            kind: .heartRateVariability,
            typeIdentifier: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
            message: "Query interrupted"
        )
        health.samples = [recentSleepSample()]
        health.queryFailures = [failedHRV]
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )

        await model.start()

        XCTAssertEqual(model.healthConnectionState, .partialData(sampleCount: 1, failedQueryCount: 1))
        XCTAssertEqual(model.healthStatus, "Partial data · 1 samples")
        XCTAssertEqual(model.healthQueryFailures, [failedHRV])
        XCTAssertEqual(model.snapshot.samples.count, 1)
        XCTAssertTrue(model.snapshot.readinessAvailable)
        XCTAssertEqual(model.diagnostics.count, 1)
    }

    func testAutomaticHealthRefreshFailuresRemainNonModalAcrossLifecyclePaths() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")
        let failedSleep = HealthQueryFailure(
            kind: .sleep,
            typeIdentifier: "HKCategoryTypeIdentifierSleepAnalysis",
            message: "Store unavailable"
        )
        let health = MockHealthService()
        health.fetchError = HealthDataError.queryFailed([failedSleep])
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )

        await model.start()
        XCTAssertEqual(model.healthConnectionState, .refreshFailed)
        XCTAssertNil(model.notice)

        await model.refreshForForeground()
        XCTAssertEqual(model.healthConnectionState, .refreshFailed)
        XCTAssertNil(model.notice)

        await health.emitBackgroundEvent(.dataChanged(
            kind: .sleep,
            typeIdentifier: failedSleep.typeIdentifier
        ))
        XCTAssertEqual(health.fetchCount, 3)
        XCTAssertEqual(model.healthQueryFailures, [failedSleep])
        XCTAssertNil(model.notice)
    }

    func testExplicitHealthRefreshFailureSurfacesNotice() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")
        let failedSleep = HealthQueryFailure(
            kind: .sleep,
            typeIdentifier: "HKCategoryTypeIdentifierSleepAnalysis",
            message: "Store unavailable"
        )
        let health = MockHealthService()
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )
        await model.start()
        health.fetchError = HealthDataError.queryFailed([failedSleep])

        await model.refresh()

        XCTAssertEqual(model.healthConnectionState, .refreshFailed)
        XCTAssertEqual(model.notice, health.fetchError?.localizedDescription)
    }

    func testQueuedExplicitRefreshPreservesHealthFailureNoticeIntent() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")
        let failedSleep = HealthQueryFailure(
            kind: .sleep,
            typeIdentifier: "HKCategoryTypeIdentifierSleepAnalysis",
            message: "Store unavailable"
        )
        let health = MockHealthService()
        health.fetchError = HealthDataError.queryFailed([failedSleep])
        health.suspendNextFetch = true
        let fetchStarted = expectation(description: "Automatic startup refresh reached HealthKit")
        health.onFetchStarted = { fetchStarted.fulfill() }
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )

        let startup = Task { @MainActor in await model.start() }
        await fulfillment(of: [fetchStarted], timeout: 2)
        let explicitRefreshStarted = expectation(description: "Explicit refresh reached AppModel")
        let explicitRefresh = Task { @MainActor in
            explicitRefreshStarted.fulfill()
            await model.refresh()
        }
        await fulfillment(of: [explicitRefreshStarted], timeout: 2)
        await Task.yield()
        XCTAssertNil(model.notice)

        health.resumeFetch()
        await startup.value
        await explicitRefresh.value

        XCTAssertEqual(health.fetchCount, 2)
        XCTAssertEqual(model.notice, health.fetchError?.localizedDescription)
        XCTAssertFalse(model.isRefreshing)
    }

    func testFullHealthRefreshFailureClearsOldRecommendationAndCanRecover() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")

        let health = MockHealthService()
        health.samples = [recentSleepSample()]
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )

        await model.start()
        XCTAssertTrue(model.snapshot.readinessAvailable)

        let failedSleep = HealthQueryFailure(
            kind: .sleep,
            typeIdentifier: "HKCategoryTypeIdentifierSleepAnalysis",
            message: "Store unavailable"
        )
        health.fetchError = HealthDataError.queryFailed([failedSleep])
        await model.refresh()

        XCTAssertEqual(model.healthConnectionState, .refreshFailed)
        XCTAssertEqual(model.healthStatus, "Refresh failed")
        XCTAssertEqual(model.healthQueryFailures, [failedSleep])
        XCTAssertTrue(model.snapshot.samples.isEmpty)
        XCTAssertFalse(model.snapshot.readinessAvailable)
        XCTAssertTrue(model.diagnostics.isEmpty)
        XCTAssertEqual(model.plan.workoutAdjustment.title, "No adjustment yet")

        health.fetchError = nil
        health.samples = [recentSleepSample()]
        await model.refresh()

        XCTAssertEqual(model.healthConnectionState, .dataReceived(sampleCount: 1))
        XCTAssertTrue(model.snapshot.readinessAvailable)
        XCTAssertTrue(model.healthQueryFailures.isEmpty)
    }

    func testChangingSourcePreferencesRecomputesCurrentSnapshotWithoutAnotherFetch() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "healthAuthorizationRequested")

        let health = MockHealthService()
        health.samples = [
            recentSleepSample(),
            recentSleepSample(source: "Apple Watch", bundle: "com.apple.health.watch")
        ]
        let model = AppModel(
            health: health,
            calendar: MockCalendarService(),
            alarms: MockAlarmService(),
            defaults: defaults
        )

        var preferences = model.preferences
        let sleepIndex = try! XCTUnwrap(
            preferences.decisionMetricPreferences.firstIndex { $0.metric == .sleep }
        )
        preferences.decisionMetricPreferences[sleepIndex].sourceMode = .manual
        preferences.decisionMetricPreferences[sleepIndex].manualSourceBundleIdentifier = "com.eightsleep.app"
        preferences.decisionMetricPreferences[sleepIndex].allowAutomaticFallback = false
        model.preferences = preferences

        await model.start()
        XCTAssertEqual(model.snapshot.latestSleep?.sourceName, "Eight Sleep")
        XCTAssertEqual(health.fetchCount, 1)

        preferences = model.preferences
        preferences.decisionMetricPreferences[sleepIndex].sourceMode = .manual
        preferences.decisionMetricPreferences[sleepIndex].manualSourceBundleIdentifier = "com.apple.health.watch"
        preferences.decisionMetricPreferences[sleepIndex].allowAutomaticFallback = false
        model.preferences = preferences

        XCTAssertEqual(model.snapshot.latestSleep?.sourceName, "Apple Watch")
        XCTAssertEqual(health.fetchCount, 1)
    }

    func testApplyPlanIgnoresASecondRequestWhileTheFirstIsInFlight() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let health = MockHealthService()
        let calendar = MockCalendarService()
        calendar.suspendGymEventCreation = true
        let alarms = MockAlarmService()
        let model = AppModel(
            health: health,
            calendar: calendar,
            alarms: alarms,
            defaults: defaults,
            demoMode: true
        )
        let createStarted = expectation(description: "The first apply reached Calendar")
        calendar.onGymEventCreationStarted = { createStarted.fulfill() }

        let firstApply = Task { await model.applyPlan() }
        await fulfillment(of: [createStarted], timeout: 2)
        XCTAssertTrue(model.isApplying)
        XCTAssertNotNil(model.appliedPlanStatus)
        XCTAssertNotNil(defaults.data(forKey: "appliedPlanStatus"))
        XCTAssertTrue(model.appliedPlanVerificationMessage?.contains("in progress") == true)

        let overlappingApply = Task { await model.applyPlan() }
        await overlappingApply.value

        XCTAssertEqual(calendar.gymEventCreationCount, 1)
        XCTAssertEqual(alarms.scheduleCount, 0)

        calendar.resumeGymEventCreation()
        await firstApply.value

        XCTAssertEqual(calendar.gymEventCreationCount, 1)
        XCTAssertEqual(alarms.scheduleCount, 1)
        XCTAssertFalse(model.isApplying)
        XCTAssertNil(model.notice)
        XCTAssertEqual(model.appliedPlanStatus?.wakeAlarmApplied, true)
        XCTAssertEqual(model.appliedPlanStatus?.calendarEventApplied, true)
        XCTAssertTrue(calendar.lastGymNote?.contains("Created by Dayvera.") == true)
        XCTAssertTrue(calendar.lastGymNote?.contains("Readiness:") == true)
    }

    func testUndoCannotRaceAnInFlightPlanApplication() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        let alarms = MockAlarmService()
        alarms.suspendNextSchedule = true
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: alarms,
            defaults: defaults,
            demoMode: true
        )
        let alarmStarted = expectation(description: "Alarm scheduling suspended")
        alarms.onScheduleStarted = { alarmStarted.fulfill() }

        let apply = Task { await model.applyPlan() }
        await fulfillment(of: [alarmStarted], timeout: 2)

        await model.refreshForForeground()

        XCTAssertEqual(alarms.presenceCheckCount, 0)
        XCTAssertEqual(calendar.presenceCheckCount, 0)
        XCTAssertNotNil(model.appliedPlanStatus)
        XCTAssertNotNil(defaults.data(forKey: "appliedPlanStatus"))

        model.undoAppliedPlan()

        XCTAssertTrue(model.isApplying)
        XCTAssertEqual(calendar.gymEventCancellationCount, 0)
        XCTAssertEqual(alarms.cancelCount, 0)
        XCTAssertEqual(model.notice, "Wait for the current plan application to finish before undoing it.")
        XCTAssertNotNil(defaults.data(forKey: "appliedPlanStatus"))

        alarms.resumeSchedule()
        await apply.value

        XCTAssertFalse(model.isApplying)
        XCTAssertEqual(model.appliedPlanStatus?.wakeAlarmApplied, true)
        XCTAssertEqual(model.appliedPlanStatus?.calendarEventApplied, true)
    }

    func testApplyPlanReportsPartialSuccessWhenCalendarFailsButAlarmSucceeds() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.gymEventError = StubError.calendarWriteFailed
        let alarms = MockAlarmService()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: alarms,
            defaults: defaults,
            demoMode: true
        )

        await model.applyPlan()

        XCTAssertEqual(calendar.gymEventCreationCount, 1)
        XCTAssertEqual(alarms.scheduleCount, 1)
        XCTAssertFalse(model.isApplying)
        XCTAssertEqual(model.notice, "Applied wake alarm. Calendar: Calendar write failed.")
        XCTAssertEqual(model.appliedPlanStatus?.wakeAlarmApplied, true)
        XCTAssertEqual(model.appliedPlanStatus?.calendarEventApplied, false)
    }

    func testMultiCalendarApplyPersistsPartialSuccessByDestination() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.calendarSources = calendarSourcesFixture()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: MockAlarmService(),
            defaults: defaults,
            demoMode: true
        )
        model.setCalendar("work", sharesBusy: true)
        let personalReceipt = CalendarEventReceipt(
            eventIdentifier: "personal-event",
            calendarIdentifier: "personal",
            calendarTitle: "Personal",
            role: .detailed
        )
        calendar.nextWriteResult = CalendarEventWriteResult(
            activeReceipts: [personalReceipt],
            writtenReceipts: [personalReceipt],
            failures: [CalendarEventOperationFailure(
                calendarIdentifier: "work",
                calendarTitle: "Work",
                role: .busy,
                message: "This calendar is read-only. Choose a writable calendar in Settings."
            )]
        )

        await model.applyPlan()

        let status = try XCTUnwrap(model.appliedPlanStatus)
        XCTAssertTrue(status.wakeAlarmApplied)
        XCTAssertTrue(status.calendarEventApplied)
        XCTAssertEqual(status.calendarEventReceipts, [personalReceipt])
        XCTAssertEqual(status.requestedCalendarEventCount, 2)
        XCTAssertFalse(status.calendarEventsComplete)
        XCTAssertTrue(model.notice?.contains("Applied 1 of 2 calendar events and wake alarm") == true)
        XCTAssertTrue(model.notice?.contains("Work: This calendar is read-only") == true)
        XCTAssertTrue(calendar.lastGymNote?.contains("Readiness:") == true)
        XCTAssertTrue(calendar.lastGymNote?.contains("Data confidence:") == true)
    }

    func testMultiCalendarUndoKeepsOnlyDestinationThatFailedThenRetriesIt() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.calendarSources = calendarSourcesFixture()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: MockAlarmService(),
            defaults: defaults,
            demoMode: true
        )
        model.setCalendar("work", sharesBusy: true)
        await model.applyPlan()
        let applied = try XCTUnwrap(model.appliedPlanStatus)
        let detailed = try XCTUnwrap(applied.calendarEventReceipts.first { $0.role == .detailed })
        let busy = try XCTUnwrap(applied.calendarEventReceipts.first { $0.role == .busy })
        calendar.queuedUndoResults = [CalendarEventUndoResult(
            removedReceipts: [detailed],
            remainingReceipts: [busy],
            failures: [CalendarEventOperationFailure(
                calendarIdentifier: busy.calendarIdentifier,
                calendarTitle: busy.calendarTitle,
                role: .busy,
                message: "The calendar is read-only."
            )]
        )]

        model.undoAppliedPlan()

        XCTAssertEqual(model.appliedPlanStatus?.wakeAlarmApplied, false)
        XCTAssertEqual(model.appliedPlanStatus?.calendarEventReceipts, [busy])
        XCTAssertEqual(model.appliedPlanStatus?.calendarEventApplied, true)
        XCTAssertTrue(model.notice?.contains("Work: The calendar is read-only") == true)

        model.undoAppliedPlan()

        XCTAssertNil(model.appliedPlanStatus)
        XCTAssertNil(model.notice)
        XCTAssertEqual(calendar.gymEventCancellationCount, 2)
    }

    func testRemovingBusyPreferenceReconcilesOldReceiptAndRequestedCount() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.calendarSources = calendarSourcesFixture()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: MockAlarmService(),
            defaults: defaults,
            demoMode: true
        )
        model.setCalendar("work", sharesBusy: true)
        await model.applyPlan()
        let initiallyApplied = try XCTUnwrap(model.appliedPlanStatus)
        XCTAssertEqual(initiallyApplied.calendarEventReceipts.count, 2)
        XCTAssertEqual(model.appliedPlanStatus?.requestedCalendarEventCount, 2)

        model.setCalendar("work", sharesBusy: false)
        XCTAssertFalse(
            initiallyApplied.matches(
                calendarDestinations: model.writableCalendarEventDestinations
            )
        )
        await model.applyPlan()

        let replaced = try XCTUnwrap(model.appliedPlanStatus)
        XCTAssertEqual(replaced.calendarEventReceipts.map(\.calendarIdentifier), ["personal"])
        XCTAssertEqual(replaced.requestedCalendarEventCount, 1)
        XCTAssertTrue(replaced.calendarEventsComplete)
        XCTAssertNil(model.appliedPlanVerificationMessage)
    }

    func testReapplyIsBlockedWhenPriorCalendarEventHasNoWritableReplacement() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.calendarSources = calendarSourcesFixture()
        let alarms = MockAlarmService()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: alarms,
            defaults: defaults,
            demoMode: true
        )
        await model.applyPlan()
        let original = try XCTUnwrap(model.appliedPlanStatus)

        calendar.calendarSources = []
        await model.refresh()
        XCTAssertNotNil(model.calendarReapplyBlockingReason)

        await model.applyPlan()

        XCTAssertEqual(alarms.scheduleCount, 1)
        XCTAssertEqual(calendar.gymEventCreationCount, 1)
        XCTAssertEqual(model.appliedPlanStatus, original)
        XCTAssertTrue(model.notice?.contains("Undo the applied plan") == true)
    }

    func testReapplyIsBlockedWhenDetailedCalendarDisappearsButBusyTargetRemains() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.calendarSources = calendarSourcesFixture()
        let alarms = MockAlarmService()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: alarms,
            defaults: defaults,
            demoMode: true
        )
        model.setCalendar("work", sharesBusy: true)
        await model.applyPlan()
        XCTAssertNotNil(model.appliedPlanStatus?.calendarEventReceipts.first { $0.role == .detailed })

        calendar.calendarSources = calendarSourcesFixture().filter { $0.id == "exchange" }
        await model.refresh()
        let statusBeforeBlockedApply = try XCTUnwrap(model.appliedPlanStatus)
        XCTAssertNil(model.writableCalendarEventDestinations.detailedCalendarIdentifier)
        XCTAssertEqual(model.writableCalendarEventDestinations.busyCalendarIdentifiers, ["work"])
        XCTAssertTrue(model.planApplicationRequest().includesCalendarEvent)
        XCTAssertNotNil(model.calendarReapplyBlockingReason)

        await model.applyPlan()

        XCTAssertEqual(alarms.scheduleCount, 1)
        XCTAssertEqual(calendar.gymEventCreationCount, 1)
        XCTAssertEqual(model.appliedPlanStatus, statusBeforeBlockedApply)
        XCTAssertTrue(model.notice?.contains("Workout details") == true)
    }

    func testCalendarThrowTracksExpandedCurrentDestinationCount() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.calendarSources = calendarSourcesFixture()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: MockAlarmService(),
            defaults: defaults,
            demoMode: true
        )
        await model.applyPlan()
        model.setCalendar("work", sharesBusy: true)
        calendar.gymEventError = StubError.calendarWriteFailed

        await model.applyPlan()

        let status = try XCTUnwrap(model.appliedPlanStatus)
        XCTAssertEqual(status.requestedCalendarEventCount, 2)
        XCTAssertEqual(status.calendarEventDestinations?.requestedCount, 2)
        XCTAssertFalse(status.calendarEventsComplete)
        XCTAssertFalse(status.calendarEventIssues.isEmpty)
    }

    func testReconciliationAdoptsRefreshedCalendarReceiptIdentifier() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.calendarSources = calendarSourcesFixture()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: MockAlarmService(),
            defaults: defaults,
            demoMode: true
        )
        await model.applyPlan()
        let original = try XCTUnwrap(model.appliedPlanStatus?.calendarEventReceipts.first)
        let refreshed = CalendarEventReceipt(
            eventIdentifier: "synced-local-identifier",
            externalIdentifier: "stable-external-identifier",
            calendarIdentifier: original.calendarIdentifier,
            calendarTitle: original.calendarTitle,
            role: original.role,
            startDate: original.startDate,
            endDate: original.endDate
        )
        calendar.nextVerificationResult = CalendarEventVerificationResult(
            verifiedReceipts: [refreshed],
            missingReceipts: [],
            failures: []
        )

        await model.refresh()

        XCTAssertEqual(model.appliedPlanStatus?.calendarEventReceipts, [refreshed])
    }

    func testReconciliationRetainsAmbiguousReceiptAlongsideVerifiedReceipt() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.calendarSources = calendarSourcesFixture()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: MockAlarmService(),
            defaults: defaults,
            demoMode: true
        )
        model.setCalendar("work", sharesBusy: true)
        await model.applyPlan()
        let receipts = try XCTUnwrap(model.appliedPlanStatus?.calendarEventReceipts)
        let detailed = try XCTUnwrap(receipts.first { $0.role == .detailed })
        let busy = try XCTUnwrap(receipts.first { $0.role == .busy })
        calendar.nextVerificationResult = CalendarEventVerificationResult(
            verifiedReceipts: [detailed],
            missingReceipts: [],
            failures: [CalendarEventOperationFailure(
                calendarIdentifier: busy.calendarIdentifier,
                calendarTitle: busy.calendarTitle,
                role: .busy,
                message: "Ambiguous external identifier."
            )]
        )

        await model.refresh()

        XCTAssertEqual(Set(model.appliedPlanStatus?.calendarEventReceipts ?? []), Set(receipts))
        XCTAssertTrue(model.appliedPlanVerificationMessage?.contains("Ambiguous") == true)
    }

    func testFailedApplyKeepsConservativeUndoJournalUntilCleanupRuns() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.gymEventError = StubError.calendarWriteFailed
        let alarms = MockAlarmService()
        alarms.scheduleError = StubError.alarmWriteFailed
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: alarms,
            defaults: defaults,
            demoMode: true
        )

        await model.applyPlan()

        XCTAssertEqual(model.appliedPlanStatus?.wakeAlarmApplied, true)
        XCTAssertEqual(model.appliedPlanStatus?.calendarEventApplied, true)
        XCTAssertNotNil(defaults.data(forKey: "appliedPlanStatus"))
        XCTAssertTrue(model.appliedPlanVerificationMessage?.contains("could not confirm") == true)

        model.undoAppliedPlan()

        XCTAssertEqual(calendar.gymEventCancellationCount, 1)
        XCTAssertEqual(alarms.cancelCount, 1)
        XCTAssertNil(model.appliedPlanStatus)
        XCTAssertNil(defaults.data(forKey: "appliedPlanStatus"))
    }

    func testPostScheduleInspectionFailureKeepsAlarmVisibleForVerificationAndUndo() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let alarms = MockAlarmService()
        alarms.scheduleError = AlarmServiceError.postScheduleInspectionFailed("Inspection failed.")
        let model = AppModel(
            health: MockHealthService(),
            calendar: MockCalendarService(),
            alarms: alarms,
            defaults: defaults,
            demoMode: true
        )

        await model.applyPlan()

        XCTAssertEqual(model.appliedPlanStatus?.wakeAlarmApplied, true)
        XCTAssertEqual(model.appliedPlanStatus?.calendarEventApplied, true)
        XCTAssertTrue(model.appliedPlanVerificationMessage?.contains("could not verify") == true)
        XCTAssertNotNil(defaults.data(forKey: "appliedPlanStatus"))

        model.undoAppliedPlan()

        XCTAssertEqual(alarms.cancelCount, 1)
        XCTAssertNil(model.appliedPlanStatus)
    }

    func testAmbiguousAlarmFailurePromotesPriorCalendarOnlyJournal() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        let alarms = MockAlarmService()
        alarms.scheduleError = StubError.alarmWriteFailed
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: alarms,
            defaults: defaults,
            demoMode: true
        )

        await model.applyPlan()
        XCTAssertEqual(model.appliedPlanStatus?.wakeAlarmApplied, false)
        XCTAssertEqual(model.appliedPlanStatus?.calendarEventApplied, true)

        calendar.gymEventError = StubError.calendarWriteFailed
        alarms.scheduleError = AlarmServiceError.postScheduleInspectionFailed("Inspection failed.")
        await model.applyPlan()

        XCTAssertEqual(model.appliedPlanStatus?.wakeAlarmApplied, true)
        XCTAssertEqual(model.appliedPlanStatus?.calendarEventApplied, true)
        XCTAssertTrue(model.appliedPlanVerificationMessage?.contains("wake alarm") == true)
        XCTAssertNotNil(defaults.data(forKey: "appliedPlanStatus"))
    }

    func testPartialReplacementFailurePreservesPriorAlarmTrackingAndUndoPath() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        let alarms = MockAlarmService()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: alarms,
            defaults: defaults,
            demoMode: true
        )
        let originalRequest = model.planApplicationRequest()

        await model.applyPlan(originalRequest)

        let replacementRequest = PlanApplicationRequest(
            wakeTime: originalRequest.wakeTime.addingTimeInterval(30 * 60),
            gymStart: originalRequest.gymStart.addingTimeInterval(30 * 60),
            gymEnd: originalRequest.gymEnd.addingTimeInterval(30 * 60),
            workoutTitle: originalRequest.workoutTitle,
            readinessScore: originalRequest.readinessScore,
            confidence: originalRequest.confidence,
            includesCalendarEvent: true
        )
        alarms.scheduleError = StubError.alarmWriteFailed

        await model.applyPlan(replacementRequest)

        let replacementStatus = try! XCTUnwrap(model.appliedPlanStatus)
        XCTAssertEqual(replacementStatus.wakeTime, replacementRequest.wakeTime)
        XCTAssertTrue(replacementStatus.wakeAlarmApplied)
        XCTAssertTrue(replacementStatus.calendarEventApplied)
        XCTAssertEqual(alarms.persistedWakeDate, originalRequest.wakeTime)
        XCTAssertEqual(model.notice, "Applied gym event. Alarm: Alarm write failed.")
        XCTAssertTrue(model.appliedPlanVerificationMessage?.contains("previously applied wake alarm may still be active") == true)
        XCTAssertTrue(model.appliedPlanVerificationMessage?.contains("Use Undo") == true)
        XCTAssertNotNil(defaults.data(forKey: "appliedPlanStatus"))

        await model.refreshForForeground()
        let mismatchWarning = try! XCTUnwrap(model.appliedPlanVerificationMessage)
        XCTAssertTrue(mismatchWarning.contains("wake alarm doesn’t match this plan"))

        await model.refreshForForeground()

        XCTAssertEqual(model.appliedPlanVerificationMessage, mismatchWarning)
        XCTAssertEqual(model.appliedPlanStatus, replacementStatus)

        model.undoAppliedPlan()

        XCTAssertNil(model.appliedPlanStatus)
        XCTAssertNil(model.appliedPlanVerificationMessage)
        XCTAssertNil(defaults.data(forKey: "appliedPlanStatus"))
        XCTAssertEqual(alarms.cancelCount, 1)
        XCTAssertEqual(calendar.gymEventCancellationCount, 1)
    }

    func testApplyUsesTheConfirmedPlanSnapshotWhenLivePreferencesChange() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        calendar.suspendGymEventCreation = true
        let alarms = MockAlarmService()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: alarms,
            defaults: defaults,
            demoMode: true
        )
        let request = model.planApplicationRequest()
        let createStarted = expectation(description: "Plan application reached Calendar")
        calendar.onGymEventCreationStarted = { createStarted.fulfill() }

        let apply = Task { await model.applyPlan(request) }
        await fulfillment(of: [createStarted], timeout: 2)

        model.preferences.gymDurationMinutes += 30
        XCTAssertNotEqual(model.plan.gymStart, request.gymStart)

        calendar.resumeGymEventCreation()
        await apply.value

        XCTAssertEqual(calendar.lastGymStart, request.gymStart)
        XCTAssertEqual(calendar.lastGymEnd, request.gymEnd)
        XCTAssertEqual(alarms.lastScheduledDate, request.wakeTime)
    }

    func testAppliedPlanPersistsAndUndoCancelsOwnedItems() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        let alarms = MockAlarmService()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: alarms,
            defaults: defaults,
            demoMode: true
        )

        await model.applyPlan()
        let applied = try! XCTUnwrap(model.appliedPlanStatus)

        let restoredCalendar = MockCalendarService()
        let restoredAlarms = MockAlarmService()
        let restored = AppModel(
            health: MockHealthService(),
            calendar: restoredCalendar,
            alarms: restoredAlarms,
            defaults: defaults,
            demoMode: true
        )
        XCTAssertEqual(restored.appliedPlanStatus, applied)

        restored.undoAppliedPlan()

        XCTAssertNil(restored.appliedPlanStatus)
        XCTAssertEqual(restoredCalendar.gymEventCancellationCount, 1)
        XCTAssertEqual(restoredAlarms.cancelCount, 1)
    }

    func testPartialUndoPersistsOnlyTheItemThatCouldNotBeRemoved() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        let alarms = MockAlarmService()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: alarms,
            defaults: defaults,
            demoMode: true
        )
        await model.applyPlan()
        calendar.cancelError = StubError.calendarWriteFailed

        model.undoAppliedPlan()

        XCTAssertEqual(model.appliedPlanStatus?.wakeAlarmApplied, false)
        XCTAssertEqual(model.appliedPlanStatus?.calendarEventApplied, true)
        XCTAssertNotNil(defaults.data(forKey: "appliedPlanStatus"))
        XCTAssertTrue(model.appliedPlanVerificationMessage?.contains("could not be removed") == true)

        calendar.cancelError = nil
        model.undoAppliedPlan()

        XCTAssertNil(model.appliedPlanStatus)
        XCTAssertNil(defaults.data(forKey: "appliedPlanStatus"))
    }

    func testReconciliationMismatchPreservesAppliedStateAcrossRefreshesAndUndoCleansUp() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = MockCalendarService()
        let alarms = MockAlarmService()
        let model = AppModel(
            health: MockHealthService(),
            calendar: calendar,
            alarms: alarms,
            defaults: defaults,
            demoMode: true
        )

        await model.applyPlan()
        let applied = try! XCTUnwrap(model.appliedPlanStatus)
        XCTAssertTrue(applied.wakeAlarmApplied)
        XCTAssertTrue(applied.calendarEventApplied)

        alarms.wakeAlarmPresent = false
        await model.refreshForForeground()

        XCTAssertEqual(model.appliedPlanStatus, applied)
        XCTAssertNotNil(defaults.data(forKey: "appliedPlanStatus"))
        XCTAssertTrue(model.appliedPlanVerificationMessage?.contains("wake alarm doesn’t match this plan") == true)
        XCTAssertEqual(alarms.presenceCheckCount, 1)
        XCTAssertEqual(calendar.presenceCheckCount, 1)

        calendar.gymEventPresent = false
        await model.refreshForForeground()

        let combinedWarning = try! XCTUnwrap(model.appliedPlanVerificationMessage)
        XCTAssertEqual(model.appliedPlanStatus, applied)
        XCTAssertNotNil(defaults.data(forKey: "appliedPlanStatus"))
        XCTAssertTrue(combinedWarning.contains("wake alarm doesn’t match this plan"))
        XCTAssertTrue(combinedWarning.contains("gym event doesn’t match this plan"))

        await model.refreshForForeground()

        XCTAssertEqual(model.appliedPlanStatus, applied)
        XCTAssertEqual(model.appliedPlanVerificationMessage, combinedWarning)
        XCTAssertEqual(alarms.presenceCheckCount, 3)
        XCTAssertEqual(calendar.presenceCheckCount, 3)

        model.undoAppliedPlan()

        XCTAssertNil(model.appliedPlanStatus)
        XCTAssertNil(model.appliedPlanVerificationMessage)
        XCTAssertNil(defaults.data(forKey: "appliedPlanStatus"))
        XCTAssertEqual(alarms.cancelCount, 1)
        XCTAssertEqual(calendar.gymEventCancellationCount, 1)
    }

    func testReconciliationErrorKeepsLastKnownAppliedStateButMarksItUnverified() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let alarms = MockAlarmService()
        let model = AppModel(
            health: MockHealthService(),
            calendar: MockCalendarService(),
            alarms: alarms,
            defaults: defaults,
            demoMode: true
        )
        await model.applyPlan()
        alarms.presenceError = StubError.alarmReadFailed

        await model.refreshForForeground()

        XCTAssertEqual(model.appliedPlanStatus?.wakeAlarmApplied, true)
        XCTAssertEqual(model.appliedPlanStatus?.calendarEventApplied, true)
        XCTAssertTrue(model.appliedPlanVerificationMessage?.contains("couldn’t verify the saved wake alarm") == true)
    }

    private func calendarSourcesFixture(
        includesWork: Bool = true,
        workIsWritable: Bool = true
    ) -> [CalendarSourceDescriptor] {
        let personal = CalendarDescriptor(
            id: "personal",
            title: "Personal",
            sourceIdentifier: "icloud",
            sourceTitle: "iCloud",
            allowsContentModifications: true,
            isDefault: true,
            supportsBusyAvailability: true
        )
        let work = CalendarDescriptor(
            id: "work",
            title: "Work",
            sourceIdentifier: "exchange",
            sourceTitle: "Exchange",
            allowsContentModifications: workIsWritable,
            isDefault: false,
            supportsBusyAvailability: true
        )
        var sources = [
            CalendarSourceDescriptor(id: "icloud", title: "iCloud", calendars: [personal])
        ]
        if includesWork {
            sources.append(
                CalendarSourceDescriptor(id: "exchange", title: "Exchange", calendars: [work])
            )
        }
        return sources
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "app.dayvera.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func workoutModelContainer() throws -> ModelContainer {
        try ModelContainer(
            for: WorkoutSessionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func workoutSession(
        id: UUID,
        healthExportSyncVersion: Int = 1
    ) -> WorkoutSessionRecord {
        WorkoutSessionRecord(
            id: id,
            templateID: nil,
            templateName: "Reliability workout",
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 4_600),
            readiness: .moderate,
            readinessScore: 65,
            sets: [],
            healthExportSyncVersion: healthExportSyncVersion
        )
    }

    private func recentSleepSample(
        source: String = "Eight Sleep",
        bundle: String = "com.eightsleep.app"
    ) -> MetricSample {
        let end = Date.now.addingTimeInterval(-60 * 60)
        return MetricSample(
            kind: .sleep,
            startDate: end.addingTimeInterval(-8 * 60 * 60),
            endDate: end,
            sleepStage: .asleep,
            sourceName: source,
            sourceBundleIdentifier: bundle
        )
    }

    private func commitment(id: String, hour: Int) -> CalendarCommitment {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow)!
        return CalendarCommitment(
            id: id,
            title: "Commitment \(id)",
            startDate: start,
            endDate: start.addingTimeInterval(60 * 60),
            location: nil
        )
    }
}

private final class MockHealthService: HealthDataProviding {
    struct WorkoutSaveRequest: Equatable {
        let sessionID: UUID
        let syncVersion: Int
        let start: Date
        let end: Date
    }

    var isAvailable = true
    var authorizationRequestSchema = HealthAuthorizationRequestSchema(
        version: 0,
        readTypeIdentifiers: []
    )
    var accessRequestStatus = HealthAccessRequestStatus.unknown
    var samples: [MetricSample] = []
    var queryFailures: [HealthQueryFailure] = []
    var authorizationError: Error?
    var fetchError: Error?
    var backgroundDeliveryError: Error?
    var workoutSaveError: Error?
    var suspendNextFetch = false
    var suspendNextWorkoutSave = false
    var onFetchStarted: (() -> Void)?
    var onWorkoutSaveStarted: (() -> Void)?
    private(set) var authorizationRequestCount = 0
    private(set) var authorizationStatusRequestCount = 0
    private(set) var fetchCount = 0
    private(set) var observerConfigurationCount = 0
    private(set) var savedWorkoutCount = 0
    private(set) var workoutSaveRequests: [WorkoutSaveRequest] = []
    private var fetchContinuation: CheckedContinuation<Void, Never>?
    private var workoutSaveContinuation: CheckedContinuation<Void, Never>?
    private var backgroundUpdateHandler: (
        @MainActor @Sendable (HealthBackgroundEvent) async -> Void
    )?

    func requestAuthorization() async throws {
        authorizationRequestCount += 1
        if let authorizationError { throw authorizationError }
    }

    func authorizationRequestStatus() async throws -> HealthAccessRequestStatus {
        authorizationStatusRequestCount += 1
        return accessRequestStatus
    }

    func fetchSamples(since startDate: Date, through endDate: Date) async throws -> HealthSampleFetchResult {
        fetchCount += 1
        if suspendNextFetch {
            suspendNextFetch = false
            await withCheckedContinuation { continuation in
                fetchContinuation = continuation
                onFetchStarted?()
            }
        }
        if let fetchError { throw fetchError }
        return HealthSampleFetchResult(samples: samples, queryFailures: queryFailures)
    }

    func saveStrengthWorkout(
        sessionID: UUID,
        syncVersion: Int,
        start: Date,
        end: Date
    ) async throws {
        savedWorkoutCount += 1
        workoutSaveRequests.append(.init(
            sessionID: sessionID,
            syncVersion: syncVersion,
            start: start,
            end: end
        ))
        if suspendNextWorkoutSave {
            suspendNextWorkoutSave = false
            await withCheckedContinuation { continuation in
                workoutSaveContinuation = continuation
                onWorkoutSaveStarted?()
            }
        }
        if let workoutSaveError { throw workoutSaveError }
    }

    @MainActor
    func configureBackgroundDelivery(
        onUpdate: @escaping @MainActor @Sendable (HealthBackgroundEvent) async -> Void
    ) async throws {
        observerConfigurationCount += 1
        if let backgroundDeliveryError { throw backgroundDeliveryError }
        backgroundUpdateHandler = onUpdate
    }

    @MainActor
    func emitBackgroundEvent(_ event: HealthBackgroundEvent) async {
        await backgroundUpdateHandler?(event)
    }

    func resumeFetch() {
        fetchContinuation?.resume()
        fetchContinuation = nil
    }

    func resumeWorkoutSave() {
        workoutSaveContinuation?.resume()
        workoutSaveContinuation = nil
    }
}

private final class MockCalendarService: CalendarProviding {
    var authorizationLabel = "Connected"
    var calendarSources: [CalendarSourceDescriptor] = [.legacyDefault]
    var commitment: CalendarCommitment?
    var commitmentError: Error?
    var accessGranted = true
    var gymEventError: Error?
    var cancelError: Error?
    var presenceError: Error?
    var gymEventPresent = true
    var nextWriteResult: CalendarEventWriteResult?
    var nextVerificationResult: CalendarEventVerificationResult?
    var queuedUndoResults: [CalendarEventUndoResult] = []
    var suspendGymEventCreation = false
    var onGymEventCreationStarted: (() -> Void)?
    var onCalendarSourcesRequested: (() -> Void)?
    private(set) var accessRequestCount = 0
    private(set) var calendarSourceRequestCount = 0
    private(set) var commitmentQueryCount = 0
    private(set) var gymEventCreationCount = 0
    private(set) var gymEventCancellationCount = 0
    private(set) var presenceCheckCount = 0
    private(set) var lastPlanningCalendarIdentifiers: Set<String>?
    private(set) var lastWriteRequest: CalendarEventWriteRequest?
    private(set) var lastGymStart: Date?
    private(set) var lastGymEnd: Date?
    private(set) var lastGymNote: String?
    private var activeReceipts: [CalendarEventReceipt] = []
    private var eventStoreChangeHandler: (() -> Void)?
    private var gymEventContinuation: CheckedContinuation<Void, Never>?

    func requestAccess() async throws -> Bool {
        accessRequestCount += 1
        return accessGranted
    }

    func firstCommitment(on date: Date) async throws -> CalendarCommitment? {
        commitmentQueryCount += 1
        if let commitmentError { throw commitmentError }
        return commitment
    }

    func availableCalendarSources() throws -> [CalendarSourceDescriptor] {
        calendarSourceRequestCount += 1
        onCalendarSourcesRequested?()
        return calendarSources
    }

    func firstCommitment(
        on date: Date,
        calendarIdentifiers: Set<String>?
    ) async throws -> CalendarCommitment? {
        commitmentQueryCount += 1
        lastPlanningCalendarIdentifiers = calendarIdentifiers
        if let commitmentError { throw commitmentError }
        return commitment
    }

    func createGymEvent(start: Date, end: Date, note: String) async throws {
        gymEventCreationCount += 1
        lastGymStart = start
        lastGymEnd = end
        lastGymNote = note
        if suspendGymEventCreation {
            await withCheckedContinuation { continuation in
                gymEventContinuation = continuation
                onGymEventCreationStarted?()
            }
        } else {
            onGymEventCreationStarted?()
        }
        if let gymEventError { throw gymEventError }
        gymEventPresent = true
    }

    func createGymEvents(_ request: CalendarEventWriteRequest) async throws -> CalendarEventWriteResult {
        gymEventCreationCount += 1
        lastWriteRequest = request
        lastGymStart = request.start
        lastGymEnd = request.end
        lastGymNote = request.detailedNotes
        if suspendGymEventCreation {
            await withCheckedContinuation { continuation in
                gymEventContinuation = continuation
                onGymEventCreationStarted?()
            }
        } else {
            onGymEventCreationStarted?()
        }
        if let gymEventError { throw gymEventError }
        gymEventPresent = true
        if let nextWriteResult {
            self.nextWriteResult = nil
            activeReceipts = nextWriteResult.activeReceipts
            return nextWriteResult
        }

        var written: [CalendarEventReceipt] = []
        if let identifier = request.destinations.detailedCalendarIdentifier {
            written.append(receipt(for: identifier, role: .detailed))
        }
        written.append(contentsOf: request.destinations.busyCalendarIdentifiers.sorted().map {
            receipt(for: $0, role: .busy)
        })
        for receipt in written {
            activeReceipts.removeAll {
                $0.role == receipt.role && $0.calendarIdentifier == receipt.calendarIdentifier
            }
            activeReceipts.append(receipt)
        }
        activeReceipts.removeAll { receipt in
            if receipt.role == .detailed {
                return written.contains(where: { $0.role == .detailed })
                    && receipt.calendarIdentifier
                        != request.destinations.detailedCalendarIdentifier
            }
            return !request.destinations.busyCalendarIdentifiers
                .contains(receipt.calendarIdentifier)
        }
        return CalendarEventWriteResult(
            activeReceipts: activeReceipts,
            writtenReceipts: written,
            failures: []
        )
    }

    func hasGymEvent(start: Date, end: Date) throws -> Bool {
        presenceCheckCount += 1
        if let presenceError { throw presenceError }
        return gymEventPresent
    }

    func verifyGymEvents(
        receipts: [CalendarEventReceipt],
        start: Date,
        end: Date
    ) throws -> CalendarEventVerificationResult {
        presenceCheckCount += 1
        if let presenceError { throw presenceError }
        if let nextVerificationResult {
            self.nextVerificationResult = nil
            return nextVerificationResult
        }
        let resolved = receipts.isEmpty
            ? (activeReceipts.isEmpty
                ? [receipt(for: CalendarDescriptor.legacyDefault.id, role: .detailed)]
                : activeReceipts)
            : receipts
        return CalendarEventVerificationResult(
            verifiedReceipts: gymEventPresent ? resolved : [],
            missingReceipts: gymEventPresent ? [] : resolved,
            failures: []
        )
    }

    func cancelGymEvent(start: Date, end: Date) throws {
        gymEventCancellationCount += 1
        if let cancelError { throw cancelError }
        gymEventPresent = false
    }

    func cancelGymEvents(
        receipts: [CalendarEventReceipt],
        start: Date,
        end: Date
    ) throws -> CalendarEventUndoResult {
        gymEventCancellationCount += 1
        if let cancelError { throw cancelError }
        if !queuedUndoResults.isEmpty {
            let result = queuedUndoResults.removeFirst()
            activeReceipts = result.remainingReceipts
            gymEventPresent = !result.remainingReceipts.isEmpty
            return result
        }
        let resolved = receipts.isEmpty ? activeReceipts : receipts
        activeReceipts = []
        gymEventPresent = false
        return CalendarEventUndoResult(
            removedReceipts: resolved,
            remainingReceipts: [],
            failures: []
        )
    }

    func setEventStoreChangeHandler(_ handler: @escaping () -> Void) {
        eventStoreChangeHandler = handler
    }

    func emitEventStoreChange() {
        eventStoreChangeHandler?()
    }

    func resumeGymEventCreation() {
        suspendGymEventCreation = false
        gymEventContinuation?.resume()
        gymEventContinuation = nil
    }

    private func receipt(
        for calendarIdentifier: String,
        role: CalendarEventRole
    ) -> CalendarEventReceipt {
        let descriptor = calendarSources
            .flatMap(\.calendars)
            .first { $0.id == calendarIdentifier }
        return CalendarEventReceipt(
            eventIdentifier: "mock-\(role.rawValue)-\(calendarIdentifier)",
            calendarIdentifier: calendarIdentifier,
            calendarTitle: descriptor?.title ?? "Selected calendar",
            role: role,
            startDate: lastGymStart,
            endDate: lastGymEnd
        )
    }
}

private final class StubEventStore: EKEventStore {
    var matchingEvents: [EKEvent] = []

    override func event(withIdentifier identifier: String) -> EKEvent? {
        nil
    }

    override func calendarItem(withIdentifier identifier: String) -> EKCalendarItem? {
        nil
    }

    override func events(matching predicate: NSPredicate) -> [EKEvent] {
        matchingEvents
    }
}

private final class MockAlarmService: AlarmScheduling {
    var authorizationLabel = "Authorized"
    var scheduleError: Error?
    var presenceError: Error?
    var wakeAlarmPresent = true
    var suspendNextSchedule = false
    var onScheduleStarted: (() -> Void)?
    private(set) var scheduleCount = 0
    private(set) var cancelCount = 0
    private(set) var presenceCheckCount = 0
    private(set) var lastScheduledDate: Date?
    private(set) var persistedWakeDate: Date?
    private var scheduleContinuation: CheckedContinuation<Void, Never>?

    func scheduleWakeAlarm(at date: Date) async throws {
        scheduleCount += 1
        lastScheduledDate = date
        if suspendNextSchedule {
            suspendNextSchedule = false
            await withCheckedContinuation { continuation in
                scheduleContinuation = continuation
                onScheduleStarted?()
            }
        } else {
            onScheduleStarted?()
        }
        if let scheduleError { throw scheduleError }
        wakeAlarmPresent = true
        persistedWakeDate = date
    }

    func hasWakeAlarm(scheduledAt date: Date) throws -> Bool {
        presenceCheckCount += 1
        if let presenceError { throw presenceError }
        guard wakeAlarmPresent else { return false }
        guard let persistedWakeDate else { return true }
        return abs(persistedWakeDate.timeIntervalSince(date)) < 1
    }

    func cancelWakeAlarm() throws {
        cancelCount += 1
        wakeAlarmPresent = false
        persistedWakeDate = nil
    }

    func resumeSchedule() {
        scheduleContinuation?.resume()
        scheduleContinuation = nil
    }
}

private final class MockPrivateAppStateStore: PrivateAppStatePersisting {
    let removesLegacyDefaultsAfterSave = true
    var failWrites = false
    var failRemovals = false
    private var storage: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        storage[key]
    }

    func set(_ data: Data, forKey key: String) -> Bool {
        guard !failWrites else { return false }
        storage[key] = data
        return true
    }

    func removeData(forKey key: String) -> Bool {
        guard !failRemovals else { return false }
        storage.removeValue(forKey: key)
        return true
    }
}

private enum StubError: LocalizedError {
    case calendarWriteFailed
    case calendarReadFailed
    case alarmReadFailed
    case alarmWriteFailed
    case healthAuthorizationFailed
    case backgroundDeliveryFailed
    case workoutExportFailed

    var errorDescription: String? {
        switch self {
        case .calendarWriteFailed: "Calendar write failed."
        case .calendarReadFailed: "Calendar read failed."
        case .alarmReadFailed: "Alarm read failed."
        case .alarmWriteFailed: "Alarm write failed."
        case .healthAuthorizationFailed: "Health authorization failed."
        case .backgroundDeliveryFailed: "Background delivery failed."
        case .workoutExportFailed: "Workout export failed."
        }
    }
}
