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

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "app.sleepcoach.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
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
    var isAvailable = true
    var samples: [MetricSample] = []
    var queryFailures: [HealthQueryFailure] = []
    var fetchError: Error?
    private(set) var authorizationRequestCount = 0
    private(set) var fetchCount = 0
    private(set) var observerConfigurationCount = 0
    private(set) var savedWorkoutCount = 0

    func requestAuthorization() async throws {
        authorizationRequestCount += 1
    }

    func fetchSamples(since startDate: Date, through endDate: Date) async throws -> HealthSampleFetchResult {
        fetchCount += 1
        if let fetchError { throw fetchError }
        return HealthSampleFetchResult(samples: samples, queryFailures: queryFailures)
    }

    func saveStrengthWorkout(start: Date, end: Date) async throws {
        savedWorkoutCount += 1
    }

    func configureBackgroundDelivery(onUpdate: @escaping @Sendable () async -> Void) async {
        observerConfigurationCount += 1
    }
}

private final class MockCalendarService: CalendarProviding {
    var commitment: CalendarCommitment?
    var accessGranted = true
    var gymEventError: Error?
    var suspendGymEventCreation = false
    var onGymEventCreationStarted: (() -> Void)?
    private(set) var accessRequestCount = 0
    private(set) var commitmentQueryCount = 0
    private(set) var gymEventCreationCount = 0
    private(set) var gymEventCancellationCount = 0
    private(set) var lastGymStart: Date?
    private(set) var lastGymEnd: Date?
    private var gymEventContinuation: CheckedContinuation<Void, Never>?

    func requestAccess() async throws -> Bool {
        accessRequestCount += 1
        return accessGranted
    }

    func firstCommitment(on date: Date) async throws -> CalendarCommitment? {
        commitmentQueryCount += 1
        return commitment
    }

    func createGymEvent(start: Date, end: Date, note: String) async throws {
        gymEventCreationCount += 1
        lastGymStart = start
        lastGymEnd = end
        if suspendGymEventCreation {
            await withCheckedContinuation { continuation in
                gymEventContinuation = continuation
                onGymEventCreationStarted?()
            }
        } else {
            onGymEventCreationStarted?()
        }
        if let gymEventError { throw gymEventError }
    }

    func cancelGymEvent() throws {
        gymEventCancellationCount += 1
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
    private(set) var scheduleCount = 0
    private(set) var cancelCount = 0
    private(set) var lastScheduledDate: Date?

    func scheduleWakeAlarm(at date: Date) async throws {
        scheduleCount += 1
        lastScheduledDate = date
        if let scheduleError { throw scheduleError }
    }

    func cancelWakeAlarm() throws {
        cancelCount += 1
    }
}

private enum StubError: LocalizedError {
    case calendarWriteFailed

    var errorDescription: String? {
        switch self {
        case .calendarWriteFailed: "Calendar write failed."
        }
    }
}
