import Foundation

/// Pure, deterministic workout planning. It performs no I/O and has no dependency on an LLM.
struct WorkoutPlanningEngine: Sendable {
    static let currentPlannerVersion = 1

    let plannerVersion: Int

    init(plannerVersion: Int = WorkoutPlanningEngine.currentPlannerVersion) {
        self.plannerVersion = plannerVersion
    }

    func generate(
        from state: DailyTrainingState,
        curatedPool: [CuratedExerciseDefinition],
        loadUnit: LoadUnit = .pounds
    ) throws -> WorkoutPlanCandidates {
        try validateInputs(state: state, curatedPool: curatedPool)

        let envelope = RecoveryEnvelope(state: state)
        let eligible = curatedPool.filter {
            isEligible($0, state: state, envelope: envelope)
        }
        guard !eligible.isEmpty else { throw WorkoutPlanningError.noEligibleExercises }

        let viableFocuses = TrainingFocus.allCases.filter { isViableFocus($0, in: eligible) }
        let primaryFocus: TrainingFocus
        if let requested = state.constraints.preferredFocus {
            guard viableFocuses.contains(requested) else {
                throw WorkoutPlanningError.requestedFocusUnavailable(requested)
            }
            primaryFocus = requested
        } else {
            primaryFocus = try selectPrimaryFocus(from: viableFocuses, state: state)
        }

        guard let alternateFocus = selectAlternateFocus(
            excluding: primaryFocus,
            from: viableFocuses,
            state: state
        ) else {
            throw WorkoutPlanningError.insufficientFocusCoverage
        }

        let primaryBudget = state.constraints.availableMinutes
        let shorterBudget = shorterDuration(for: primaryBudget)

        let primary = try buildCandidate(
            role: .primary,
            focus: primaryFocus,
            durationLimitMinutes: primaryBudget,
            state: state,
            eligible: eligible,
            envelope: envelope,
            loadUnit: loadUnit
        )
        var shorter = try buildCandidate(
            role: .shorter,
            focus: primaryFocus,
            durationLimitMinutes: shorterBudget,
            state: state,
            eligible: eligible,
            envelope: envelope,
            loadUnit: loadUnit
        )
        if primaryBudget > 15,
           shorter.plan.expectedDurationMinutes >= primary.plan.expectedDurationMinutes {
            // Highly constrained pools can leave only two valid exercises, and
            // normal rounding may give both options the same set count. Reduce
            // only that edge case instead of making every shorter plan too brief.
            shorter = try buildCandidate(
                role: .shorter,
                focus: primaryFocus,
                durationLimitMinutes: shorterBudget,
                state: state,
                eligible: eligible,
                envelope: envelope,
                loadUnit: loadUnit,
                shorterVolumeScale: 0.5
            )
        }
        guard primaryBudget == 15
                || shorter.plan.expectedDurationMinutes < primary.plan.expectedDurationMinutes else {
            throw WorkoutPlanningError.unableToBuildCandidate(.shorter)
        }
        let alternate = try buildCandidate(
            role: .alternateFocus,
            focus: alternateFocus,
            durationLimitMinutes: primaryBudget,
            state: state,
            eligible: eligible,
            envelope: envelope,
            loadUnit: loadUnit
        )

        let result = WorkoutPlanCandidates(
            primary: primary,
            shorter: shorter,
            alternateFocus: alternate
        )
        let issues = validationIssues(for: result, state: state, curatedPool: curatedPool)
        guard issues.isEmpty else { throw WorkoutPlanningError.validationFailed(issues) }
        return result
    }

    func validate(
        _ candidates: WorkoutPlanCandidates,
        against state: DailyTrainingState,
        curatedPool: [CuratedExerciseDefinition]
    ) throws {
        try validateInputs(state: state, curatedPool: curatedPool)
        let issues = validationIssues(for: candidates, state: state, curatedPool: curatedPool)
        guard issues.isEmpty else { throw WorkoutPlanningError.validationFailed(issues) }
    }

