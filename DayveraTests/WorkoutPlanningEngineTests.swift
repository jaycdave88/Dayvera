import XCTest
@testable import Dayvera

final class WorkoutPlanningEngineTests: XCTestCase {
    private let engine = WorkoutPlanningEngine()

    func testSuccessfulGenerationAlwaysReturnsTheThreeFixedRoles() throws {
        let state = makeState(preferredFocus: .upperBody)

        let candidates = try engine.generate(from: state, curatedPool: exercisePool())

        XCTAssertEqual(candidates.all.map(\.role), [.primary, .shorter, .alternateFocus])
        XCTAssertEqual(candidates.all.count, 3)
        XCTAssertEqual(candidates.primary.plan.focus, .upperBody)
        XCTAssertNotEqual(candidates.alternateFocus.plan.focus, candidates.primary.plan.focus)
        XCTAssertLessThanOrEqual(
            candidates.shorter.plan.durationLimitMinutes,
            candidates.primary.plan.durationLimitMinutes
        )
        XCTAssertNoThrow(try engine.validate(candidates, against: state, curatedPool: exercisePool()))
    }

    func testGenerationIsDeterministicAcrossInputOrdering() throws {
        let state = makeState(preferredFocus: .upperBody)

        let forward = try engine.generate(from: state, curatedPool: exercisePool())
        let reversed = try engine.generate(from: state, curatedPool: exercisePool().reversed())

        XCTAssertEqual(forward, reversed)
    }

    func testPlannerPrefersFamiliarAndExplicitlyPreferredExercises() throws {
        let history = [
            ExerciseTrainingHistory(
                catalogID: "db-bench",
                completedSessions: 6,
                lastPerformedDaysAgo: 4,
                lastWorkingLoad: 60,
                lastCompletedReps: 8,
                lastRPE: 7.5,
                progressionEligible: false
            )
        ]
        let state = makeState(
            preferredFocus: .upperBody,
            preferredExerciseIDs: ["db-bench"],
            exerciseHistory: history
        )

        let candidates = try engine.generate(from: state, curatedPool: exercisePool())

        XCTAssertEqual(candidates.primary.plan.exercises.first?.catalogID, "db-bench")
        XCTAssertTrue(candidates.primary.plan.reasonCodes.contains(.familiarExercisesPrioritized))
    }

    func testEquipmentAndHardExclusionsAreNeverRelaxed() throws {
        let equipment = EquipmentProfile(
            id: EquipmentProfileID(rawValue: "dumbbells-only"),
            name: "Dumbbells Only",
            equipment: [.dumbbell]
        )
        let state = makeState(
            equipment: equipment,
            preferredFocus: .upperBody,
            excludedExerciseIDs: ["db-bench"],
            excludedMovementPatterns: [.verticalPush]
        )

        let candidates = try engine.generate(from: state, curatedPool: exercisePool())

        for prescription in candidates.all.flatMap(\.plan.exercises) {
            XCTAssertFalse(prescription.requiredEquipment.contains(.barbell))
            XCTAssertFalse(prescription.requiredEquipment.contains(.cableMachine))
            XCTAssertNotEqual(prescription.catalogID, "db-bench")
            XCTAssertNotEqual(prescription.movementPattern, .verticalPush)
        }
    }

    func testLowReadinessUsesOnlyLowDemandExercisesAndCapsRPE() throws {
        let state = makeState(
            band: .low,
            score: 38,
            equipment: .home,
            preferredFocus: .upperBody,
            dataQuality: Self.quality(confidence: .medium)
        )
        let poolByID = Dictionary(uniqueKeysWithValues: exercisePool().map { ($0.catalogID, $0) })

        let candidates = try engine.generate(from: state, curatedPool: exercisePool())

        XCTAssertEqual(candidates.primary.plan.mode, .reduced)
        for prescription in candidates.all.flatMap({ $0.plan.exercises }) {
            XCTAssertLessThanOrEqual(prescription.targetRPE, 6.5)
            XCTAssertLessThanOrEqual(poolByID[prescription.catalogID]?.recoveryDemand ?? .high, .low)
            XCTAssertNil(prescription.progressionSuggestion)
        }
    }

