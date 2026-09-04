import XCTest
@testable import SleepCoach

@MainActor
final class DailyTrainingStateBuilderTests: XCTestCase {
    func testBuilderNormalizesRecoveryAndLocalTrainingHistory() throws {
        let now = date(year: 2026, month: 9, day: 10, hour: 12)
        let pool = CuratedExerciseCatalog.makePool(from: [])
        let exercise = try XCTUnwrap(pool.first(where: { $0.movementPattern == .horizontalPush }))
        let constraints = WorkoutConstraints(
            availableMinutes: 45,
            equipmentProfile: .fullGym
        )
        let sessions = [
            session(
                name: "Recent one",
                startedAt: date(year: 2026, month: 9, day: 5, hour: 7),
                set: completedSet(for: exercise, weight: 100, rpe: 8)
            ),
            session(
                name: "Recent two",
                startedAt: date(year: 2026, month: 9, day: 8, hour: 7),
                set: completedSet(for: exercise, weight: 105, rpe: 8)
            ),
            baselineSession(day: 13),
            baselineSession(day: 20),
            baselineSession(day: 27),
            baselineSession(month: 9, day: 2)
        ]

        let state = DailyTrainingStateBuilder(calendar: calendar).makeState(
            snapshot: healthSnapshot(now: now),
            sessions: sessions,
            constraints: constraints,
            curatedPool: pool,
            now: now
        )

        XCTAssertEqual(state.generatedAt, now)
        XCTAssertEqual(state.recovery.readinessScore, 72)
        XCTAssertEqual(state.recovery.readinessBand.rawValue, ReadinessBand.moderate.rawValue)
        XCTAssertEqual(state.recovery.sleepMinutes, 444)
        XCTAssertEqual(state.recovery.sleepTargetMinutes, 480)
        XCTAssertEqual(state.recovery.sleepVsBaselineMinutes, -21)
        XCTAssertEqual(try XCTUnwrap(state.recovery.heartRateVariabilityVsBaseline), -0.08, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(state.recovery.restingHeartRateDeltaBPM), 2, accuracy: 0.000_1)

        XCTAssertEqual(state.dataQuality.availability, .available)
        XCTAssertEqual(state.dataQuality.currentSignalCount, 3)
        XCTAssertEqual(state.dataQuality.baselineDayCount, 21)
        XCTAssertFalse(state.dataQuality.isStale)
        XCTAssertTrue(state.dataQuality.permitsProgressionSuggestion)

        XCTAssertEqual(state.training.sessionsLast7Days, 2)
        XCTAssertEqual(try XCTUnwrap(state.training.weeklyTrainingEffort), 1.6, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(state.training.loadVersus28DayAverage), 2, accuracy: 0.000_1)
        XCTAssertEqual(state.training.daysSinceTraining(exercise.primaryMuscleGroup), 2)
        XCTAssertEqual(state.training.mostRecentFocus, .upperBody)

        let movementLoad = try XCTUnwrap(state.training.load(for: exercise.movementPattern))
        XCTAssertEqual(movementLoad.workingSetsLast7Days, 2)
        XCTAssertEqual(movementLoad.targetWorkingSets, 6)
        XCTAssertEqual(movementLoad.targetDeficit, 4)

        let history = try XCTUnwrap(state.training.history(for: exercise.catalogID))
        XCTAssertEqual(history.completedSessions, 2)
        XCTAssertEqual(history.lastPerformedDaysAgo, 2)
        XCTAssertEqual(history.lastWorkingLoad, 105)
        XCTAssertEqual(history.lastCompletedReps, 8)
        XCTAssertEqual(history.lastRPE, 8)
        XCTAssertTrue(history.progressionEligible)

        let evidenceByID = Dictionary(uniqueKeysWithValues: state.evidence.map { ($0.id, $0) })
        XCTAssertEqual(evidenceByID["readiness"]?.provenance, .calculated)
        XCTAssertEqual(evidenceByID["sleep"]?.provenance, .measured)
        XCTAssertEqual(evidenceByID["lower-body-history"]?.provenance, .calculated)
        XCTAssertEqual(evidenceByID["available-time"]?.provenance, .userEntered)
        XCTAssertEqual(evidenceByID["equipment"]?.provenance, .userEntered)
    }