    func validationIssues(
        for candidates: WorkoutPlanCandidates,
        state: DailyTrainingState,
        curatedPool: [CuratedExerciseDefinition]
    ) -> [WorkoutPlanValidationIssue] {
        var issues: [WorkoutPlanValidationIssue] = []
        if candidates.primary.role != .primary {
            issues.append(.invalidCandidateRole(expected: .primary, actual: candidates.primary.role))
        }
        if candidates.shorter.role != .shorter {
            issues.append(.invalidCandidateRole(expected: .shorter, actual: candidates.shorter.role))
        }
        if candidates.alternateFocus.role != .alternateFocus {
            issues.append(.invalidCandidateRole(expected: .alternateFocus, actual: candidates.alternateFocus.role))
        }
        if candidates.primary.plan.focus == candidates.alternateFocus.plan.focus {
            issues.append(.alternateFocusMatchesPrimary)
        }
        for candidate in candidates.all {
            issues.append(contentsOf: validationIssues(
                for: candidate.plan,
                state: state,
                curatedPool: curatedPool
            ))
        }
        return issues
    }

    func validationIssues(
        for plan: WorkoutPlan,
        state: DailyTrainingState,
        curatedPool: [CuratedExerciseDefinition]
    ) -> [WorkoutPlanValidationIssue] {
        var issues: [WorkoutPlanValidationIssue] = []
        var definitions: [String: CuratedExerciseDefinition] = [:]
        for definition in curatedPool where definitions[definition.catalogID] == nil {
            definitions[definition.catalogID] = definition
        }
        let envelope = RecoveryEnvelope(state: state)

        if plan.stateID != state.stateID {
            issues.append(.staleState(expected: state.stateID, actual: plan.stateID))
        }
        if plan.plannerVersion != plannerVersion {
            issues.append(.unsupportedPlannerVersion(expected: plannerVersion, actual: plan.plannerVersion))
        }
        if !(15...180).contains(plan.durationLimitMinutes) {
            issues.append(.invalidDurationLimit(plan.durationLimitMinutes))
        }
        if plan.durationLimitMinutes > state.constraints.availableMinutes {
            issues.append(.durationLimitExceedsAvailable(
                limit: plan.durationLimitMinutes,
                available: state.constraints.availableMinutes
            ))
        }
        if plan.exercises.isEmpty {
            issues.append(.emptyWorkout)
        }
        if plan.focus == .fullBody, !plan.exercises.isEmpty {
            let hasUpperBody = plan.exercises.contains { $0.movementPattern.focus == .upperBody }
            let hasLowerBody = plan.exercises.contains { $0.movementPattern.focus == .lowerBody }
            if !hasUpperBody || !hasLowerBody {
                issues.append(.fullBodyBalanceMissing)
            }
        }

        let calculatedSeconds = plan.exercises.reduce(0) { $0 + $1.estimatedDurationSeconds }
        let calculatedMinutes = roundedUpMinutes(calculatedSeconds)
        if calculatedMinutes > plan.durationLimitMinutes {
            issues.append(.durationExceeded(expected: calculatedMinutes, limit: plan.durationLimitMinutes))
        }
        if calculatedMinutes != plan.expectedDurationMinutes {
            issues.append(.durationMismatch(stored: plan.expectedDurationMinutes, calculated: calculatedMinutes))
        }

        var seen: Set<String> = []
        for prescription in plan.exercises {
            guard seen.insert(prescription.catalogID).inserted else {
                issues.append(.duplicateExercise(prescription.catalogID))
                continue
            }
            guard let definition = definitions[prescription.catalogID] else {
                issues.append(.unknownExercise(prescription.catalogID))
                continue
            }
            let goalStyle = goalPrescription(
                for: definition,
                goal: state.constraints.goal
            )
            if state.constraints.excludedExerciseIDs.contains(prescription.catalogID) {
                issues.append(.excludedExercise(prescription.catalogID))
            }
            if state.constraints.excludedMovementPatterns.contains(prescription.movementPattern) {
                issues.append(.excludedMovement(prescription.movementPattern))
            }
            for equipment in definition.requiredEquipment.sorted(by: { $0.rawValue < $1.rawValue })
            where !state.constraints.equipmentProfile.supports([equipment]) {
                issues.append(.unavailableEquipment(exerciseID: prescription.catalogID, equipment: equipment))
            }
            if !definition.supportedGoals.contains(state.constraints.goal) {
                issues.append(.unsupportedGoal(exerciseID: prescription.catalogID, goal: state.constraints.goal))
            }
            if plan.focus != .fullBody,
               !(plan.focus.includes(definition.primaryMuscleGroup)
                    && (definition.movementPattern.focus == plan.focus || definition.movementPattern == .core)) {
                issues.append(.exerciseOutsideFocus(exerciseID: prescription.catalogID, focus: plan.focus))
            }
            if prescription.name != definition.name
                || prescription.primaryMuscleGroup != definition.primaryMuscleGroup
                || prescription.movementPattern != definition.movementPattern
                || prescription.requiredEquipment != definition.requiredEquipment
                || prescription.repetitions != goalStyle.repRange
                || prescription.restSeconds != goalStyle.restSeconds
                || prescription.secondsPerSet != definition.secondsPerSet
                || prescription.transitionSeconds != definition.transitionSeconds {
                issues.append(.catalogMetadataMismatch(prescription.catalogID))
            }
            if definition.recoveryDemand > envelope.maximumDemand {
                issues.append(.recoveryDemandExceeded(prescription.catalogID))
            }
            if !(1...6).contains(prescription.workingSets) {
                issues.append(.invalidSets(exerciseID: prescription.catalogID, sets: prescription.workingSets))
            }
            let maximumSets = max(1, min(
                6,
                Int((Double(goalStyle.defaultSets) * envelope.volumeMultiplier).rounded())
            ))
            if prescription.workingSets > maximumSets {
                issues.append(.volumeEnvelopeExceeded(
                    exerciseID: prescription.catalogID,
                    sets: prescription.workingSets,
                    maximum: maximumSets
                ))
            }
            if prescription.repetitions.lowerBound < 1
                || prescription.repetitions.upperBound > 50
                || prescription.repetitions.lowerBound > prescription.repetitions.upperBound {
                issues.append(.invalidRepetitions(exerciseID: prescription.catalogID))
            }
            if prescription.targetRPE < 4
                || prescription.targetRPE > min(envelope.maximumRPE, definition.targetRPE) {
                issues.append(.invalidRPE(
                    exerciseID: prescription.catalogID,
                    rpe: prescription.targetRPE,
                    maximum: envelope.maximumRPE
                ))
            }
            if prescription.workingLoad != state.training.history(for: prescription.catalogID)?.lastWorkingLoad {
                issues.append(.unsupportedWorkingLoad(prescription.catalogID))
            }
            if let progression = prescription.progressionSuggestion {
                if !progression.requiresConfirmation {
                    issues.append(.unconfirmedProgression(prescription.catalogID))
                }
                let history = state.training.history(for: prescription.catalogID)
                if !envelope.allowsProgression
                    || history?.progressionEligible != true {
                    issues.append(.ineligibleProgression(prescription.catalogID))
                }
            }
        }
        return issues
    }

