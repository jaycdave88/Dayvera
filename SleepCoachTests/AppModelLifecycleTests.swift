import SwiftData
import XCTest
@testable import SleepCoach

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
            .appendingPathComponent("sleepcoach-private-state-\(UUID().uuidString)", isDirectory: true)
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
            "Sleep Coach couldn’t securely save the plan before applying it. No system changes were requested."
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

    func testBackgroundDeliveryFailureIsSurfacedAndCanRecover() async {
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
        XCTAssertEqual(model.notice, "Background delivery failed.")
        XCTAssertEqual(model.healthStatus, "No readable samples · Background updates unavailable")

        health.backgroundDeliveryError = nil
        await model.refresh()

        XCTAssertEqual(health.observerConfigurationCount, 2)
        XCTAssertNil(model.healthBackgroundDeliveryFailure)
        XCTAssertNil(model.notice)
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

    func testObserverRuntimeFailureSurfacesAndRemainsRetryable() async {
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
        health.backgroundDeliveryError = StubError.backgroundDeliveryFailed

        await health.emitBackgroundEvent(.observerFailed(
            kind: .sleep,
            typeIdentifier: "HKCategoryTypeIdentifierSleepAnalysis",
            message: "Observer failed."
        ))

        XCTAssertEqual(health.observerConfigurationCount, 2)
        XCTAssertEqual(model.healthBackgroundDeliveryFailure, "Background delivery failed.")

        health.backgroundDeliveryError = nil
        await model.refresh()

        XCTAssertEqual(health.observerConfigurationCount, 3)
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

        await model.start()
        XCTAssertEqual(model.snapshot.latestSleep?.sourceName, "Eight Sleep")
        XCTAssertEqual(health.fetchCount, 1)

        var preferences = model.preferences
        let sleepIndex = try! XCTUnwrap(
            preferences.decisionMetricPreferences.firstIndex { $0.metric == .sleep }
        )
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
        XCTAssertEqual(calendar.lastGymNote, "Created by Sleep Coach.")
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

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "app.sleepcoach.tests.\(UUID().uuidString)"
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
    var commitment: CalendarCommitment?
    var commitmentError: Error?
    var accessGranted = true
    var gymEventError: Error?
    var cancelError: Error?
    var presenceError: Error?
    var gymEventPresent = true
    var suspendGymEventCreation = false
    var onGymEventCreationStarted: (() -> Void)?
    private(set) var accessRequestCount = 0
    private(set) var commitmentQueryCount = 0
    private(set) var gymEventCreationCount = 0
    private(set) var gymEventCancellationCount = 0
    private(set) var presenceCheckCount = 0
    private(set) var lastGymStart: Date?
    private(set) var lastGymEnd: Date?
    private(set) var lastGymNote: String?
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

    func hasGymEvent(start: Date, end: Date) throws -> Bool {
        presenceCheckCount += 1
        if let presenceError { throw presenceError }
        return gymEventPresent
    }

    func cancelGymEvent(start: Date, end: Date) throws {
        gymEventCancellationCount += 1
        if let cancelError { throw cancelError }
        gymEventPresent = false
    }

    func resumeGymEventCreation() {
        suspendGymEventCreation = false
        gymEventContinuation?.resume()
        gymEventContinuation = nil
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
