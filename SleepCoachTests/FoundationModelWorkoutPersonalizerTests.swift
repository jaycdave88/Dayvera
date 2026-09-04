import XCTest
@testable import SleepCoach

final class FoundationModelWorkoutPersonalizerTests: XCTestCase {
    func testValidGeneratedChoiceUsesOnlyTheSelectedCandidateAndEvidence() async throws {
        let runtime = PersonalizationRuntimeStub(
            generated: .init(
                candidateSlot: .shorter,
                reasonCodes: [.durationMatched, .sleepNearTarget],
                explanation: "A 30-minute upper-body session fits your available time and current sleep."
            )
        )
        let personalizer = FoundationModelWorkoutPersonalizer(
            runtime: runtime,
            resourceMonitor: PersonalizationResourceStub()
        )
        let request = try makeRequest()

        let decision = await personalizer.personalize(request)

        XCTAssertEqual(decision.stateID, request.stateID)
        XCTAssertEqual(decision.candidateIdentifier, "shorter")
        XCTAssertEqual(decision.slot, .shorter)
        XCTAssertEqual(decision.reasonCodes, [.durationMatched, .sleepNearTarget])
        XCTAssertEqual(decision.status, .personalized)
    }

    func testUnsupportedReasonCodeFallsBackToDeterministicPrimaryCandidate() async throws {
        let runtime = PersonalizationRuntimeStub(
            generated: .init(
                candidateSlot: .alternateFocus,
                reasonCodes: [.sleepNearTarget],
                explanation: "This option fits your sleep."
            )
        )
        let personalizer = FoundationModelWorkoutPersonalizer(
            runtime: runtime,
            resourceMonitor: PersonalizationResourceStub()
        )

        let decision = await personalizer.personalize(try makeRequest())

        XCTAssertEqual(decision.candidateIdentifier, "primary")
        XCTAssertEqual(decision.status, .deterministicFallback(.invalidResponse))
        XCTAssertEqual(decision.explanation, "This workout matches your goal and current signals.")
    }

    func testMedicalizedOrUnsupportedExplanationFallsBack() async throws {
        let runtime = PersonalizationRuntimeStub(
            generated: .init(
                candidateSlot: .primary,
                reasonCodes: [.userPreference],
                explanation: "This workout guarantees that your injury is safe to train."
            )
        )
        let personalizer = FoundationModelWorkoutPersonalizer(
            runtime: runtime,
            resourceMonitor: PersonalizationResourceStub()
        )

        let decision = await personalizer.personalize(try makeRequest())

        XCTAssertEqual(decision.candidateIdentifier, "primary")
        XCTAssertEqual(decision.status, .deterministicFallback(.invalidResponse))
    }

    func testInventedNumberFallsBack() async throws {
        let runtime = PersonalizationRuntimeStub(
            generated: .init(
                candidateSlot: .shorter,
                reasonCodes: [.durationMatched],
                explanation: "This 25-minute option fits your available time."
            )
        )
        let personalizer = FoundationModelWorkoutPersonalizer(
            runtime: runtime,
            resourceMonitor: PersonalizationResourceStub()
        )

        let decision = await personalizer.personalize(try makeRequest())

        XCTAssertEqual(decision.status, .deterministicFallback(.invalidResponse))
    }

    func testConsentAndResourcePolicyBypassTheModel() async throws {
        let runtime = PersonalizationRuntimeStub(
            generated: .init(
                candidateSlot: .primary,
                reasonCodes: [.userPreference],
                explanation: "This workout matches your goal."
            )
        )
        let optedOut = FoundationModelWorkoutPersonalizer(
            runtime: runtime,
            resourceMonitor: PersonalizationResourceStub()
        )
        let lowPower = FoundationModelWorkoutPersonalizer(
            runtime: runtime,
            resourceMonitor: PersonalizationResourceStub(isLowPowerModeEnabled: true)
        )

        let optedOutDecision = await optedOut.personalize(try makeRequest(aiConsentGranted: false))
        let lowPowerDecision = await lowPower.personalize(try makeRequest())
        let generationCount = await runtime.generationCount()

        XCTAssertEqual(optedOutDecision.status, .deterministicFallback(.consentNotGranted))
        XCTAssertEqual(lowPowerDecision.status, .deterministicFallback(.lowPowerMode))
        XCTAssertEqual(generationCount, 0)
    }