    private let minimumExerciseCount = 2

    private func validateInputs(
        state: DailyTrainingState,
        curatedPool: [CuratedExerciseDefinition]
    ) throws {
        guard state.schemaVersion == DailyTrainingState.currentSchemaVersion else {
            throw WorkoutPlanningError.unsupportedStateSchema(state.schemaVersion)
        }
        guard (15...180).contains(state.constraints.availableMinutes) else {
            throw WorkoutPlanningError.invalidAvailableMinutes(state.constraints.availableMinutes)
        }
        if let score = state.recovery.readinessScore, !(0...100).contains(score) {
            throw WorkoutPlanningError.invalidRecoveryScore(score)
        }
        guard !curatedPool.isEmpty else { throw WorkoutPlanningError.emptyCuratedPool }

        var identifiers: Set<String> = []
        for exercise in curatedPool {
            guard identifiers.insert(exercise.catalogID).inserted else {
                throw WorkoutPlanningError.duplicateCatalogID(exercise.catalogID)
            }
            guard !exercise.catalogID.isEmpty,
                  !exercise.name.isEmpty,
                  (1...6).contains(exercise.defaultSets),
                  exercise.repRange.lowerBound >= 1,
                  exercise.repRange.upperBound <= 50,
                  exercise.repRange.lowerBound <= exercise.repRange.upperBound,
                  !exercise.requiredEquipment.isEmpty,
                  !exercise.supportedGoals.isEmpty,
                  (4...10).contains(exercise.targetRPE),
                  exercise.restSeconds >= 0,
                  exercise.secondsPerSet > 0,
                  exercise.transitionSeconds >= 0 else {
                throw WorkoutPlanningError.invalidCuratedExercise(exercise.catalogID)
            }
        }
    }