    func testLowConfidenceHighReadinessUsesConservativeEnvelope() throws {
        let progressionReadyHistory = [
            ExerciseTrainingHistory(
                catalogID: "db-bench",
                completedSessions: 8,
                lastPerformedDaysAgo: 4,
                lastWorkingLoad: 60,
                lastCompletedReps: 8,
                lastRPE: 7,
                progressionEligible: true
            )
        ]
        let highConfidence = makeState(
            band: .high,
            score: 86,
            preferredFocus: .upperBody,
            sessionsLast7Days: 2,
            preferredExerciseIDs: ["db-bench"],
            exerciseHistory: progressionReadyHistory,
            dataQuality: Self.quality(confidence: .high)
        )
        let lowConfidence = makeState(
            band: .high,
            score: 86,
            preferredFocus: .upperBody,
            sessionsLast7Days: 2,
            preferredExerciseIDs: ["db-bench"],
            exerciseHistory: progressionReadyHistory,
            dataQuality: Self.quality(confidence: .low)
        )
        let pool = exercisePool()
        let poolByID = Dictionary(uniqueKeysWithValues: pool.map { ($0.catalogID, $0) })

        let regular = try engine.generate(from: highConfidence, curatedPool: pool)
        let conservative = try engine.generate(from: lowConfidence, curatedPool: pool)

        XCTAssertEqual(regular.primary.plan.mode, .performance)
        XCTAssertEqual(conservative.primary.plan.mode, .balanced)
        XCTAssertTrue(conservative.primary.plan.reasonCodes.contains(.limitedRecoveryConfidence))
        XCTAssertTrue(conservative.primary.plan.reasonCodes.contains(.moderateReadiness))
        XCTAssertFalse(conservative.primary.plan.reasonCodes.contains(.highReadiness))
        XCTAssertGreaterThan(
            regular.primary.plan.exercises.reduce(0) { $0 + $1.workingSets },
            conservative.primary.plan.exercises.reduce(0) { $0 + $1.workingSets }
        )
        let regularBench = try XCTUnwrap(
            regular.primary.plan.exercises.first { $0.catalogID == "db-bench" }
        )
        let conservativeBench = try XCTUnwrap(
            conservative.primary.plan.exercises.first { $0.catalogID == "db-bench" }
        )
        XCTAssertNotNil(regularBench.progressionSuggestion)
        XCTAssertNil(conservativeBench.progressionSuggestion)
        for prescription in conservative.all.flatMap(\.plan.exercises) {
            XCTAssertLessThanOrEqual(prescription.targetRPE, 7.5)
            XCTAssertLessThanOrEqual(poolByID[prescription.catalogID]?.recoveryDemand ?? .high, .moderate)
            XCTAssertNil(prescription.progressionSuggestion)
        }
    }

    func testReachingWeeklySessionTargetReducesEnvelopeAndAddsReason() throws {
        let progressionReadyHistory = [
            ExerciseTrainingHistory(
                catalogID: "db-bench",
                completedSessions: 8,
                lastPerformedDaysAgo: 4,
                lastWorkingLoad: 60,
                lastCompletedReps: 8,
                lastRPE: 7,
                progressionEligible: true
            )
        ]
        let belowTarget = makeState(
            band: .high,
            score: 86,
            preferredFocus: .upperBody,
            targetSessionsPerWeek: 4,
            sessionsLast7Days: 3,
            preferredExerciseIDs: ["db-bench"],
            exerciseHistory: progressionReadyHistory
        )
        let targetReached = makeState(
            band: .high,
            score: 86,
            preferredFocus: .upperBody,
            targetSessionsPerWeek: 4,
            sessionsLast7Days: 4,
            preferredExerciseIDs: ["db-bench"],
            exerciseHistory: progressionReadyHistory
        )

        let regular = try engine.generate(from: belowTarget, curatedPool: exercisePool())
        let reduced = try engine.generate(from: targetReached, curatedPool: exercisePool())

        XCTAssertEqual(regular.primary.plan.mode, .performance)
        XCTAssertEqual(reduced.primary.plan.mode, .reduced)
        XCTAssertTrue(reduced.primary.plan.reasonCodes.contains(.weeklyTargetReached))
        XCTAssertGreaterThan(
            regular.primary.plan.exercises.reduce(0) { $0 + $1.workingSets },
            reduced.primary.plan.exercises.reduce(0) { $0 + $1.workingSets }
        )
        let regularBench = try XCTUnwrap(
            regular.primary.plan.exercises.first { $0.catalogID == "db-bench" }
        )
        let reducedBench = try XCTUnwrap(
            reduced.primary.plan.exercises.first { $0.catalogID == "db-bench" }
        )
        XCTAssertNotNil(regularBench.progressionSuggestion)
        XCTAssertNil(reducedBench.progressionSuggestion)
        XCTAssertTrue(reduced.all.flatMap(\.plan.exercises).allSatisfy { $0.targetRPE <= 7 })
    }