    func testUnavailableModelAndRefusalUseExplicitFallbackStatuses() async throws {
        let unavailableRuntime = PersonalizationRuntimeStub(
            availability: .appleIntelligenceNotEnabled,
            generated: .init(
                candidateSlot: .primary,
                reasonCodes: [.userPreference],
                explanation: "This workout matches your goal."
            )
        )
        let refusingRuntime = PersonalizationRuntimeStub(failure: .refused)
        let unavailable = FoundationModelWorkoutPersonalizer(
            runtime: unavailableRuntime,
            resourceMonitor: PersonalizationResourceStub()
        )
        let refusing = FoundationModelWorkoutPersonalizer(
            runtime: refusingRuntime,
            resourceMonitor: PersonalizationResourceStub()
        )

        let unavailableDecision = await unavailable.personalize(try makeRequest())
        let refusalDecision = await refusing.personalize(try makeRequest())

        XCTAssertEqual(
            unavailableDecision.status,
            .deterministicFallback(.appleIntelligenceNotEnabled)
        )
        XCTAssertEqual(refusalDecision.status, .deterministicFallback(.refused))
    }

    func testActorSerializesConcurrentModelRequests() async throws {
        let runtime = PersonalizationRuntimeStub(
            generated: .init(
                candidateSlot: .primary,
                reasonCodes: [.userPreference],
                explanation: "This workout matches your goal."
            ),
            delayNanoseconds: 50_000_000
        )
        let personalizer = FoundationModelWorkoutPersonalizer(
            runtime: runtime,
            resourceMonitor: PersonalizationResourceStub()
        )
        let request = try makeRequest()

        async let first = personalizer.personalize(request)
        async let second = personalizer.personalize(request)
        _ = await (first, second)
        let maximumConcurrent = await runtime.maximumConcurrentGenerations()
        let generationCount = await runtime.generationCount()

        XCTAssertEqual(maximumConcurrent, 1)
        XCTAssertEqual(generationCount, 2)
    }

    func testRequestRequiresExactlyOneCandidateForEachBoundedSlot() throws {
        let valid = try makeRequest()

        XCTAssertThrowsError(
            try WorkoutPersonalizationRequest(
                stateID: valid.stateID,
                candidates: Array(valid.candidates.prefix(2)),
                evidence: valid.evidence,
                aiConsentGranted: true
            )
        ) { error in
            XCTAssertEqual(
                error as? WorkoutPersonalizationRequestError,
                .candidatesMustContainEverySlot
            )
        }
    }

    func testPlannerBridgeMapsCandidatesWithoutPassingPrescriptionsToTheAdapter() throws {
        let state = planningState()
        let plans = planCandidates(stateID: state.stateID)

        let request = try WorkoutPersonalizationRequestBuilder().makeRequest(
            state: state,
            candidates: plans,
            aiConsentGranted: true,
            preference: "Keep the session concise"
        )

        XCTAssertEqual(request.stateID, state.stateID)
        XCTAssertEqual(request.candidates.map(\.slot), [.primary, .shorter, .alternateFocus])
        XCTAssertEqual(request.candidates.map(\.identifier), ["primary-plan", "shorter-plan", "alternate-plan"])
        XCTAssertTrue(request.candidates.allSatisfy { $0.supportedReasonCodes.contains(.userPreference) })
        XCTAssertEqual(request.evidence.filter { $0.code == .userPreference }.count, 1)
        XCTAssertTrue(request.evidence.contains {
            $0.code == .equipmentMatched && $0.provenance == .calculated
        })
    }

    func testPlannerBridgeRejectsAPlanForAnOlderDailyState() throws {
        let state = planningState()
        let stalePlans = planCandidates(stateID: UUID())

        XCTAssertThrowsError(
            try WorkoutPersonalizationRequestBuilder().makeRequest(
                state: state,
                candidates: stalePlans,
                aiConsentGranted: true
            )
        ) { error in
            XCTAssertEqual(error as? WorkoutPersonalizationBridgeError, .staleCandidateState)
        }
    }