    private func isEligible(
        _ exercise: CuratedExerciseDefinition,
        state: DailyTrainingState,
        envelope: RecoveryEnvelope
    ) -> Bool {
        exercise.supportedGoals.contains(state.constraints.goal)
            && state.constraints.equipmentProfile.supports(exercise.requiredEquipment)
            && !state.constraints.excludedExerciseIDs.contains(exercise.catalogID)
            && !state.constraints.excludedMovementPatterns.contains(exercise.movementPattern)
            && exercise.recoveryDemand <= envelope.maximumDemand
    }

    private func selectPrimaryFocus(
        from viableFocuses: [TrainingFocus],
        state: DailyTrainingState
    ) throws -> TrainingFocus {
        guard !viableFocuses.isEmpty else { throw WorkoutPlanningError.noEligibleExercises }
        if state.training.sessionsLast7Days == 0, viableFocuses.contains(.fullBody) {
            return .fullBody
        }
        return viableFocuses.sorted {
            let left = focusScore($0, state: state)
            let right = focusScore($1, state: state)
            if left == right { return focusOrder($0) < focusOrder($1) }
            return left > right
        }.first!
    }

    private func selectAlternateFocus(
        excluding primary: TrainingFocus,
        from viableFocuses: [TrainingFocus],
        state: DailyTrainingState
    ) -> TrainingFocus? {
        viableFocuses
            .filter { $0 != primary }
            .sorted {
                let left = focusScore($0, state: state)
                let right = focusScore($1, state: state)
                if left == right { return focusOrder($0) < focusOrder($1) }
                return left > right
            }
            .first
    }

    private func focusScore(_ focus: TrainingFocus, state: DailyTrainingState) -> Int {
        let relevantMuscles = muscles(for: focus)
        let recordedRecency = relevantMuscles.compactMap(state.training.daysSinceTraining)
        let recencyScore = recordedRecency.isEmpty
            ? 30
            : recordedRecency.reduce(0, +) * 10 / recordedRecency.count

        let relevantPatterns = patterns(for: focus)
        let deficitScore = relevantPatterns.reduce(0) {
            $0 + (state.training.load(for: $1)?.targetDeficit ?? 0)
        }
        let repetitionPenalty = state.training.mostRecentFocus == focus ? 20 : 0
        let fullBodyPenalty = focus == .fullBody && state.training.sessionsLast7Days > 0 ? 4 : 0
        return recencyScore + deficitScore * 3 - repetitionPenalty - fullBodyPenalty
    }

