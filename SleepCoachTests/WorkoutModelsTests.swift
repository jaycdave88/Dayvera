import HealthKit
import XCTest
@testable import SleepCoach

final class WorkoutModelsTests: XCTestCase {
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
                HKQuantityTypeIdentifier.restingHeartRate.rawValue
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
        XCTAssertEqual(set.progressionKey, "name:back squat")
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
            rpe: restoredExercise.targetRPE,
            restSeconds: restoredExercise.restSeconds
        )

        let restoredDraftSet = try XCTUnwrap(backfillingCatalogIDs(in: [legacyDraftSet], from: [restoredExercise]).first)
        XCTAssertEqual(restoredDraftSet.catalogID, "goblet-squat")

        let completed = CompletedSet(
            exerciseID: restoredDraftSet.exerciseID,
            catalogID: restoredDraftSet.catalogID,
            exerciseName: restoredDraftSet.exerciseName,
            setNumber: restoredDraftSet.setNumber,
            weight: restoredDraftSet.weight,
            reps: restoredDraftSet.reps,
            rpe: restoredDraftSet.rpe,
            isWarmup: false,
            completedAt: Date(timeIntervalSince1970: 0)
        )
        let completedJSON = try JSONEncoder().encode(completed)
        let restoredCompleted = try JSONDecoder().decode(CompletedSet.self, from: completedJSON)

        XCTAssertEqual(restoredCompleted.catalogID, "goblet-squat")
        XCTAssertEqual(restoredCompleted.progressionKey, "catalog:goblet-squat")
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
        warmup: Bool = false
    ) -> CompletedSet {
        CompletedSet(
            exerciseID: exerciseID,
            catalogID: catalogID,
            exerciseName: name,
            setNumber: number,
            weight: weight,
            reps: reps,
            rpe: warmup ? 4 : 8,
            isWarmup: warmup,
            completedAt: Date(timeIntervalSince1970: TimeInterval(number))
        )
    }
}