    func testGoalSpecificProgressionWaitsUntilPriorRepsReachNewRange() throws {
        let history = [
            ExerciseTrainingHistory(
                catalogID: "db-bench",
                completedSessions: 8,
                lastPerformedDaysAgo: 4,
                lastWorkingLoad: 60,
                lastCompletedReps: 6,
                lastRPE: 7,
                progressionEligible: true
            )
        ]
        let state = makeState(
            band: .high,
            score: 88,
            goal: .muscleGain,
            preferredFocus: .upperBody,
            sessionsLast7Days: 2,
            preferredExerciseIDs: ["db-bench"],
            exerciseHistory: history,
            dataQuality: Self.quality(confidence: .high)
        )

        let candidates = try engine.generate(from: state, curatedPool: exercisePool())
        let bench = try XCTUnwrap(
            candidates.primary.plan.exercises.first { $0.catalogID == "db-bench" }
        )

        XCTAssertEqual(bench.repetitions, RepRange(8, 12))
        XCTAssertNil(bench.progressionSuggestion)
    }

    func testTrainingGoalChangesSetsRepetitionsRestAndTitle() throws {
        let hybridState = makeState(
            goal: .strengthAndMuscle,
            preferredFocus: .upperBody,
            preferredExerciseIDs: ["db-bench"]
        )
        let strengthState = makeState(
            goal: .strength,
            preferredFocus: .upperBody,
            preferredExerciseIDs: ["db-bench"]
        )
        let muscleState = makeState(
            goal: .muscleGain,
            preferredFocus: .upperBody,
            preferredExerciseIDs: ["db-bench"]
        )

        let hybrid = try engine.generate(from: hybridState, curatedPool: exercisePool())
        let strength = try engine.generate(from: strengthState, curatedPool: exercisePool())
        let muscle = try engine.generate(from: muscleState, curatedPool: exercisePool())
        let hybridBench = try XCTUnwrap(hybrid.primary.plan.exercises.first { $0.catalogID == "db-bench" })
        let strengthBench = try XCTUnwrap(strength.primary.plan.exercises.first { $0.catalogID == "db-bench" })
        let muscleBench = try XCTUnwrap(muscle.primary.plan.exercises.first { $0.catalogID == "db-bench" })

        XCTAssertEqual(hybridBench.repetitions, RepRange(6, 10))
        XCTAssertEqual(strengthBench.repetitions, RepRange(4, 6))
        XCTAssertEqual(muscleBench.repetitions, RepRange(8, 12))
        XCTAssertGreaterThan(strengthBench.restSeconds, muscleBench.restSeconds)
        XCTAssertGreaterThan(strengthBench.workingSets, hybridBench.workingSets)
        XCTAssertGreaterThan(muscleBench.workingSets, hybridBench.workingSets)
        XCTAssertEqual(hybrid.primary.plan.title, "Upper Body Strength + Muscle")
        XCTAssertEqual(strength.primary.plan.title, "Upper Body Strength")
        XCTAssertEqual(muscle.primary.plan.title, "Upper Body Muscle")
        XCTAssertNoThrow(try engine.validate(hybrid, against: hybridState, curatedPool: exercisePool()))
        XCTAssertNoThrow(try engine.validate(strength, against: strengthState, curatedPool: exercisePool()))
        XCTAssertNoThrow(try engine.validate(muscle, against: muscleState, curatedPool: exercisePool()))
    }