    private func buildCandidate(
        role: WorkoutCandidateRole,
        focus: TrainingFocus,
        durationLimitMinutes: Int,
        state: DailyTrainingState,
        eligible: [CuratedExerciseDefinition],
        envelope: RecoveryEnvelope,
        loadUnit: LoadUnit,
        shorterVolumeScale: Double = 0.8
    ) throws -> WorkoutPlanCandidate {
        let focused = eligibleExercises(for: focus, from: eligible)
        let ordered = focused.sorted {
            let left = exerciseScore($0, focus: focus, state: state)
            let right = exerciseScore($1, focus: focus, state: state)
            if left == right {
                let leftPattern = patternPriority($0.movementPattern, focus: focus)
                let rightPattern = patternPriority($1.movementPattern, focus: focus)
                if leftPattern == rightPattern { return $0.catalogID < $1.catalogID }
                return leftPattern < rightPattern
            }
            return left > right
        }

        let setMultiplier = role == .shorter
            ? envelope.volumeMultiplier * shorterVolumeScale
            : envelope.volumeMultiplier
        let exerciseLimit = role == .shorter
            ? max(minimumExerciseCount, envelope.maximumExercises - 2)
            : envelope.maximumExercises
        var prescriptions: [ExercisePrescription] = []
        var usedPatterns: Set<MovementPattern> = []

        // Pattern diversity comes before adding a second exercise from the same pattern.
        let diversityPass = ordered.filter { exercise in
            if usedPatterns.contains(exercise.movementPattern) { return false }
            usedPatterns.insert(exercise.movementPattern)
            return true
        }
        let remaining = ordered.filter { definition in
            !diversityPass.contains(where: { $0.catalogID == definition.catalogID })
        }

        var selectionOrder = diversityPass + remaining
        if focus == .fullBody,
           let upperAnchor = selectionOrder.first(where: { $0.movementPattern.focus == .upperBody }),
           let lowerAnchor = selectionOrder.first(where: { $0.movementPattern.focus == .lowerBody }) {
            let anchorIDs: Set<String> = [upperAnchor.catalogID, lowerAnchor.catalogID]
            selectionOrder = [upperAnchor, lowerAnchor]
                + selectionOrder.filter { !anchorIDs.contains($0.catalogID) }
        }

        for definition in selectionOrder {
            let prescription = prescription(
                for: definition,
                state: state,
                envelope: envelope,
                setMultiplier: setMultiplier,
                loadUnit: loadUnit
            )
            let proposedSeconds = prescriptions.reduce(0) { $0 + $1.estimatedDurationSeconds }
                + prescription.estimatedDurationSeconds
            guard proposedSeconds <= durationLimitMinutes * 60 else { continue }
            prescriptions.append(prescription)
            if prescriptions.count == exerciseLimit { break }
        }

        guard prescriptions.count >= minimumExerciseCount else {
            throw WorkoutPlanningError.unableToBuildCandidate(role)
        }

        let expectedMinutes = roundedUpMinutes(
            prescriptions.reduce(0) { $0 + $1.estimatedDurationSeconds }
        )
        let reasons = reasonCodes(
            role: role,
            focus: focus,
            state: state,
            prescriptions: prescriptions
        )
        let plan = WorkoutPlan(
            id: planID(state: state, role: role),
            stateID: state.stateID,
            plannerVersion: plannerVersion,
            mode: envelope.mode,
            title: workoutTitle(
                focus: focus,
                goal: state.constraints.goal,
                mode: envelope.mode
            ),
            focus: focus,
            durationLimitMinutes: durationLimitMinutes,
            expectedDurationMinutes: expectedMinutes,
            exercises: prescriptions,
            reasonCodes: reasons
        )
        return WorkoutPlanCandidate(
            role: role,
            plan: plan,
            plannerScore: focusScore(focus, state: state)
        )
    }

    private func prescription(
        for exercise: CuratedExerciseDefinition,
        state: DailyTrainingState,
        envelope: RecoveryEnvelope,
        setMultiplier: Double,
        loadUnit: LoadUnit
    ) -> ExercisePrescription {
        let goalStyle = goalPrescription(for: exercise, goal: state.constraints.goal)
        let sets = max(1, min(6, Int((Double(goalStyle.defaultSets) * setMultiplier).rounded())))
        let history = state.training.history(for: exercise.catalogID)
        return ExercisePrescription(
            catalogID: exercise.catalogID,
            name: exercise.name,
            primaryMuscleGroup: exercise.primaryMuscleGroup,
            movementPattern: exercise.movementPattern,
            requiredEquipment: exercise.requiredEquipment,
            workingSets: sets,
            repetitions: goalStyle.repRange,
            workingLoad: history?.lastWorkingLoad,
            targetRPE: min(exercise.targetRPE, envelope.maximumRPE),
            restSeconds: goalStyle.restSeconds,
            secondsPerSet: exercise.secondsPerSet,
            transitionSeconds: exercise.transitionSeconds,
            progressionSuggestion: progressionSuggestion(
                for: exercise,
                history: history,
                state: state,
                envelope: envelope,
                repRange: goalStyle.repRange,
                unit: loadUnit
            )
        )
    }