    func testDisabledRecoverySignalsCannotEnterNormalizedState() {
        let now = date(year: 2026, month: 9, day: 10, hour: 12)

        let state = makeState(
            now: now,
            enabledRecoveryMetrics: [.sleep]
        )

        XCTAssertEqual(state.recovery.sleepMinutes, 444)
        XCTAssertEqual(state.recovery.sleepVsBaselineMinutes, -21)
        XCTAssertNil(state.recovery.heartRateVariabilityVsBaseline)
        XCTAssertNil(state.recovery.restingHeartRateDeltaBPM)
        XCTAssertEqual(state.dataQuality.currentSignalCount, 1)
        XCTAssertEqual(state.dataQuality.baselineDayCount, 21)
        XCTAssertNotNil(state.evidence.first(where: { $0.id == "sleep" }))
    }

    func testMixedSignalConsentCountsOnlyEnabledInputs() throws {
        let now = date(year: 2026, month: 9, day: 10, hour: 12)

        let state = makeState(
            now: now,
            enabledRecoveryMetrics: [.heartRateVariability]
        )

        XCTAssertNotNil(state.recovery.readinessScore)
        XCTAssertNil(state.recovery.sleepMinutes)
        XCTAssertNil(state.recovery.sleepTargetMinutes)
        XCTAssertNil(state.recovery.sleepVsBaselineMinutes)
        XCTAssertEqual(try XCTUnwrap(state.recovery.heartRateVariabilityVsBaseline), -0.08, accuracy: 0.000_1)
        XCTAssertNil(state.recovery.restingHeartRateDeltaBPM)
        XCTAssertEqual(state.dataQuality.availability, .available)
        XCTAssertEqual(state.dataQuality.currentSignalCount, 1)
        XCTAssertEqual(state.dataQuality.baselineDayCount, 21)
        XCTAssertNil(state.evidence.first(where: { $0.id == "sleep" }))
        XCTAssertNotNil(state.evidence.first(where: { $0.id == "readiness" }))
    }

    func testNoEnabledSignalsProducesHealthFreeTrainingState() {
        let now = date(year: 2026, month: 9, day: 10, hour: 12)

        let state = makeState(now: now, enabledRecoveryMetrics: [])

        XCTAssertNil(state.recovery.readinessScore)
        XCTAssertNil(state.recovery.sleepMinutes)
        XCTAssertNil(state.recovery.sleepTargetMinutes)
        XCTAssertNil(state.recovery.sleepVsBaselineMinutes)
        XCTAssertNil(state.recovery.heartRateVariabilityVsBaseline)
        XCTAssertNil(state.recovery.restingHeartRateDeltaBPM)
        XCTAssertEqual(state.dataQuality.availability, .unavailable)
        XCTAssertEqual(state.dataQuality.confidence.rawValue, DataConfidence.low.rawValue)
        XCTAssertEqual(state.dataQuality.currentSignalCount, 0)
        XCTAssertEqual(state.dataQuality.baselineDayCount, 0)
        XCTAssertFalse(state.dataQuality.isStale)
        XCTAssertNil(state.evidence.first(where: { $0.id == "readiness" }))
        XCTAssertNil(state.evidence.first(where: { $0.id == "sleep" }))
        XCTAssertEqual(Set(state.evidence.map(\.id)), Set(["available-time", "equipment"]))
    }