    func testWeeklyLoadAboveEnvelopeReducesWorkingSets() throws {
        let base = makeState(
            band: .high,
            score: 84,
            preferredFocus: .upperBody,
            loadVersusBaseline: 1
        )
        let overloaded = makeState(
            band: .high,
            score: 84,
            preferredFocus: .upperBody,
            loadVersusBaseline: 1.3
        )

        let regular = try engine.generate(from: base, curatedPool: exercisePool())
        let reduced = try engine.generate(from: overloaded, curatedPool: exercisePool())

        XCTAssertGreaterThan(
            regular.primary.plan.exercises.reduce(0) { $0 + $1.workingSets },
            reduced.primary.plan.exercises.reduce(0) { $0 + $1.workingSets }
        )
        XCTAssertTrue(reduced.primary.plan.reasonCodes.contains(.weeklyLoadReduced))
    }

    func testPlannerProgressionIsConservativeRepsOnlyAndRequiresConfirmation() throws {
        let history = [
            ExerciseTrainingHistory(
                catalogID: "db-bench",
                completedSessions: 8,
                lastPerformedDaysAgo: 4,
                lastWorkingLoad: 60,
                lastCompletedReps: 8,
                lastRPE: 7,
                progressionEligible: true
            )
        ]
        let state = makeState(
            band: .high,
            score: 88,
            preferredFocus: .upperBody,
            preferredExerciseIDs: ["db-bench"],
            exerciseHistory: history,
            dataQuality: Self.quality(confidence: .high)
        )

        let candidates = try engine.generate(from: state, curatedPool: exercisePool())
        let bench = try XCTUnwrap(candidates.primary.plan.exercises.first { $0.catalogID == "db-bench" })
        let suggestion = try XCTUnwrap(bench.progressionSuggestion)

        XCTAssertEqual(bench.workingLoad, 60)
        XCTAssertEqual(suggestion.kind, .repetitions)
        XCTAssertEqual(suggestion.currentLoad, 60)
        XCTAssertEqual(suggestion.suggestedLoad, 60)
        XCTAssertEqual(suggestion.currentRepetitions, 8)
        XCTAssertEqual(suggestion.suggestedRepetitions, 9)
        XCTAssertTrue(suggestion.requiresConfirmation)
    }

    func testPlannerDoesNotSuggestLoadAtTopOfRangeWithoutSetLevelEvidence() throws {
        let history = [
            ExerciseTrainingHistory(
                catalogID: "db-bench",
                completedSessions: 8,
                lastPerformedDaysAgo: 4,
                lastWorkingLoad: 60,
                lastCompletedReps: 10,
                lastRPE: 7,
                progressionEligible: true
            )
        ]
        let state = makeState(
            band: .high,
            score: 88,
            preferredFocus: .upperBody,
            preferredExerciseIDs: ["db-bench"],
            exerciseHistory: history,
            dataQuality: Self.quality(confidence: .high)
        )

        let candidates = try engine.generate(from: state, curatedPool: exercisePool())
        let bench = try XCTUnwrap(
            candidates.primary.plan.exercises.first { $0.catalogID == "db-bench" }
        )

        XCTAssertNil(bench.progressionSuggestion)
    }

    func testProgressionIsOmittedWhenHealthConfidenceIsInsufficient() throws {
        let history = [
            ExerciseTrainingHistory(
                catalogID: "db-bench",
                completedSessions: 8,
                lastPerformedDaysAgo: 4,
                lastWorkingLoad: 60,
                lastCompletedReps: 8,
                lastRPE: 7,
                progressionEligible: true
            )
        ]
        let state = makeState(
            band: .high,
            score: 88,
            preferredFocus: .upperBody,
            preferredExerciseIDs: ["db-bench"],
            exerciseHistory: history,
            dataQuality: Self.quality(availability: .partial, confidence: .medium)
        )

        let candidates = try engine.generate(from: state, curatedPool: exercisePool())

        XCTAssertTrue(candidates.all.flatMap({ $0.plan.exercises }).allSatisfy { $0.progressionSuggestion == nil })
    }