    private func progressionSuggestion(
        for exercise: CuratedExerciseDefinition,
        history: ExerciseTrainingHistory?,
        state: DailyTrainingState,
        envelope: RecoveryEnvelope,
        repRange: RepRange,
        unit: LoadUnit
    ) -> ProgressionSuggestion? {
        guard envelope.allowsProgression,
              let history,
              history.progressionEligible,
              let completedRepetitions = history.lastCompletedReps,
              completedRepetitions >= repRange.lowerBound else { return nil }

        if let load = history.lastWorkingLoad, load > 0, let increment = exercise.loadIncrement, increment > 0 {
            return ProgressionSuggestion(
                kind: .load,
                currentLoad: load,
                suggestedLoad: load + increment,
                currentRepetitions: completedRepetitions,
                suggestedRepetitions: completedRepetitions,
                unit: unit,
                requiresConfirmation: true
            )
        }
        if completedRepetitions < repRange.upperBound {
            return ProgressionSuggestion(
                kind: .repetitions,
                currentLoad: history.lastWorkingLoad,
                suggestedLoad: history.lastWorkingLoad,
                currentRepetitions: completedRepetitions,
                suggestedRepetitions: completedRepetitions + 1,
                unit: unit,
                requiresConfirmation: true
            )
        }
        return nil
    }

    private func reasonCodes(
        role: WorkoutCandidateRole,
        focus: TrainingFocus,
        state: DailyTrainingState,
        prescriptions: [ExercisePrescription]
    ) -> [WorkoutPlanReasonCode] {
        var reasons: [WorkoutPlanReasonCode] = []
        let effectiveBand = effectiveReadinessBand(for: state)
        switch effectiveBand {
        case .high: reasons.append(.highReadiness)
        case .moderate: reasons.append(.moderateReadiness)
        case .low: reasons.append(.lowReadiness)
        }
        if state.dataQuality.confidence == .low,
           state.dataQuality.availability != .unavailable,
           !state.dataQuality.isStale {
            reasons.append(.limitedRecoveryConfidence)
        }
        if state.dataQuality.availability == .unavailable {
            reasons.append(.healthDataUnavailable)
        }
        if let sleepDelta = state.recovery.sleepDeltaFromTargetMinutes {
            reasons.append(sleepDelta >= -30 ? .sleepNearTarget : .sleepBelowTarget)
        }
        if let hrv = state.recovery.heartRateVariabilityVsBaseline {
            reasons.append(hrv >= -0.08 ? .heartRateVariabilityNearBaseline : .heartRateVariabilityBelowBaseline)
        }
        if let restingDelta = state.recovery.restingHeartRateDeltaBPM {
            reasons.append(restingDelta <= 3 ? .restingHeartRateNearBaseline : .restingHeartRateElevated)
        }
        if state.constraints.preferredFocus != nil {
            reasons.append(.userRequestedFocus)
        } else {
            switch focus {
            case .upperBody: reasons.append(.upperBodyDue)
            case .lowerBody: reasons.append(.lowerBodyDue)
            case .fullBody: reasons.append(.balancedFullBody)
            }
        }
        let familiar = state.training.familiarExerciseIDs
        if prescriptions.contains(where: { familiar.contains($0.catalogID) }) {
            reasons.append(.familiarExercisesPrioritized)
        }
        if let load = state.training.loadVersus28DayAverage, load > 1.2 {
            reasons.append(.weeklyLoadReduced)
        }
        if state.training.sessionsLast7Days >= state.constraints.targetSessionsPerWeek {
            reasons.append(.weeklyTargetReached)
        }
        reasons.append(.equipmentMatched)
        reasons.append(.durationMatched)
        switch role {
        case .primary: break
        case .shorter: reasons.append(.shorterOption)
        case .alternateFocus: reasons.append(.alternateFocus)
        }
        return reasons
    }

    private func eligibleExercises(
        for focus: TrainingFocus,
        from exercises: [CuratedExerciseDefinition]
    ) -> [CuratedExerciseDefinition] {
        switch focus {
        case .upperBody, .lowerBody:
            return exercises.filter {
                focus.includes($0.primaryMuscleGroup)
                    && ($0.movementPattern.focus == focus || $0.movementPattern == .core)
            }
        case .fullBody:
            return exercises
        }
    }