    func testPlannerBridgeExplainsWhenWeeklySessionTargetIsReached() throws {
        let state = planningState()
        let plans = planCandidates(
            stateID: state.stateID,
            additionalReasons: [.weeklyTargetReached]
        )

        let request = try WorkoutPersonalizationRequestBuilder().makeRequest(
            state: state,
            candidates: plans,
            aiConsentGranted: true
        )
        let evidence = try XCTUnwrap(
            request.evidence.first(where: { $0.code == .weeklyTargetReached })
        )

        XCTAssertEqual(evidence.provenance, .calculated)
        XCTAssertTrue(evidence.statement.contains("4 of their 4-session weekly target"))
        XCTAssertTrue(request.candidates.allSatisfy {
            $0.supportedReasonCodes.contains(.weeklyTargetReached)
        })
    }

    func testPlannerBridgeExplainsLimitedRecoveryConfidence() throws {
        let state = planningState(confidence: .low)
        let plans = planCandidates(
            stateID: state.stateID,
            additionalReasons: [.limitedRecoveryConfidence]
        )

        let request = try WorkoutPersonalizationRequestBuilder().makeRequest(
            state: state,
            candidates: plans,
            aiConsentGranted: true
        )
        let evidence = try XCTUnwrap(
            request.evidence.first(where: { $0.code == .limitedRecoveryConfidence })
        )

        XCTAssertEqual(evidence.provenance, .calculated)
        XCTAssertEqual(
            evidence.statement,
            "Recovery confidence is limited, so the planner used a conservative training envelope."
        )
        XCTAssertTrue(request.candidates.allSatisfy {
            $0.supportedReasonCodes.contains(.limitedRecoveryConfidence)
        })
    }

    private func makeRequest(aiConsentGranted: Bool = true) throws -> WorkoutPersonalizationRequest {
        let evidence = try [
            WorkoutPersonalizationEvidence(
                code: .sleepNearTarget,
                statement: "Sleep duration is close to the same-source baseline."
            ),
            WorkoutPersonalizationEvidence(
                code: .durationMatched,
                statement: "30 minutes are available."
            ),
            WorkoutPersonalizationEvidence(
                code: .equipmentMatched,
                statement: "The Full Gym equipment profile is available."
            ),
            WorkoutPersonalizationEvidence(
                code: .userPreference,
                statement: "The selected goal is strength and muscle."
            )
        ]
        let candidates = try [
            ValidatedWorkoutCandidateSummary(
                identifier: "primary",
                slot: .primary,
                title: "Upper Body Strength",
                durationMinutes: 45,
                focus: "Upper body",
                rankingSummary: "A moderate upper-body strength session.",
                supportedReasonCodes: [.userPreference, .sleepNearTarget],
                deterministicExplanation: "This workout matches your goal and current signals."
            ),
            ValidatedWorkoutCandidateSummary(
                identifier: "shorter",
                slot: .shorter,
                title: "Upper Body Express",
                durationMinutes: 30,
                focus: "Upper body",
                rankingSummary: "A shorter upper-body strength session.",
                supportedReasonCodes: [.durationMatched, .sleepNearTarget],
                deterministicExplanation: "This shorter workout fits the time available."
            ),
            ValidatedWorkoutCandidateSummary(
                identifier: "alternate",
                slot: .alternateFocus,
                title: "Full Body Technique",
                durationMinutes: 40,
                focus: "Full body",
                rankingSummary: "A moderate full-body technique session.",
                supportedReasonCodes: [.equipmentMatched, .userPreference],
                deterministicExplanation: "This alternative matches your equipment and goal."
            )
        ]
        return try WorkoutPersonalizationRequest(
            stateID: UUID(uuidString: "00000000-0000-0000-0000-000000000077")!,
            candidates: candidates,
            evidence: evidence,
            aiConsentGranted: aiConsentGranted
        )
    }

    private func planningState(confidence: DataConfidence = .high) -> DailyTrainingState {
        DailyTrainingState(
            stateID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            generatedAt: Date(timeIntervalSince1970: 1_000),
            recovery: RecoveryState(
                readinessScore: 78,
                readinessBand: .high,
                sleepMinutes: 450,
                sleepTargetMinutes: 480,
                sleepVsBaselineMinutes: -10,
                heartRateVariabilityVsBaseline: -0.03,
                restingHeartRateDeltaBPM: 1
            ),
            training: TrainingHistoryState(
                sessionsLast7Days: 4,
                weeklyTrainingEffort: 23,
                loadVersus28DayAverage: 1,
                muscleRecency: [],
                movementLoads: [],
                exerciseHistory: [],
                mostRecentFocus: .lowerBody
            ),
            constraints: WorkoutConstraints(
                availableMinutes: 45,
                equipmentProfile: .fullGym,
                preferredFocus: .upperBody
            ),
            dataQuality: RecommendationDataQuality(
                availability: .available,
                confidence: confidence,
                currentSignalCount: 3,
                baselineDayCount: 21,
                isStale: false
            )
        )
    }