    func testUnavailableHealthStillProducesDeterministicFallbackPlans() throws {
        let state = makeState(
            band: .moderate,
            score: nil,
            preferredFocus: .fullBody,
            dataQuality: Self.quality(availability: .unavailable, confidence: .low, currentSignals: 0)
        )

        let candidates = try engine.generate(from: state, curatedPool: exercisePool())

        XCTAssertTrue(candidates.primary.plan.reasonCodes.contains(.healthDataUnavailable))
        XCTAssertFalse(candidates.primary.plan.exercises.isEmpty)
        XCTAssertNoThrow(try engine.validate(candidates, against: state, curatedPool: exercisePool()))
    }

    func testEveryCandidateFitsItsOwnDurationLimit() throws {
        for duration in [15, 20, 30, 45, 60, 90] {
            let state = makeState(
                availableMinutes: duration,
                band: .moderate,
                preferredFocus: .upperBody
            )

            let candidates = try engine.generate(from: state, curatedPool: exercisePool())

            for candidate in candidates.all {
                XCTAssertLessThanOrEqual(
                    candidate.plan.expectedDurationMinutes,
                    candidate.plan.durationLimitMinutes,
                    "\(candidate.role) exceeded \(duration)-minute input"
                )
            }
        }
    }

    func testFullBodyCandidateContainsUpperAndLowerBodyWork() throws {
        let state = makeState(preferredFocus: .fullBody)

        let candidates = try engine.generate(from: state, curatedPool: exercisePool())
        let patterns = candidates.primary.plan.exercises.map(\.movementPattern)

        XCTAssertTrue(patterns.contains { $0.focus == .upperBody })
        XCTAssertTrue(patterns.contains { $0.focus == .lowerBody })
    }

    func testPrescriptionConvertsToExistingWorkoutExerciseWithPlanningMetadata() throws {
        let state = makeState(
            preferredFocus: .upperBody,
            preferredExerciseIDs: ["db-bench"]
        )
        let candidates = try engine.generate(from: state, curatedPool: exercisePool())
        let prescription = try XCTUnwrap(
            candidates.primary.plan.exercises.first { $0.catalogID == "db-bench" }
        )
        let workoutExercise = prescription.workoutExercise(
            loadUnit: .kilograms,
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000055")!
        )

        XCTAssertEqual(workoutExercise.catalogID, "db-bench")
        XCTAssertEqual(workoutExercise.equipment, "Adjustable Bench, Dumbbells")
        XCTAssertEqual(workoutExercise.movementPattern, MovementPattern.horizontalPush.rawValue)
        XCTAssertEqual(workoutExercise.targetWeight, 0)
        XCTAssertEqual(workoutExercise.loadUnit, .kilograms)
    }

    func testInvalidDurationFailsWithoutReturningPartialCandidates() {
        let state = makeState(availableMinutes: 10)

        XCTAssertThrowsError(try engine.generate(from: state, curatedPool: exercisePool())) { error in
            XCTAssertEqual(error as? WorkoutPlanningError, .invalidAvailableMinutes(10))
        }
    }

    func testDuplicateCatalogIdentityIsRejected() {
        let duplicate = exercisePool()[0]

        XCTAssertThrowsError(
            try engine.generate(from: makeState(), curatedPool: exercisePool() + [duplicate])
        ) { error in
            XCTAssertEqual(error as? WorkoutPlanningError, .duplicateCatalogID(duplicate.catalogID))
        }
    }