    private func isViableFocus(
        _ focus: TrainingFocus,
        in exercises: [CuratedExerciseDefinition]
    ) -> Bool {
        let focused = eligibleExercises(for: focus, from: exercises)
        guard focused.count >= minimumExerciseCount else { return false }
        guard focus == .fullBody else { return true }

        let containsUpperBody = focused.contains {
            $0.movementPattern.focus == .upperBody
        }
        let containsLowerBody = focused.contains {
            $0.movementPattern.focus == .lowerBody
        }
        return containsUpperBody && containsLowerBody
    }

    private func exerciseScore(
        _ exercise: CuratedExerciseDefinition,
        focus: TrainingFocus,
        state: DailyTrainingState
    ) -> Int {
        var score = 0
        if state.constraints.preferredExerciseIDs.contains(exercise.catalogID) { score += 1_000 }
        if state.training.familiarExerciseIDs.contains(exercise.catalogID) { score += 500 }
        score += (state.training.load(for: exercise.movementPattern)?.targetDeficit ?? 0) * 20
        score += (state.training.daysSinceTraining(exercise.primaryMuscleGroup) ?? 3) * 5
        // Within the recovery envelope, lead with the most productive compound
        // option instead of letting low-demand accessories win alphabetical ties.
        score += exercise.recoveryDemand.rawValue * 4
        score -= patternPriority(exercise.movementPattern, focus: focus)
        return score
    }

    private func shorterDuration(for minutes: Int) -> Int {
        guard minutes > 15 else { return 15 }
        return max(15, min(minutes - 10, Int((Double(minutes) * 0.7).rounded())))
    }

    private func goalPrescription(
        for exercise: CuratedExerciseDefinition,
        goal: TrainingGoal
    ) -> GoalPrescriptionStyle {
        let isAccessory = [
            MovementPattern.elbowFlexion,
            .elbowExtension,
            .calfRaise,
            .core,
            .isolation
        ].contains(exercise.movementPattern)

        return switch goal {
        case .strengthAndMuscle:
            GoalPrescriptionStyle(
                defaultSets: exercise.defaultSets,
                repRange: exercise.repRange,
                restSeconds: exercise.restSeconds
            )
        case .strength:
            GoalPrescriptionStyle(
                defaultSets: min(exercise.defaultSets + (isAccessory ? 0 : 1), 6),
                repRange: isAccessory ? RepRange(8, 12) : RepRange(4, 6),
                restSeconds: max(exercise.restSeconds, isAccessory ? 90 : 150)
            )
        case .muscleGain:
            GoalPrescriptionStyle(
                defaultSets: min(exercise.defaultSets + 1, 6),
                repRange: isAccessory ? RepRange(10, 15) : RepRange(8, 12),
                restSeconds: min(max(exercise.restSeconds, 75), 90)
            )
        }
    }

    private func planID(state: DailyTrainingState, role: WorkoutCandidateRole) -> String {
        "\(state.stateID.uuidString.lowercased()):v\(plannerVersion):\(role.rawValue)"
    }

    private func workoutTitle(
        focus: TrainingFocus,
        goal: TrainingGoal,
        mode: WorkoutPlanningMode
    ) -> String {
        if mode == .reduced { return "\(focus.title) Reduced Session" }
        return switch goal {
        case .strengthAndMuscle: "\(focus.title) Strength + Muscle"
        case .strength: "\(focus.title) Strength"
        case .muscleGain: "\(focus.title) Muscle"
        }
    }

    private func roundedUpMinutes(_ seconds: Int) -> Int {
        max(1, (seconds + 59) / 60)
    }

    private func focusOrder(_ focus: TrainingFocus) -> Int {
        switch focus {
        case .upperBody: 0
        case .lowerBody: 1
        case .fullBody: 2
        }
    }