    private func planCandidates(
        stateID: UUID,
        additionalReasons: [WorkoutPlanReasonCode] = []
    ) -> WorkoutPlanCandidates {
        let primary = planCandidate(
            id: "primary-plan",
            stateID: stateID,
            role: .primary,
            duration: 42,
            reasons: [.highReadiness, .sleepNearTarget, .equipmentMatched, .durationMatched]
                + additionalReasons
        )
        let shorter = planCandidate(
            id: "shorter-plan",
            stateID: stateID,
            role: .shorter,
            duration: 30,
            reasons: [.highReadiness, .equipmentMatched, .durationMatched, .shorterOption]
                + additionalReasons
        )
        let alternate = planCandidate(
            id: "alternate-plan",
            stateID: stateID,
            role: .alternateFocus,
            duration: 40,
            reasons: [.highReadiness, .equipmentMatched, .durationMatched, .alternateFocus]
                + additionalReasons
        )
        return .init(primary: primary, shorter: shorter, alternateFocus: alternate)
    }

    private func planCandidate(
        id: String,
        stateID: UUID,
        role: WorkoutCandidateRole,
        duration: Int,
        reasons: [WorkoutPlanReasonCode]
    ) -> WorkoutPlanCandidate {
        let focus: TrainingFocus = role == .alternateFocus ? .fullBody : .upperBody
        let plan = WorkoutPlan(
            id: id,
            stateID: stateID,
            plannerVersion: 1,
            mode: .balanced,
            title: focus == .fullBody ? "Full Body Strength" : "Upper Body Strength",
            focus: focus,
            durationLimitMinutes: duration,
            expectedDurationMinutes: duration,
            exercises: [],
            reasonCodes: reasons
        )
        return .init(role: role, plan: plan, plannerScore: 100)
    }
}

private struct PersonalizationResourceStub: WorkoutPersonalizationResourceMonitoring {
    let isLowPowerModeEnabled: Bool
    let thermalState: WorkoutPersonalizationThermalState

    init(
        isLowPowerModeEnabled: Bool = false,
        thermalState: WorkoutPersonalizationThermalState = .nominal
    ) {
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.thermalState = thermalState
    }

    func currentState() async -> WorkoutPersonalizationResourceState {
        .init(isLowPowerModeEnabled: isLowPowerModeEnabled, thermalState: thermalState)
    }
}

private actor PersonalizationRuntimeStub: WorkoutFoundationModelRuntime {
    private let modelAvailability: WorkoutFoundationModelAvailability
    private let generated: FoundationModelGeneratedWorkoutPersonalization?
    private let failure: WorkoutFoundationModelRuntimeFailure?
    private let delayNanoseconds: UInt64
    private var generations = 0
    private var concurrentGenerations = 0
    private var maximumConcurrent = 0

    init(
        availability: WorkoutFoundationModelAvailability = .available,
        generated: FoundationModelGeneratedWorkoutPersonalization? = nil,
        failure: WorkoutFoundationModelRuntimeFailure? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.modelAvailability = availability
        self.generated = generated
        self.failure = failure
        self.delayNanoseconds = delayNanoseconds
    }

    func availability() async -> WorkoutFoundationModelAvailability {
        modelAvailability
    }

    func generate(prompt: String) async throws -> FoundationModelGeneratedWorkoutPersonalization {
        generations += 1
        concurrentGenerations += 1
        maximumConcurrent = max(maximumConcurrent, concurrentGenerations)
        defer { concurrentGenerations -= 1 }

        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let failure { throw failure }
        return generated ?? .init(
            candidateSlot: .primary,
            reasonCodes: [.userPreference],
            explanation: "This workout matches your goal."
        )
    }

    func generationCount() -> Int { generations }
    func maximumConcurrentGenerations() -> Int { maximumConcurrent }
}