    func testUnavailableRequestedFocusFailsInsteadOfRelaxingConstraint() {
        let onlyUpperBody = exercisePool().filter {
            $0.movementPattern.focus == .upperBody || $0.movementPattern == .core
        }
        let state = makeState(preferredFocus: .lowerBody)

        XCTAssertThrowsError(try engine.generate(from: state, curatedPool: onlyUpperBody)) { error in
            XCTAssertEqual(error as? WorkoutPlanningError, .requestedFocusUnavailable(.lowerBody))
        }
    }

    func testValidatorRejectsAPlanFromAStaleDailyState() throws {
        let state = makeState(preferredFocus: .upperBody)
        let candidates = try engine.generate(from: state, curatedPool: exercisePool())
        let refreshedState = makeState(
            stateID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            preferredFocus: .upperBody
        )

        let issues = engine.validationIssues(
            for: candidates.primary.plan,
            state: refreshedState,
            curatedPool: exercisePool()
        )

        XCTAssertTrue(issues.contains {
            if case .staleState = $0 { return true }
            return false
        })
    }

    func testStateAndCandidatesRoundTripThroughCodable() throws {
        let state = makeState(preferredFocus: .upperBody)
        let candidates = try engine.generate(from: state, curatedPool: exercisePool())

        let restoredState = try JSONDecoder().decode(
            DailyTrainingState.self,
            from: JSONEncoder().encode(state)
        )
        let restoredCandidates = try JSONDecoder().decode(
            WorkoutPlanCandidates.self,
            from: JSONEncoder().encode(candidates)
        )

        XCTAssertEqual(restoredState, state)
        XCTAssertEqual(restoredCandidates, candidates)
    }

    private func makeState(
        stateID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!,
        availableMinutes: Int = 45,
        band: ReadinessBand = .moderate,
        score: Int? = 72,
        equipment: EquipmentProfile = .fullGym,
        goal: TrainingGoal = .strengthAndMuscle,
        preferredFocus: TrainingFocus? = nil,
        targetSessionsPerWeek: Int = 5,
        sessionsLast7Days: Int = 4,
        preferredExerciseIDs: Set<String> = [],
        excludedExerciseIDs: Set<String> = [],
        excludedMovementPatterns: Set<MovementPattern> = [],
        exerciseHistory: [ExerciseTrainingHistory] = [],
        loadVersusBaseline: Double? = 1,
        dataQuality: RecommendationDataQuality = WorkoutPlanningEngineTests.quality()
    ) -> DailyTrainingState {
        DailyTrainingState(
            stateID: stateID,
            generatedAt: Date(timeIntervalSince1970: 1_725_436_800),
            recovery: RecoveryState(
                readinessScore: score,
                readinessBand: band,
                sleepMinutes: 462,
                sleepTargetMinutes: 480,
                sleepVsBaselineMinutes: -12,
                heartRateVariabilityVsBaseline: -0.04,
                restingHeartRateDeltaBPM: 2
            ),
            training: TrainingHistoryState(
                sessionsLast7Days: sessionsLast7Days,
                weeklyTrainingEffort: 23,
                loadVersus28DayAverage: loadVersusBaseline,
                muscleRecency: [
                    MuscleTrainingRecency(muscleGroup: .chest, daysAgo: 4),
                    MuscleTrainingRecency(muscleGroup: .back, daysAgo: 3),
                    MuscleTrainingRecency(muscleGroup: .quads, daysAgo: 1),
                    MuscleTrainingRecency(muscleGroup: .hamstrings, daysAgo: 1)
                ],
                movementLoads: [
                    MovementTrainingLoad(movementPattern: .horizontalPush, workingSetsLast7Days: 4, targetWorkingSets: 8),
                    MovementTrainingLoad(movementPattern: .horizontalPull, workingSetsLast7Days: 4, targetWorkingSets: 8),
                    MovementTrainingLoad(movementPattern: .squat, workingSetsLast7Days: 6, targetWorkingSets: 8),
                    MovementTrainingLoad(movementPattern: .hinge, workingSetsLast7Days: 6, targetWorkingSets: 8)
                ],
                exerciseHistory: exerciseHistory,
                mostRecentFocus: .lowerBody
            ),
            constraints: WorkoutConstraints(
                availableMinutes: availableMinutes,
                goal: goal,
                targetSessionsPerWeek: targetSessionsPerWeek,
                equipmentProfile: equipment,
                preferredFocus: preferredFocus,
                preferredExerciseIDs: preferredExerciseIDs,
                excludedExerciseIDs: excludedExerciseIDs,
                excludedMovementPatterns: excludedMovementPatterns
            ),
            dataQuality: dataQuality,
            evidence: [
                EvidenceItem(
                    id: "sleep.latest",
                    provenance: .measured,
                    metric: .sleep,
                    title: "Sleep",
                    detail: "7h 42m",
                    value: 462,
                    unit: "min"
                )
            ]
        )
    }