    func testHistoryNormalizesMixedAndLegacyLoadsIntoRequestedUnit() throws {
        let now = date(year: 2026, month: 9, day: 10, hour: 12)
        let pool = CuratedExerciseCatalog.makePool(from: [])
        let exercises = Array(pool.prefix(2))
        XCTAssertEqual(exercises.count, 2)
        let legacyExercise = try XCTUnwrap(exercises.first)
        let metricExercise = exercises[1]
        let startedAt = date(year: 2026, month: 9, day: 8, hour: 7)
        let mixedUnitSession = WorkoutSessionRecord(
            templateID: nil,
            templateName: "Mixed units",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(45 * 60),
            readiness: .moderate,
            readinessScore: 72,
            sets: [
                completedSet(for: legacyExercise, weight: 100, rpe: 8),
                completedSet(for: metricExercise, weight: 50, loadUnit: .kilograms, rpe: 8)
            ]
        )

        let state = DailyTrainingStateBuilder(calendar: calendar).makeState(
            snapshot: healthSnapshot(now: now),
            sessions: [mixedUnitSession],
            constraints: WorkoutConstraints(
                availableMinutes: 45,
                equipmentProfile: .fullGym
            ),
            curatedPool: pool,
            loadUnit: .kilograms,
            now: now
        )

        XCTAssertEqual(
            try XCTUnwrap(state.training.history(for: legacyExercise.catalogID)?.lastWorkingLoad),
            45.359_237,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(state.training.history(for: metricExercise.catalogID)?.lastWorkingLoad),
            50,
            accuracy: 0.000_001
        )
    }

    func testTrainingProfilePersistsAndReloadsFromPrivateState() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TrainingStateTestPrivateStore()
        let garageID = EquipmentProfileID(rawValue: "garage")
        let profile = TrainingProfile(
            goal: .strength,
            targetSessionsPerWeek: 5,
            loadUnit: .kilograms,
            equipmentProfiles: [
                .fullGym,
                .home,
                .travel,
                EquipmentProfile(
                    id: garageID,
                    name: "Garage",
                    equipment: [.dumbbell, .kettlebell, .adjustableBench]
                )
            ],
            activeEquipmentProfileID: garageID,
            preferredExerciseIDs: ["bench-press"],
            excludedExerciseIDs: ["deadlift"],
            excludedMovementPatterns: [.verticalPush],
            onDevicePersonalizationEnabled: true
        )
        let model = makeAppModel(defaults: defaults, store: store)

        model.trainingProfile = profile

        let storedProfile = try JSONDecoder().decode(
            TrainingProfile.self,
            from: XCTUnwrap(store.data(forKey: "trainingProfile"))
        )
        XCTAssertEqual(storedProfile, profile)

