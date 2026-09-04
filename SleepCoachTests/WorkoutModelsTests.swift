import HealthKit
import XCTest
@testable import SleepCoach

final class WorkoutModelsTests: XCTestCase {
    func testWorkoutReadinessDistinguishesMissingDataFromRealZero() {
        let unavailable = WorkoutSessionRecord(
            templateID: nil,
            templateName: "No recovery data",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            readiness: .moderate,
            readinessScore: 0,
            readinessAvailable: false,
            sets: []
        )
        let realZero = WorkoutSessionRecord(
            templateID: nil,
            templateName: "Measured zero",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            readiness: .low,
            readinessScore: 0,
            readinessAvailable: true,
            sets: []
        )
        let legacyZero = WorkoutSessionRecord(
            templateID: nil,
            templateName: "Legacy",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            readiness: .moderate,
            readinessScore: 0,
            sets: []
        )
        legacyZero.readinessWasAvailable = nil

        XCTAssertNil(unavailable.recordedReadinessScore)
        XCTAssertEqual(realZero.recordedReadinessScore, 0)
        XCTAssertNil(legacyZero.recordedReadinessScore)
    }

    func testWorkoutHealthExportStartsPendingAndFailedRetryIncrementsVersion() {
        let session = WorkoutSessionRecord(
            templateID: nil,
            templateName: "Lower",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            readiness: .moderate,
            readinessScore: 60,
            sets: []
        )

        XCTAssertEqual(session.healthExportState, .pending)
        XCTAssertEqual(session.healthExportSyncVersion, 1)

        session.markHealthExportFailed(message: "Denied")
        session.prepareHealthExportRetry()

        XCTAssertEqual(session.healthExportState, .pending)
        XCTAssertEqual(session.healthExportSyncVersion, 2)
        XCTAssertNil(session.healthExportErrorMessage)
    }

    func testPendingHealthExportRetryAdvancesItsVersion() {
        let session = WorkoutSessionRecord(
            templateID: nil,
            templateName: "Lower",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            readiness: .moderate,
            readinessScore: 60,
            sets: [],
            healthExportSyncVersion: 4
        )

        session.prepareHealthExportRetry()

        XCTAssertEqual(session.healthExportState, .pending)
        XCTAssertEqual(session.healthExportSyncVersion, 5)
    }

    func testUnknownLegacyHealthExportCannotBeRetried() {
        let session = WorkoutSessionRecord(
            templateID: nil,
            templateName: "Legacy",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            readiness: .moderate,
            readinessScore: 60,
            sets: [],
            healthExportState: .unknown
        )

        XCTAssertFalse(session.prepareHealthExportRetry())
        XCTAssertEqual(session.healthExportState, .unknown)
        XCTAssertEqual(session.healthExportSyncVersion, 1)
    }

    func testHealthKitWorkoutMetadataUsesSessionIdentityAndSyncVersion() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000043")!

        let metadata = HealthKitService.workoutMetadata(sessionID: id, syncVersion: 9)