    private func patternPriority(_ pattern: MovementPattern, focus: TrainingFocus) -> Int {
        let ordered: [MovementPattern]
        switch focus {
        case .upperBody:
            ordered = [.horizontalPush, .horizontalPull, .verticalPush, .verticalPull, .elbowFlexion, .elbowExtension, .core, .carry, .isolation]
        case .lowerBody:
            ordered = [.squat, .hinge, .singleLeg, .calfRaise, .core, .carry, .isolation]
        case .fullBody:
            ordered = [.squat, .horizontalPush, .horizontalPull, .hinge, .verticalPush, .verticalPull, .singleLeg, .core, .carry, .isolation, .elbowFlexion, .elbowExtension, .calfRaise]
        }
        return ordered.firstIndex(of: pattern) ?? ordered.count
    }

    private func muscles(for focus: TrainingFocus) -> [MuscleGroup] {
        switch focus {
        case .upperBody: [.chest, .back, .shoulders, .arms]
        case .lowerBody: [.quads, .hamstrings, .glutes, .calves]
        case .fullBody: [.chest, .back, .shoulders, .quads, .hamstrings, .glutes]
        }
    }

    private func patterns(for focus: TrainingFocus) -> [MovementPattern] {
        switch focus {
        case .upperBody: [.horizontalPush, .horizontalPull, .verticalPush, .verticalPull]
        case .lowerBody: [.squat, .hinge, .singleLeg]
        case .fullBody: [.squat, .hinge, .horizontalPush, .horizontalPull]
        }
    }
}

private struct GoalPrescriptionStyle {
    let defaultSets: Int
    let repRange: RepRange
    let restSeconds: Int
}

private struct RecoveryEnvelope {
    let mode: WorkoutPlanningMode
    let volumeMultiplier: Double
    let maximumRPE: Double
    let maximumDemand: ExerciseRecoveryDemand
    let maximumExercises: Int
    let allowsProgression: Bool

    init(state: DailyTrainingState) {
        let easierAdjustment = state.constraints.effort == .easier
        let highLoad = (state.training.loadVersus28DayAverage ?? 1) > 1.2
        let weeklyTargetReached = state.training.sessionsLast7Days
            >= state.constraints.targetSessionsPerWeek
        let effectiveBand = effectiveReadinessBand(for: state)

        switch effectiveBand {
        case .high:
            if weeklyTargetReached {
                mode = .reduced
                volumeMultiplier = easierAdjustment ? 0.55 : 0.65
                maximumRPE = easierAdjustment ? 6.5 : 7
                maximumDemand = .moderate
                maximumExercises = 4
                allowsProgression = false
            } else {
                mode = easierAdjustment || highLoad ? .balanced : .performance
                volumeMultiplier = easierAdjustment || highLoad ? 0.8 : 1
                maximumRPE = easierAdjustment ? 7 : 8.5
                maximumDemand = easierAdjustment || highLoad ? .moderate : .high
                maximumExercises = easierAdjustment ? 5 : 7
                allowsProgression = !easierAdjustment
                    && !highLoad
                    && state.dataQuality.permitsProgressionSuggestion
            }
        case .moderate:
            mode = highLoad || weeklyTargetReached ? .reduced : .balanced
            volumeMultiplier = weeklyTargetReached
                ? 0.55
                : (easierAdjustment || highLoad ? 0.65 : 0.8)
            maximumRPE = easierAdjustment || weeklyTargetReached ? 6.5 : 7.5
            maximumDemand = .moderate
            maximumExercises = easierAdjustment || highLoad || weeklyTargetReached ? 4 : 6
            allowsProgression = false
        case .low:
            mode = .reduced
            volumeMultiplier = 0.55
            maximumRPE = 6.5
            maximumDemand = .low
            maximumExercises = 4
            allowsProgression = false
        }
    }
}

/// Uses the same conservative-baseline policy as `WellnessEngine`: limited
/// confidence may preserve a low signal, but it cannot unlock a high-readiness
/// training envelope.
private func effectiveReadinessBand(for state: DailyTrainingState) -> ReadinessBand {
    if state.dataQuality.availability == .unavailable || state.dataQuality.isStale {
        return .moderate
    }
    if state.dataQuality.confidence == .low, state.recovery.readinessBand == .high {
        return .moderate
    }
    return state.recovery.readinessBand
}