        let reloadedModel = makeAppModel(defaults: defaults, store: store)
        XCTAssertEqual(reloadedModel.trainingProfile, profile)
        XCTAssertEqual(reloadedModel.trainingProfile.activeEquipmentProfile.name, "Garage")
    }

    func testSparseLegacyTrainingProfileDecodesWithSafeDefaultsAndMigrates() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TrainingStateTestPrivateStore()
        let legacyData = Data(
            """
            {
              "targetSessionsPerWeek": 5,
              "preferredExerciseIDs": ["bench-press"],
              "onDevicePersonalizationEnabled": true
            }
            """.utf8
        )
        defaults.set(legacyData, forKey: "trainingProfile")

        let model = makeAppModel(defaults: defaults, store: store)

        XCTAssertEqual(model.trainingProfile.goal, .strengthAndMuscle)
        XCTAssertEqual(model.trainingProfile.targetSessionsPerWeek, 5)
        XCTAssertEqual(model.trainingProfile.loadUnit, .pounds)
        XCTAssertEqual(model.trainingProfile.activeEquipmentProfileID, .fullGym)
        XCTAssertEqual(model.trainingProfile.equipmentProfiles, [.fullGym, .home, .travel])
        XCTAssertEqual(model.trainingProfile.preferredExerciseIDs, ["bench-press"])
        XCTAssertTrue(model.trainingProfile.excludedExerciseIDs.isEmpty)
        XCTAssertTrue(model.trainingProfile.excludedMovementPatterns.isEmpty)
        XCTAssertTrue(model.trainingProfile.onDevicePersonalizationEnabled)
        XCTAssertNil(defaults.data(forKey: "trainingProfile"))
        XCTAssertEqual(store.data(forKey: "trainingProfile"), legacyData)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        year: Int = 2026,
        month: Int = 8,
        day: Int,
        hour: Int = 7
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    private func session(
        name: String,
        startedAt: Date,
        set: CompletedSet
    ) -> WorkoutSessionRecord {
        WorkoutSessionRecord(
            templateID: nil,
            templateName: name,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(45 * 60),
            readiness: .moderate,
            readinessScore: 72,
            sets: [set]
        )
    }

    private func completedSet(
        for exercise: CuratedExerciseDefinition,
        weight: Double,
        loadUnit: LoadUnit? = nil,
        rpe: Double
    ) -> CompletedSet {
        CompletedSet(
            exerciseID: UUID(),
            catalogID: exercise.catalogID,
            muscleGroup: exercise.primaryMuscleGroup,
            equipment: exercise.requiredEquipment.first?.rawValue,
            movementPattern: exercise.movementPattern.rawValue,
            exerciseName: exercise.name,
            setNumber: 1,
            weight: weight,
            loadUnit: loadUnit,
            reps: 8,
            rpe: rpe,
            isWarmup: false,
            completedAt: .distantPast
        )
    }

    private func baselineSession(month: Int = 8, day: Int) -> WorkoutSessionRecord {
        let startedAt = date(month: month, day: day)
        let set = CompletedSet(
            exerciseID: UUID(),
            catalogID: nil,
            muscleGroup: .quads,
            equipment: EquipmentID.bodyweight.rawValue,
            movementPattern: MovementPattern.squat.rawValue,
            exerciseName: "Bodyweight squat",
            setNumber: 1,
            weight: 0,
            reps: 12,
            rpe: 8,
            isWarmup: false,
            completedAt: startedAt.addingTimeInterval(10 * 60)
        )
        return session(name: "Baseline", startedAt: startedAt, set: set)
    }

    private func healthSnapshot(now: Date) -> DailyHealthSnapshot {
        let sleepEnd = date(year: 2026, month: 9, day: 10, hour: 7)
        let sleep = SleepSession(
            id: UUID(),
            startDate: sleepEnd.addingTimeInterval(-480 * 60),
            endDate: sleepEnd,
            asleepMinutes: 444,
            inBedMinutes: 480,
            deepMinutes: 70,
            remMinutes: 95,
            sourceName: "Eight Sleep",
            sourceBundleIdentifier: "com.eightsleep.app"
        )
        return DailyHealthSnapshot(
            generatedAt: now,
            samples: [],
            sleepSessions: [sleep],
            latestSleep: sleep,
            readinessAvailable: true,
            sleepDebtMinutes: 36,
            readinessScore: 72,
            readinessBand: .moderate,
            confidence: .high,
            reasons: [],
            latestHRV: 46,
            baselineHRV: 50,
            latestRestingHeartRate: 58,
            baselineRestingHeartRate: 56,
            previousDayActiveEnergy: nil,
            sleepTrend: trend(
                kind: .sleep,
                currentValue: 444,
                referenceValue: 480,
                average: 465,
                now: now
            ),
            hrvTrend: trend(
                kind: .heartRateVariability,
                currentValue: 46,
                referenceValue: 50,
                average: 49,
                now: now
            ),
            restingHeartRateTrend: trend(
                kind: .restingHeartRate,
                currentValue: 58,
                referenceValue: 56,
                average: 57,
                now: now
            ),
            todaySignalOrder: MetricKind.decisionMetrics,
            sleepTimingVariability: .empty,
            recoveryTakeaway: "Recovery is close to baseline."
        )
    }

    private func makeState(
        now: Date,
        enabledRecoveryMetrics: Set<MetricKind>
    ) -> DailyTrainingState {
        DailyTrainingStateBuilder(calendar: calendar).makeState(
            snapshot: healthSnapshot(now: now),
            sessions: [],
            constraints: WorkoutConstraints(
                availableMinutes: 45,
                equipmentProfile: .fullGym
            ),
            curatedPool: CuratedExerciseCatalog.makePool(from: []),
            enabledRecoveryMetrics: enabledRecoveryMetrics,
            now: now
        )
    }

    private func trend(
        kind: MetricKind,
        currentValue: Double,
        referenceValue: Double,
        average: Double,
        now: Date
    ) -> MetricTrendSeries {
        MetricTrendSeries(
            kind: kind,
            sourceName: "Test source",
            sourceBundleIdentifier: "app.sleepcoach.tests",
            currentValue: currentValue,
            currentDate: now,
            referenceValue: referenceValue,
            referenceLabel: "Personal baseline",
            baselineDayCount: 21,
            freshness: .current,
            ageInDays: 0,
            status: .nearTarget,
            statusText: "Near baseline",
            sourceHealth: MetricSourceHealth(
                state: .automatic,
                requestedBundleIdentifier: nil,
                selectedBundleIdentifier: "app.sleepcoach.tests",
                reason: "Selected automatically"
            ),
            points: [],
            sevenDaySummary: MetricTrendSummary(
                average: average,
                referenceValue: referenceValue,
                deltaFromReference: average - referenceValue,
                recordedDays: 7,
                expectedDays: 7
            ),
            twentyEightDaySummary: MetricTrendSummary(
                average: average,
                referenceValue: referenceValue,
                deltaFromReference: average - referenceValue,
                recordedDays: 21,
                expectedDays: 28
            )
        )
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "app.sleepcoach.training-state-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func makeAppModel(
        defaults: UserDefaults,
        store: TrainingStateTestPrivateStore
    ) -> AppModel {
        AppModel(
            health: TrainingStateTestHealthService(),
            calendar: TrainingStateTestCalendarService(),
            alarms: TrainingStateTestAlarmService(),
            wellness: WellnessEngine(calendar: calendar),
            defaults: defaults,
            privateStateStore: store
        )
    }
}

