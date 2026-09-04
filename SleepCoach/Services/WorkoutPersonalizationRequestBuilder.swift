import Foundation

enum WorkoutPersonalizationBridgeError: Error, Equatable, Sendable {
    case staleCandidateState
    case invalidCandidateRole
}

/// Converts fully validated planner output into the smaller, prescription-free
/// boundary accepted by `FoundationModelWorkoutPersonalizer`.
struct WorkoutPersonalizationRequestBuilder: Sendable {
    func makeRequest(
        state: DailyTrainingState,
        candidates: WorkoutPlanCandidates,
        aiConsentGranted: Bool,
        preference: String? = nil
    ) throws -> WorkoutPersonalizationRequest {
        guard candidates.all.allSatisfy({ $0.plan.stateID == state.stateID }) else {
            throw WorkoutPersonalizationBridgeError.staleCandidateState
        }
        guard candidates.primary.role == .primary,
              candidates.shorter.role == .shorter,
              candidates.alternateFocus.role == .alternateFocus else {
            throw WorkoutPersonalizationBridgeError.invalidCandidateRole
        }

        let trimmedPreference = preference?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPreference = trimmedPreference?.isEmpty == false ? trimmedPreference : nil
        let hasPreference = normalizedPreference != nil
        let reasonCodes = Set(candidates.all.flatMap { $0.plan.reasonCodes })
        var evidence = try WorkoutPlanReasonCode.allCases
            .filter(reasonCodes.contains)
            .map { reason in
                try WorkoutPersonalizationEvidence(
                    code: personalizationReason(for: reason),
                    provenance: provenance(for: reason),
                    statement: evidenceStatement(for: reason, state: state)
                )
            }
        if hasPreference {
            evidence.append(try WorkoutPersonalizationEvidence(
                code: .userPreference,
                provenance: .userEntered,
                statement: "The user provided an optional preference for ranking these candidates."
            ))
        }

        let summaries = try candidates.all.map { candidate in
            var supportedReasons = candidate.plan.reasonCodes.map(personalizationReason)
            if hasPreference { supportedReasons.append(.userPreference) }
            return try ValidatedWorkoutCandidateSummary(
                identifier: candidate.plan.id,
                slot: personalizationSlot(for: candidate.role),
                title: candidate.plan.title,
                durationMinutes: candidate.plan.expectedDurationMinutes,
                focus: candidate.plan.focus.title,
                rankingSummary: rankingSummary(for: candidate),
                supportedReasonCodes: orderedUnique(supportedReasons),
                deterministicExplanation: deterministicExplanation(
                    for: candidate,
                    equipmentProfileName: state.constraints.equipmentProfile.name
                )
            )
        }

        return try WorkoutPersonalizationRequest(
            stateID: state.stateID,
            candidates: summaries,
            evidence: evidence,
            aiConsentGranted: aiConsentGranted,
            preference: normalizedPreference
        )
    }

    private func personalizationSlot(
        for role: WorkoutCandidateRole
    ) -> WorkoutPersonalizationCandidateSlot {
        switch role {
        case .primary: .primary
        case .shorter: .shorter
        case .alternateFocus: .alternateFocus
        }
    }

    private func personalizationReason(
        for reason: WorkoutPlanReasonCode
    ) -> WorkoutPersonalizationReasonCode {
        switch reason {
        case .highReadiness: .highReadiness
        case .moderateReadiness: .moderateReadiness
        case .lowReadiness: .lowReadiness
        case .limitedRecoveryConfidence: .limitedRecoveryConfidence
        case .healthDataUnavailable: .healthDataUnavailable
        case .sleepNearTarget: .sleepNearTarget
        case .sleepBelowTarget: .sleepBelowTarget
        case .heartRateVariabilityNearBaseline: .heartRateVariabilityNearBaseline
        case .heartRateVariabilityBelowBaseline: .heartRateVariabilityBelowBaseline
        case .restingHeartRateNearBaseline: .restingHeartRateNearBaseline
        case .restingHeartRateElevated: .restingHeartRateElevated
        case .upperBodyDue: .upperBodyDue
        case .lowerBodyDue: .lowerBodyDue
        case .balancedFullBody: .balancedFullBody
        case .userRequestedFocus: .userRequestedFocus
        case .familiarExercisesPrioritized: .familiarExercisesPrioritized
        case .equipmentMatched: .equipmentMatched
        case .durationMatched: .durationMatched
        case .weeklyLoadReduced: .weeklyLoadReduced
        case .weeklyTargetReached: .weeklyTargetReached
        case .shorterOption: .shorterOption
        case .alternateFocus: .alternateFocus
        }
    }

    private func provenance(
        for reason: WorkoutPlanReasonCode
    ) -> WorkoutPersonalizationEvidenceProvenance {
        switch reason {
        case .highReadiness, .moderateReadiness, .lowReadiness, .limitedRecoveryConfidence,
             .healthDataUnavailable,
             .sleepNearTarget, .sleepBelowTarget, .heartRateVariabilityNearBaseline,
             .heartRateVariabilityBelowBaseline, .restingHeartRateNearBaseline,
             .restingHeartRateElevated, .weeklyLoadReduced, .weeklyTargetReached:
            .calculated
        case .upperBodyDue, .lowerBodyDue, .balancedFullBody:
            .calculated
        case .familiarExercisesPrioritized:
            .measured
        case .userRequestedFocus:
            .userEntered
        case .equipmentMatched, .durationMatched, .shorterOption, .alternateFocus:
            .calculated
        }
    }