        XCTAssertEqual(metadata[HKMetadataKeySyncIdentifier] as? String, id.uuidString)
        XCTAssertEqual((metadata[HKMetadataKeySyncVersion] as? NSNumber)?.intValue, 9)
        XCTAssertEqual(metadata[HKMetadataKeyIndoorWorkout] as? Bool, true)
    }

    func testBackgroundDeliveryCoversEveryReadMetricType() {
        XCTAssertEqual(
            HealthKitService.readMetricTypeIdentifiers,
            [
                HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
                HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue,
                HKQuantityTypeIdentifier.restingHeartRate.rawValue,
                HKQuantityTypeIdentifier.respiratoryRate.rawValue,
                HKQuantityTypeIdentifier.oxygenSaturation.rawValue,
                HKQuantityTypeIdentifier.appleSleepingWristTemperature.rawValue,
                HKQuantityTypeIdentifier.bodyTemperature.rawValue,
                HKQuantityTypeIdentifier.heartRate.rawValue,
                HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
                HKQuantityTypeIdentifier.appleExerciseTime.rawValue,
                HKQuantityTypeIdentifier.stepCount.rawValue,
                HKObjectType.workoutType().identifier,
                HKQuantityTypeIdentifier.bodyMass.rawValue,
                HKQuantityTypeIdentifier.bodyFatPercentage.rawValue,
                HKQuantityTypeIdentifier.leanBodyMass.rawValue,
                HKQuantityTypeIdentifier.bodyMassIndex.rawValue
            ]
        )
    }

    func testRecentWorkoutDraftKeepsItsOriginalStart() {
        let now = Date(timeIntervalSince1970: 10_000)
        let savedStart = now.addingTimeInterval(-90 * 60)

        XCTAssertEqual(normalizedWorkoutStart(savedStart: savedStart, now: now), savedStart)
    }

    func testStaleWorkoutDraftRestartsToAvoidMultiDaySession() {
        let now = Date(timeIntervalSince1970: 100_000)
        let savedStart = now.addingTimeInterval(-7 * 60 * 60)

        XCTAssertEqual(normalizedWorkoutStart(savedStart: savedStart, now: now), now)
    }

    func testFutureDatedWorkoutDraftRestarts() {
        let now = Date(timeIntervalSince1970: 100_000)
        let savedStart = now.addingTimeInterval(60)

        XCTAssertEqual(normalizedWorkoutStart(savedStart: savedStart, now: now), now)
    }

    func testStaleWorkoutFinishAlwaysProducesAValidNonzeroInterval() {
        let end = Date(timeIntervalSince1970: 100_000)
        let staleStart = end.addingTimeInterval(-(7 * 60 * 60))

        let result = validWorkoutIntervalStart(savedStart: staleStart, end: end)

        XCTAssertEqual(result, end.addingTimeInterval(-60))
        XCTAssertLessThan(result, end)
    }

    func testAdaptedSetCountsMatchWholeTemplateTarget() {
        let exercises = (0..<3).map { index in
            WorkoutExercise(
                name: "Exercise \(index)",
                muscleGroup: .fullBody,
                workingSets: 3,
                targetReps: 8,
                targetWeight: 100,
                targetRPE: 8,
                restSeconds: 90
            )
        }

        let moderate = adaptedWorkingSetCounts(for: exercises, volumeMultiplier: 0.75)
        let low = adaptedWorkingSetCounts(for: exercises, volumeMultiplier: 0.35)

        XCTAssertEqual(moderate.values.reduce(0, +), 7)
        XCTAssertEqual(low.values.reduce(0, +), 3)
    }

    func testGeneratedWorkoutLaunchKeepsAppliedVolumeButPreservesProgressionGate() {
        let recoveryGate = WorkoutAdjustment(
            title: "Safety check",
            detail: "Hold progression.",
            volumeMultiplier: 0.75,
            rpeCap: 8,
            allowProgression: false
        )
        let ready = WorkoutAdjustment(
            title: "Full performance session",
            detail: "Full plan.",
            volumeMultiplier: 1,
            rpeCap: nil,
            allowProgression: true
        )

        let gatedLaunch = generatedWorkoutLaunchAdjustment(
            dailyAdjustment: recoveryGate,
            effort: .asPlanned
        )
        let easierLaunch = generatedWorkoutLaunchAdjustment(
            dailyAdjustment: ready,
            effort: .easier
        )

        XCTAssertEqual(gatedLaunch.volumeMultiplier, 1)
        XCTAssertNil(gatedLaunch.rpeCap)
        XCTAssertFalse(gatedLaunch.allowProgression)
        XCTAssertFalse(easierLaunch.allowProgression)
    }

    func testSessionVolumeExcludesWarmups() {
        let exerciseID = UUID()
        let sets = [
            CompletedSet(exerciseID: exerciseID, exerciseName: "Squat", setNumber: 0, weight: 45, reps: 10, rpe: 4, isWarmup: true, completedAt: .now),
            CompletedSet(exerciseID: exerciseID, exerciseName: "Squat", setNumber: 1, weight: 225, reps: 5, rpe: 8, isWarmup: false, completedAt: .now),
            CompletedSet(exerciseID: exerciseID, exerciseName: "Squat", setNumber: 2, weight: 225, reps: 5, rpe: 8.5, isWarmup: false, completedAt: .now)
        ]
        let session = WorkoutSessionRecord(
            templateID: nil,
            templateName: "Lower",
            startedAt: .now.addingTimeInterval(-3600),
            endedAt: .now,
            readiness: .high,
            readinessScore: 82,
            sets: sets
        )

        XCTAssertEqual(session.totalVolume, 2250, accuracy: 0.01)
        XCTAssertEqual(session.sets.count, 3)
    }

    func testCompletedSetDecodesLegacyJSONWithoutCatalogID() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let json = """
        {
          "id": "\(id.uuidString)",
          "exerciseID": "\(exerciseID.uuidString)",
          "exerciseName": "Back Squat",
          "setNumber": 1,
          "weight": 225,
          "reps": 5,
          "rpe": 8,
          "isWarmup": false,
          "completedAt": 0
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let set = try decoder.decode(CompletedSet.self, from: json)

        XCTAssertEqual(set.id, id)
        XCTAssertEqual(set.exerciseID, exerciseID)
        XCTAssertNil(set.catalogID)
        XCTAssertNil(set.loadUnit)
        XCTAssertEqual(set.resolvedLoadUnit, .pounds)
        XCTAssertEqual(set.progressionKey, "name:back squat")
    }

    func testLoadUnitsRemainPairedWithValuesAndConvertForComparison() {
        XCTAssertEqual(LoadUnit.pounds.convert(220.462, to: .kilograms), 100, accuracy: 0.001)
        XCTAssertEqual(LoadUnit.kilograms.convert(100, to: .pounds), 220.462, accuracy: 0.001)

        let exerciseID = UUID()
        let pounds = session(
            id: UUID(),
            day: 1,
            sets: [CompletedSet(
                exerciseID: exerciseID,
                catalogID: "deadlift",
                exerciseName: "Deadlift",
                setNumber: 1,
                weight: 220.462,
                loadUnit: .pounds,
                reps: 5,
                rpe: 8,
                isWarmup: false,
                completedAt: .now
            )]
        )
        let kilograms = session(
            id: UUID(),
            day: 2,
            sets: [CompletedSet(
                exerciseID: exerciseID,
                catalogID: "deadlift",
                exerciseName: "Deadlift",
                setNumber: 1,
                weight: 100,
                loadUnit: .kilograms,
                reps: 5,
                rpe: 8,
                isWarmup: false,
                completedAt: .now
            )]
        )

        let history = exercisePerformanceHistory(
            from: [pounds, kilograms],
            exerciseKey: "catalog:deadlift",
            displayedIn: .kilograms
        )

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].weight, 100, accuracy: 0.001)
        XCTAssertEqual(history[1].weight, 100, accuracy: 0.001)
        XCTAssertTrue(history.allSatisfy { $0.loadUnit == .kilograms })
    }

    func testExercisePerformanceUsesTopWorkingSetAndMarksLatestBestAsPB() {
        let exerciseID = UUID()
        let first = session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            day: 1,
            sets: [
                set(exerciseID: exerciseID, catalogID: "barbell-back-squat", name: "Back Squat", number: 0, weight: 135, reps: 8, warmup: true),
                set(exerciseID: exerciseID, catalogID: "barbell-back-squat", name: "Back Squat", number: 1, weight: 225, reps: 5),
                set(exerciseID: exerciseID, catalogID: "barbell-back-squat", name: "Back Squat", number: 2, weight: 210, reps: 8)
            ]
        )
        let second = session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            day: 2,
            sets: [
                set(exerciseID: exerciseID, catalogID: "barbell-back-squat", name: "Back Squat", number: 1, weight: 240, reps: 5),
                set(exerciseID: exerciseID, catalogID: "barbell-back-squat", name: "Back Squat", number: 2, weight: 215, reps: 8)
            ]
        )
        let tiedLatest = session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            day: 3,
            sets: [
                set(exerciseID: exerciseID, catalogID: "barbell-back-squat", name: "Back Squat", number: 1, weight: 240, reps: 5)
            ]
        )

        let history = exercisePerformanceHistory(
            from: [tiedLatest, first, second],
            exerciseKey: "catalog:barbell-back-squat"
        )

        XCTAssertEqual(history.map(\.sessionID), [first.id, second.id, tiedLatest.id])
        XCTAssertEqual(history[0].weight, 210, accuracy: 0.01)
        XCTAssertEqual(history[0].reps, 8)
        XCTAssertEqual(history[0].estimatedOneRepMax, 266, accuracy: 0.01)
        XCTAssertEqual(history.filter(\.isPersonalBest).map(\.sessionID), [tiedLatest.id])
    }

    func testExerciseProgressSeparatesCatalogExercisesWithSameName() {
        let exerciseID = UUID()
        let record = session(
            id: UUID(),
            day: 1,
            sets: [
                set(exerciseID: exerciseID, catalogID: "back-squat-a", name: "Squat", number: 1, weight: 200, reps: 5),
                set(exerciseID: exerciseID, catalogID: "back-squat-b", name: "Squat", number: 2, weight: 100, reps: 10)
            ]
        )

        let options = exerciseProgressOptions(from: [record])

        XCTAssertEqual(Set(options.map(\.id)), ["catalog:back-squat-a", "catalog:back-squat-b"])
        XCTAssertEqual(exercisePerformanceHistory(from: [record], exerciseKey: "catalog:back-squat-a").count, 1)
        XCTAssertEqual(exercisePerformanceHistory(from: [record], exerciseKey: "catalog:back-squat-b").count, 1)
    }

    func testCatalogIdentitySurvivesTemplateDraftAndCompletedSetRoundTrip() throws {
        let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let exercise = WorkoutExercise(
            id: exerciseID,
            catalogID: "goblet-squat",
            name: "Goblet Squat",
            muscleGroup: .quads,
            workingSets: 3,
            targetReps: 10,
            targetWeight: 35,
            loadUnit: .kilograms,
            targetRPE: 7,
            restSeconds: 90
        )
        let templateJSON = try JSONEncoder().encode([exercise])
        let restoredExercise = try XCTUnwrap(JSONDecoder().decode([WorkoutExercise].self, from: templateJSON).first)
        let legacyDraftSet = ActiveSet(
            exerciseID: restoredExercise.id,
            exerciseName: restoredExercise.name,
            setNumber: 1,
            weight: restoredExercise.targetWeight,
            reps: restoredExercise.targetReps,
            restSeconds: restoredExercise.restSeconds
        )

        let restoredDraftSet = try XCTUnwrap(backfillingCatalogIDs(in: [legacyDraftSet], from: [restoredExercise]).first)
        XCTAssertEqual(restoredDraftSet.catalogID, "goblet-squat")
        XCTAssertEqual(restoredDraftSet.loadUnit, .kilograms)

        let completed = CompletedSet(
            exerciseID: restoredDraftSet.exerciseID,
            catalogID: restoredDraftSet.catalogID,
            exerciseName: restoredDraftSet.exerciseName,
            setNumber: restoredDraftSet.setNumber,
            weight: restoredDraftSet.weight,
            loadUnit: restoredDraftSet.loadUnit,
            reps: restoredDraftSet.reps,
            isWarmup: false,
            completedAt: Date(timeIntervalSince1970: 0)
        )
        let completedJSON = try JSONEncoder().encode(completed)
        let restoredCompleted = try JSONDecoder().decode(CompletedSet.self, from: completedJSON)

        XCTAssertEqual(restoredCompleted.catalogID, "goblet-squat")
        XCTAssertEqual(restoredCompleted.loadUnit, .kilograms)
        XCTAssertEqual(restoredCompleted.progressionKey, "catalog:goblet-squat")
        XCTAssertNil(restoredCompleted.rpe)
    }

    func testPreviousSetUsesCatalogIdentityAndConvertsToDisplayUnit() throws {
        let exerciseID = UUID()
        let correct = session(
            id: UUID(),
            day: 2,
            sets: [set(
                exerciseID: exerciseID,
                catalogID: "barbell-bench-press",
                name: "Bench Press",
                number: 1,
                weight: 100,
                reps: 6,
                loadUnit: .kilograms
            )]
        )
        let newerSameNameDifferentCatalog = session(
            id: UUID(),
            day: 3,
            sets: [set(
                exerciseID: exerciseID,
                catalogID: "machine-bench-press",
                name: "Bench Press",
                number: 1,
                weight: 300,
                reps: 10
            )]
        )

        let previous = try XCTUnwrap(previousSetPerformance(
            catalogID: "barbell-bench-press",
            exerciseName: "Bench Press",
            setNumber: 1,
            from: [correct, newerSameNameDifferentCatalog],
            displayedIn: .pounds
        ))

        XCTAssertEqual(previous.sessionID, correct.id)
        XCTAssertEqual(previous.weight, 220.462, accuracy: 0.001)
        XCTAssertEqual(previous.loadUnit, .pounds)
        XCTAssertEqual(previous.reps, 6)
    }

    func testPreviousSetFallsBackToNormalizedNameForLegacyHistory() throws {
        let legacy = session(
            id: UUID(),
            day: 1,
            sets: [set(
                exerciseID: UUID(),
                catalogID: nil,
                name: "  GOBLET Squát  ",
                number: 2,
                weight: 50,
                reps: 10
            )]
        )

        let previous = try XCTUnwrap(previousSetPerformance(
            catalogID: "goblet-squat",
            exerciseName: "Goblet Squat",
            setNumber: 2,
            from: [legacy],
            displayedIn: .pounds
        ))

        XCTAssertEqual(previous.reps, 10)
        XCTAssertNil(previousSetPerformance(
            catalogID: "goblet-squat",
            exerciseName: "Goblet Squat",
            setNumber: 3,
            from: [legacy],
            displayedIn: .pounds
        ))
    }

    func testCustomExerciseDoesNotBorrowSameNameCatalogHistory() {
        let catalogHistory = progressionSession(
            for: progressionExercise(),
            day: 2,
            weight: 200,
            reps: 8
        )
        var customExercise = progressionExercise()
        customExercise.catalogID = nil

        XCTAssertNil(previousSetPerformance(
            catalogID: nil,
            exerciseName: customExercise.name,
            setNumber: 1,
            from: [catalogHistory],
            displayedIn: .pounds
        ))
        XCTAssertNil(workoutProgressionRecommendation(
            for: customExercise,
            sessions: [catalogHistory],
            displayedIn: .pounds,
            allowsProgression: true
        ))
    }

    func testProgressionAddsOneRepBeforeUpperRange() throws {
        let exercise = progressionExercise()
        let history = session(
            id: UUID(),
            day: 2,
            sets: [set(
                exerciseID: UUID(),
                catalogID: exercise.catalogID,
                name: exercise.name,
                number: 1,
                weight: 100,
                reps: 7
            )]
        )

        let recommendation = try XCTUnwrap(workoutProgressionRecommendation(
            for: exercise,
            sessions: [history],
            displayedIn: .pounds,
            allowsProgression: true
        ))

        XCTAssertEqual(recommendation.action, .increaseRepetitions)
        XCTAssertEqual(recommendation.suggestedLoad, 100)
        XCTAssertEqual(recommendation.suggestedRepetitions, 8)
        XCTAssertTrue(recommendation.canApply)
    }

    func testBodyweightProgressionHoldsAtUpperRange() throws {
        var exercise = progressionExercise()
        exercise.targetWeight = 0
        let history = progressionSession(for: exercise, day: 1, weight: 0, reps: 8)

        let recommendation = try XCTUnwrap(workoutProgressionRecommendation(
            for: exercise,
            sessions: [history],
            displayedIn: .pounds,
            allowsProgression: true
        ))

        XCTAssertEqual(recommendation.action, .hold)
        XCTAssertEqual(recommendation.suggestedRepetitions, 8)
        XCTAssertFalse(recommendation.canApply)
    }

    func testProgressionRequiresTwoLatestUpperRangeSessionsBeforeLoadIncrease() throws {
        let exercise = progressionExercise(loadUnit: .kilograms)
        let first = progressionSession(for: exercise, day: 1, weight: 100, reps: 8, loadUnit: .kilograms)
        let second = progressionSession(for: exercise, day: 2, weight: 100, reps: 8, loadUnit: .kilograms)

        let oneSession = try XCTUnwrap(workoutProgressionRecommendation(
            for: exercise,
            sessions: [first],
            displayedIn: .kilograms,
            allowsProgression: true
        ))
        let twoSessions = try XCTUnwrap(workoutProgressionRecommendation(
            for: exercise,
            sessions: [first, second],
            displayedIn: .kilograms,
            allowsProgression: true
        ))

        XCTAssertEqual(oneSession.action, .hold)
        XCTAssertFalse(oneSession.canApply)
        XCTAssertEqual(twoSessions.action, .increaseLoad)
        XCTAssertEqual(twoSessions.currentLoad, 100, accuracy: 0.001)
        XCTAssertEqual(twoSessions.suggestedLoad, 102.5, accuracy: 0.001)
        XCTAssertEqual(twoSessions.suggestedRepetitions, 6)
    }

    func testProgressionDoesNotSkipAnInterveningBelowRangeSession() throws {
        let exercise = progressionExercise()
        let firstSuccess = progressionSession(for: exercise, day: 1, weight: 200, reps: 8)
        let belowRange = progressionSession(for: exercise, day: 2, weight: 200, reps: 7)
        let secondSuccess = progressionSession(for: exercise, day: 3, weight: 200, reps: 8)

        let recommendation = try XCTUnwrap(workoutProgressionRecommendation(
            for: exercise,
            sessions: [belowRange, secondSuccess, firstSuccess],
            displayedIn: .pounds,
            allowsProgression: true
        ))

        XCTAssertEqual(recommendation.action, .hold)
        XCTAssertEqual(recommendation.suggestedLoad, 200)
        XCTAssertEqual(recommendation.suggestedRepetitions, 8)
    }

    func testProgressionRequiresLatestUpperRangeSessionsAtSameLoad() throws {
        let exercise = progressionExercise()
        let previous = progressionSession(for: exercise, day: 1, weight: 195, reps: 8)
        let latest = progressionSession(for: exercise, day: 2, weight: 200, reps: 8)

        let recommendation = try XCTUnwrap(workoutProgressionRecommendation(
            for: exercise,
            sessions: [latest, previous],
            displayedIn: .pounds,
            allowsProgression: true
        ))

        XCTAssertEqual(recommendation.action, .hold)
        XCTAssertEqual(recommendation.suggestedLoad, 200)
        XCTAssertFalse(recommendation.canApply)
    }

    func testPartialExerciseHistoryDoesNotCountAsUpperRangeSuccess() throws {
        let exercise = progressionExercise()
        let complete = progressionSession(for: exercise, day: 1, weight: 200, reps: 8)
        let partial = session(
            id: UUID(),
            day: 2,
            sets: [set(
                exerciseID: exercise.id,
                catalogID: exercise.catalogID,
                name: exercise.name,
                number: 1,
                weight: 200,
                reps: 8
            )]
        )

        let recommendation = try XCTUnwrap(workoutProgressionRecommendation(
            for: exercise,
            sessions: [complete, partial],
            displayedIn: .pounds,
            allowsProgression: true
        ))

        XCTAssertEqual(recommendation.action, .hold)
        XCTAssertEqual(recommendation.suggestedLoad, 200)
    }

    func testMixedLoadSessionsDoNotQualifyForLoadProgression() throws {
        let exercise = progressionExercise()
        let mixedSessions = [1, 2].map { day in
            session(
                id: UUID(),
                day: day,
                sets: [
                    set(exerciseID: exercise.id, catalogID: exercise.catalogID, name: exercise.name, number: 1, weight: 200, reps: 8),
                    set(exerciseID: exercise.id, catalogID: exercise.catalogID, name: exercise.name, number: 2, weight: 190, reps: 8),
                    set(exerciseID: exercise.id, catalogID: exercise.catalogID, name: exercise.name, number: 3, weight: 180, reps: 8)
                ]
            )
        }

        let recommendation = try XCTUnwrap(workoutProgressionRecommendation(
            for: exercise,
            sessions: mixedSessions,
            displayedIn: .pounds,
            allowsProgression: true
        ))

        XCTAssertEqual(recommendation.action, .hold)
        XCTAssertFalse(recommendation.canApply)
    }

    func testDuplicateSetNumbersDoNotQualifyForLoadProgression() throws {
        let exercise = progressionExercise()
        let duplicateSessions = [1, 2].map { day in
            session(
                id: UUID(),
                day: day,
                sets: [1, 2, 2].map { number in
                    set(
                        exerciseID: exercise.id,
                        catalogID: exercise.catalogID,
                        name: exercise.name,
                        number: number,
                        weight: 200,
                        reps: 8
                    )
                }
            )
        }

        let recommendation = try XCTUnwrap(workoutProgressionRecommendation(
            for: exercise,
            sessions: duplicateSessions,
            displayedIn: .pounds,
            allowsProgression: true
        ))

        XCTAssertEqual(recommendation.action, .hold)
        XCTAssertFalse(recommendation.canApply)
    }

    func testProgressionRecommendationAndApplicationNeverLowerDraftValues() {
        let exerciseID = UUID()
        let historical = WorkoutProgressionRecommendation(
            exerciseID: exerciseID,
            action: .increaseLoad,
            currentLoad: 100,
            suggestedLoad: 105,
            currentRepetitions: 8,
            suggestedRepetitions: 6,
            loadUnit: .pounds,
            rationale: "History supports a load increase."
        )
        let reconciled = nonRegressiveProgressionRecommendation(
            historical,
            currentDraftLoad: 100,
            currentDraftRepetitions: 8
        )
        let activeSets = [
            ActiveSet(
                exerciseID: exerciseID,
                exerciseName: "Bench Press",
                setNumber: 1,
                weight: 110,
                reps: 7,
                restSeconds: 120
            ),
            ActiveSet(
                exerciseID: exerciseID,
                exerciseName: "Bench Press",
                setNumber: 2,
                weight: 100,
                reps: 9,
                restSeconds: 120
            )
        ]

        let applied = applyingProgressionRecommendation(
            reconciled,
            to: activeSets,
            exerciseID: exerciseID,
            loadUnit: .pounds
        )

        XCTAssertEqual(reconciled.suggestedLoad, 105)
        XCTAssertEqual(reconciled.suggestedRepetitions, 8)
        XCTAssertEqual(applied[0].weight, 110)
        XCTAssertEqual(applied[0].reps, 8)
        XCTAssertEqual(applied[1].weight, 105)
        XCTAssertEqual(applied[1].reps, 9)
    }

    func testProgressionUndoDoesNotMutateASetCompletedAfterApply() {
        let exerciseID = UUID()
        let completedID = UUID()
        let editableID = UUID()
        let snapshots = [
            ActiveSetProgressionSnapshot(id: completedID, weight: 100, repetitions: 8),
            ActiveSetProgressionSnapshot(id: editableID, weight: 100, repetitions: 8)
        ]
        let progressedSets = [
            ActiveSet(
                id: completedID,
                exerciseID: exerciseID,
                exerciseName: "Bench Press",
                setNumber: 1,
                weight: 105,
                reps: 9,
                restSeconds: 120,
                isComplete: true
            ),
            ActiveSet(
                id: editableID,
                exerciseID: exerciseID,
                exerciseName: "Bench Press",
                setNumber: 2,
                weight: 105,
                reps: 9,
                restSeconds: 120
            )
        ]

        let restored = restoringProgressionSnapshot(
            in: progressedSets,
            exerciseID: exerciseID,
            snapshots: snapshots
        )

        XCTAssertEqual(restored[0].weight, 105)
        XCTAssertEqual(restored[0].reps, 9)
        XCTAssertEqual(restored[1].weight, 100)
        XCTAssertEqual(restored[1].reps, 8)
    }

    func testRecoveryGateCanOnlyHoldAHistoryBasedIncrease() throws {
        let exercise = progressionExercise()
        let sessions = [
            progressionSession(for: exercise, day: 1, weight: 200, reps: 8),
            progressionSession(for: exercise, day: 2, weight: 200, reps: 8)
        ]

        let recommendation = try XCTUnwrap(workoutProgressionRecommendation(
            for: exercise,
            sessions: sessions,
            displayedIn: .pounds,
            allowsProgression: false
        ))

        XCTAssertEqual(recommendation.action, .hold)
        XCTAssertEqual(recommendation.suggestedLoad, recommendation.currentLoad)
        XCTAssertEqual(recommendation.suggestedRepetitions, recommendation.currentRepetitions)
        XCTAssertFalse(recommendation.canApply)
    }

    func testActiveDraftRoundTripKeepsRestDeadlineAndSourceSet() throws {
        let sourceID = UUID()
        let deadline = Date(timeIntervalSince1970: 10_500)
        let draft = ActiveWorkoutDraft(
            templateID: UUID(),
            templateName: "Upper",
            exercises: [],
            startedAt: Date(timeIntervalSince1970: 10_000),
            sets: [ActiveSet(
                id: sourceID,
                exerciseID: UUID(),
                exerciseName: "Press",
                setNumber: 1,
                weight: 50,
                reps: 8,
                restSeconds: 90,
                isComplete: true
            )],
            notes: "",
            restDeadline: deadline,
            restSourceSetID: sourceID
        )

        let restored = try JSONDecoder().decode(
            ActiveWorkoutDraft.self,
            from: JSONEncoder().encode(draft)
        )

        XCTAssertEqual(restored.restDeadline, deadline)
        XCTAssertEqual(restored.restSourceSetID, sourceID)
        XCTAssertEqual(restored.sets.first?.id, sourceID)
    }

    func testLegacyActiveDraftWithoutNewOptionalFieldsStillDecodes() throws {
        let templateID = UUID()
        let setID = UUID()
        let exerciseID = UUID()
        let legacyJSON: [String: Any] = [
            "templateID": templateID.uuidString,
            "startedAt": 0,
            "sets": [[
                "id": setID.uuidString,
                "exerciseID": exerciseID.uuidString,
                "exerciseName": "Bench Press",
                "setNumber": 1,
                "weight": 100,
                "reps": 8,
                "restSeconds": 120,
                "isComplete": false
            ]],
            "notes": "legacy"
        ]

        let data = try JSONSerialization.data(withJSONObject: legacyJSON)
        let restored = try JSONDecoder().decode(ActiveWorkoutDraft.self, from: data)

        XCTAssertEqual(restored.templateID, templateID)
        XCTAssertNil(restored.templateName)
        XCTAssertNil(restored.exercises)
        XCTAssertNil(restored.restDeadline)
        XCTAssertNil(restored.restSourceSetID)
        XCTAssertNil(restored.sets.first?.catalogID)
        XCTAssertNil(restored.sets.first?.loadUnit)
    }

    private func session(id: UUID, day: Int, sets: [CompletedSet]) -> WorkoutSessionRecord {
        WorkoutSessionRecord(
            id: id,
            templateID: nil,
            templateName: "Lower",
            startedAt: Date(timeIntervalSince1970: TimeInterval(day * 86_400)),
            endedAt: Date(timeIntervalSince1970: TimeInterval(day * 86_400 + 3_600)),
            readiness: .high,
            readinessScore: 80,
            sets: sets
        )
    }

    private func set(
        exerciseID: UUID,
        catalogID: String?,
        name: String,
        number: Int,
        weight: Double,
        reps: Int,
        loadUnit: LoadUnit? = nil,
        warmup: Bool = false
    ) -> CompletedSet {
        CompletedSet(
            exerciseID: exerciseID,
            catalogID: catalogID,
            exerciseName: name,
            setNumber: number,
            weight: weight,
            loadUnit: loadUnit,
            reps: reps,
            rpe: warmup ? 4 : 8,
            isWarmup: warmup,
            completedAt: Date(timeIntervalSince1970: TimeInterval(number))
        )
    }

    private func progressionExercise(loadUnit: LoadUnit = .pounds) -> WorkoutExercise {
        WorkoutExercise(
            catalogID: "barbell-bench-press",
            name: "Bench Press",
            muscleGroup: .chest,
            workingSets: 3,
            targetReps: 6,
            targetRepRangeUpper: 8,
            targetWeight: 100,
            loadUnit: loadUnit,
            targetRPE: 8,
            restSeconds: 120
        )
    }

    private func progressionSession(
        for exercise: WorkoutExercise,
        day: Int,
        weight: Double,
        reps: Int,
        loadUnit: LoadUnit = .pounds
    ) -> WorkoutSessionRecord {
        session(
            id: UUID(),
            day: day,
            sets: (1...3).map { number in
                set(
                    exerciseID: exercise.id,
                    catalogID: exercise.catalogID,
                    name: exercise.name,
                    number: number,
                    weight: weight,
                    reps: reps,
                    loadUnit: loadUnit
                )
            }
        )
    }
}