private final class TrainingStateTestPrivateStore: PrivateAppStatePersisting {
    let removesLegacyDefaultsAfterSave = true
    private var storage: [String: Data] = [:]

    func data(forKey key: String) -> Data? { storage[key] }

    func set(_ data: Data, forKey key: String) -> Bool {
        storage[key] = data
        return true
    }

    func removeData(forKey key: String) -> Bool {
        storage.removeValue(forKey: key)
        return true
    }
}

private final class TrainingStateTestHealthService: HealthDataProviding {
    let isAvailable = false

    func requestAuthorization() async throws {}

    func fetchSamples(since startDate: Date, through endDate: Date) async throws -> HealthSampleFetchResult {
        HealthSampleFetchResult(samples: [], queryFailures: [])
    }

    func saveStrengthWorkout(
        sessionID: UUID,
        syncVersion: Int,
        start: Date,
        end: Date
    ) async throws {}

    @MainActor
    func configureBackgroundDelivery(
        onUpdate: @escaping @MainActor @Sendable (HealthBackgroundEvent) async -> Void
    ) async throws {}
}

private final class TrainingStateTestCalendarService: CalendarProviding {
    let authorizationLabel = "Not connected"

    func requestAccess() async throws -> Bool { false }
    func firstCommitment(on date: Date) async throws -> CalendarCommitment? { nil }
    func createGymEvent(start: Date, end: Date, note: String) async throws {}
    func hasGymEvent(start: Date, end: Date) throws -> Bool { false }
    func cancelGymEvent(start: Date, end: Date) throws {}
}

private final class TrainingStateTestAlarmService: AlarmScheduling {
    let authorizationLabel = "Not connected"

    func scheduleWakeAlarm(at date: Date) async throws {}
    func hasWakeAlarm(scheduledAt date: Date) throws -> Bool { false }
    func cancelWakeAlarm() throws {}
}