    private func evidenceStatement(
        for reason: WorkoutPlanReasonCode,
        state: DailyTrainingState
    ) -> String {
        switch reason {
        case .highReadiness:
            "The calculated readiness band is high."
        case .moderateReadiness:
            "The calculated readiness band is moderate."
        case .lowReadiness:
            "The calculated readiness band is low, so the planner reduced training demands."
        case .limitedRecoveryConfidence:
            "Recovery confidence is limited, so the planner used a conservative training envelope."
        case .healthDataUnavailable:
            "Health data is unavailable, so the planner used training preferences and history."
        case .sleepNearTarget:
            "Recorded sleep met the target or was no more than 30 minutes below it."
        case .sleepBelowTarget:
            sleepBelowTargetStatement(state: state)
        case .heartRateVariabilityNearBaseline:
            biometricStatement(
                name: "HRV",
                difference: state.recovery.heartRateVariabilityVsBaseline,
                nearBaseline: true
            )
        case .heartRateVariabilityBelowBaseline:
            biometricStatement(
                name: "HRV",
                difference: state.recovery.heartRateVariabilityVsBaseline,
                nearBaseline: false
            )
        case .restingHeartRateNearBaseline:
            restingHeartRateStatement(state: state, nearBaseline: true)
        case .restingHeartRateElevated:
            restingHeartRateStatement(state: state, nearBaseline: false)
        case .upperBodyDue:
            "Recent local training history and weekly targets favor upper-body training."
        case .lowerBodyDue:
            "Recent local training history and weekly targets favor lower-body training."
        case .balancedFullBody:
            "A full-body session provides balanced coverage for the current rolling plan."
        case .userRequestedFocus:
            "The user selected \(state.constraints.preferredFocus?.title ?? "the proposed") focus."
        case .familiarExercisesPrioritized:
            "The candidate prioritizes exercises found in local workout history."
        case .equipmentMatched:
            "Every exercise matches the \(state.constraints.equipmentProfile.name) equipment profile."
        case .durationMatched:
            "Every candidate fits its stated workout-duration limit."
        case .weeklyLoadReduced:
            weeklyLoadStatement(state: state)
        case .weeklyTargetReached:
            "The user completed \(state.training.sessionsLast7Days) of their \(state.constraints.targetSessionsPerWeek)-session weekly target, so the planner reduced today’s training envelope."
        case .shorterOption:
            "This is the prevalidated shorter workout option."
        case .alternateFocus:
            "This is the prevalidated alternate-focus workout option."
        }
    }

    private func sleepBelowTargetStatement(state: DailyTrainingState) -> String {
        guard let delta = state.recovery.sleepDeltaFromTargetMinutes else {
            return "Recorded sleep is below the user’s sleep target."
        }
        return "Recorded sleep is \(abs(min(delta, 0))) minutes below the user’s sleep target."
    }

    private func biometricStatement(
        name: String,
        difference: Double?,
        nearBaseline: Bool
    ) -> String {
        guard let difference else {
            return "\(name) was compared with its same-source baseline."
        }
        let percentage = Int((abs(difference) * 100).rounded())
        let direction = difference < 0 ? "below" : "above"
        let threshold = nearBaseline ? "met" : "did not meet"
        return "\(name) is \(percentage)% \(direction) its same-source baseline and \(threshold) the planner’s threshold."
    }

    private func restingHeartRateStatement(
        state: DailyTrainingState,
        nearBaseline: Bool
    ) -> String {
        guard let delta = state.recovery.restingHeartRateDeltaBPM else {
            return "Resting heart rate was compared with its same-source baseline."
        }
        let roundedDelta = Int(abs(delta).rounded())
        let direction = delta < 0 ? "below" : "above"
        let threshold = nearBaseline ? "met" : "did not meet"
        return "Resting heart rate is \(roundedDelta) bpm \(direction) its baseline and \(threshold) the planner’s threshold."
    }

    private func weeklyLoadStatement(state: DailyTrainingState) -> String {
        guard let ratio = state.training.loadVersus28DayAverage else {
            return "Recent weekly training load caused the planner to reduce workout volume."
        }
        return "Recent weekly training load is \(Int((ratio * 100).rounded()))% of the prior 28-day weekly average, so volume was reduced."
    }

    private func rankingSummary(for candidate: WorkoutPlanCandidate) -> String {
        let mode: String = switch candidate.plan.mode {
        case .performance: "performance"
        case .balanced: "balanced"
        case .reduced: "reduced"
        }
        return "A \(candidate.plan.expectedDurationMinutes)-minute \(mode) \(candidate.plan.focus.title.lowercased()) session with \(candidate.plan.exercises.count) reviewed exercises."
    }

    private func deterministicExplanation(
        for candidate: WorkoutPlanCandidate,
        equipmentProfileName: String
    ) -> String {
        switch candidate.role {
        case .primary:
            "\(candidate.plan.title) fits the \(equipmentProfileName) setup and is planned for \(candidate.plan.expectedDurationMinutes) minutes."
        case .shorter:
            "\(candidate.plan.title) is the shorter validated option at \(candidate.plan.expectedDurationMinutes) minutes."
        case .alternateFocus:
            "\(candidate.plan.title) changes the training focus while keeping the equipment and time constraints."
        }
    }

    private func orderedUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }
}