    private static func quality(
        availability: HealthDataAvailability = .available,
        confidence: DataConfidence = .high,
        currentSignals: Int = 3
    ) -> RecommendationDataQuality {
        RecommendationDataQuality(
            availability: availability,
            confidence: confidence,
            currentSignalCount: currentSignals,
            baselineDayCount: 21,
            isStale: false
        )
    }

    private func exercisePool() -> [CuratedExerciseDefinition] {
        [
            exercise("barbell-bench", "Barbell Bench Press", .chest, .horizontalPush, [.barbell, .adjustableBench], demand: .high, increment: 5),
            exercise("db-bench", "Dumbbell Bench Press", .chest, .horizontalPush, [.dumbbell, .adjustableBench], increment: 5),
            exercise("push-up", "Push-Up", .chest, .horizontalPush, [.bodyweight], demand: .low),
            exercise("db-row", "Chest-Supported Row", .back, .horizontalPull, [.dumbbell, .adjustableBench]),
            exercise("band-row", "Band Row", .back, .horizontalPull, [.resistanceBand], demand: .low),
            exercise("db-press", "Dumbbell Shoulder Press", .shoulders, .verticalPush, [.dumbbell]),
            exercise("pull-up", "Pull-Up", .back, .verticalPull, [.pullUpBar]),
            exercise("db-curl", "Dumbbell Curl", .arms, .elbowFlexion, [.dumbbell], demand: .low),
            exercise("band-triceps", "Band Triceps Extension", .arms, .elbowExtension, [.resistanceBand], demand: .low),
            exercise("back-squat", "Back Squat", .quads, .squat, [.barbell, .squatRack], demand: .high, increment: 5),
            exercise("goblet-squat", "Goblet Squat", .quads, .squat, [.kettlebell]),
            exercise("bodyweight-squat", "Bodyweight Squat", .quads, .squat, [.bodyweight], demand: .low),
            exercise("db-rdl", "Dumbbell Romanian Deadlift", .hamstrings, .hinge, [.dumbbell]),
            exercise("band-good-morning", "Band Good Morning", .hamstrings, .hinge, [.resistanceBand], demand: .low),
            exercise("split-squat", "Split Squat", .glutes, .singleLeg, [.dumbbell]),
            exercise("glute-bridge", "Glute Bridge", .glutes, .hinge, [.bodyweight], demand: .low),
            exercise("calf-raise", "Standing Calf Raise", .calves, .calfRaise, [.bodyweight], demand: .low),
            exercise("dead-bug", "Dead Bug", .core, .core, [.bodyweight], demand: .low)
        ]
    }

    private func exercise(
        _ id: String,
        _ name: String,
        _ muscle: MuscleGroup,
        _ movement: MovementPattern,
        _ equipment: Set<EquipmentID>,
        demand: ExerciseRecoveryDemand = .moderate,
        increment: Double? = nil
    ) -> CuratedExerciseDefinition {
        CuratedExerciseDefinition(
            catalogID: id,
            name: name,
            primaryMuscleGroup: muscle,
            movementPattern: movement,
            requiredEquipment: equipment,
            recoveryDemand: demand,
            defaultSets: 3,
            repRange: RepRange(6, 10),
            targetRPE: demand == .low ? 6.5 : 7.5,
            restSeconds: 75,
            secondsPerSet: 40,
            transitionSeconds: 45,
            loadIncrement: increment
        )
    }
}
