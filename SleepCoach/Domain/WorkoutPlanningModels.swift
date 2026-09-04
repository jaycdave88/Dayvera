import Foundation

enum TrainingGoal: String, Codable, CaseIterable, Hashable, Sendable {
    case strengthAndMuscle
    case strength
    case muscleGain

    var title: String {
        switch self {
        case .strengthAndMuscle: "Strength + muscle"
        case .strength: "Strength"
        case .muscleGain: "Muscle gain"
        }
    }
}

enum TrainingFocus: String, Codable, CaseIterable, Hashable, Sendable {
    case upperBody
    case lowerBody
    case fullBody

    var title: String {
        switch self {
        case .upperBody: "Upper Body"
        case .lowerBody: "Lower Body"
        case .fullBody: "Full Body"
        }
    }

    func includes(_ muscleGroup: MuscleGroup) -> Bool {
        switch self {
        case .upperBody:
            return [.chest, .back, .shoulders, .arms, .core].contains(muscleGroup)
        case .lowerBody:
            return [.quads, .hamstrings, .glutes, .calves, .core].contains(muscleGroup)
        case .fullBody:
            return true
        }
    }
}

enum MovementPattern: String, Codable, CaseIterable, Hashable, Sendable {
    case squat
    case hinge
    case singleLeg
    case horizontalPush
    case verticalPush
    case horizontalPull
    case verticalPull
    case elbowFlexion
    case elbowExtension
    case calfRaise
    case carry
    case core
    case isolation

    var focus: TrainingFocus {
        switch self {
        case .squat, .hinge, .singleLeg, .calfRaise:
            .lowerBody
        case .horizontalPush, .verticalPush, .horizontalPull, .verticalPull, .elbowFlexion, .elbowExtension:
            .upperBody
        case .carry, .core, .isolation:
            .fullBody
        }
    }
}

enum EquipmentID: String, Codable, CaseIterable, Hashable, Sendable {
    case bodyweight
    case barbell
    case dumbbell
    case kettlebell
    case adjustableBench
    case squatRack
    case cableMachine
    case selectorizedMachine
    case pullUpBar
    case resistanceBand
    case suspensionTrainer
    case medicineBall
    case cardioMachine

    var title: String {
        switch self {
        case .bodyweight: "Bodyweight"
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbells"
        case .kettlebell: "Kettlebells"
        case .adjustableBench: "Adjustable Bench"
        case .squatRack: "Squat Rack"
        case .cableMachine: "Cable Machine"
        case .selectorizedMachine: "Strength Machines"
        case .pullUpBar: "Pull-Up Bar"
        case .resistanceBand: "Resistance Bands"
        case .suspensionTrainer: "Suspension Trainer"
        case .medicineBall: "Medicine Ball"
        case .cardioMachine: "Cardio Machine"
        }
    }
}

struct EquipmentProfileID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let fullGym = EquipmentProfileID(rawValue: "full-gym")
    static let home = EquipmentProfileID(rawValue: "home")
    static let travel = EquipmentProfileID(rawValue: "travel")
}

struct EquipmentProfile: Identifiable, Codable, Hashable, Sendable {
    let id: EquipmentProfileID
    var name: String
    var equipment: Set<EquipmentID>

    init(id: EquipmentProfileID, name: String, equipment: Set<EquipmentID>) {
        self.id = id
        self.name = name
        self.equipment = equipment.union([.bodyweight])
    }

    func supports(_ requiredEquipment: Set<EquipmentID>) -> Bool {
        requiredEquipment.isSubset(of: equipment.union([.bodyweight]))
    }

    static let fullGym = EquipmentProfile(
        id: .fullGym,
        name: "Full Gym",
        equipment: Set(EquipmentID.allCases)
    )

    static let home = EquipmentProfile(
        id: .home,
        name: "Home",
        equipment: [.bodyweight, .dumbbell, .kettlebell, .adjustableBench, .resistanceBand]
    )

    static let travel = EquipmentProfile(
        id: .travel,
        name: "Travel",
        equipment: [.bodyweight, .resistanceBand]
    )
}

enum EvidenceProvenance: String, Codable, CaseIterable, Hashable, Sendable {
    case measured
    case calculated
    case inferred
    case userEntered
}

enum EvidenceMetric: String, Codable, CaseIterable, Hashable, Sendable {
    case readiness
    case sleep
    case heartRateVariability
    case restingHeartRate
    case trainingLoad
    case trainingHistory
    case schedule
    case equipment
}

struct EvidenceItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let provenance: EvidenceProvenance
    let metric: EvidenceMetric
    let title: String
    let detail: String
    let value: Double?
    let unit: String?
    let observedAt: Date?

    init(
        id: String,
        provenance: EvidenceProvenance,
        metric: EvidenceMetric,
        title: String,
        detail: String,
        value: Double? = nil,
        unit: String? = nil,
        observedAt: Date? = nil
    ) {
        self.id = id
        self.provenance = provenance
        self.metric = metric
        self.title = title
        self.detail = detail
        self.value = value
        self.unit = unit
        self.observedAt = observedAt
    }
}

enum HealthDataAvailability: String, Codable, CaseIterable, Hashable, Sendable {
    case available
    case partial
    case unavailable
}

struct RecommendationDataQuality: Codable, Hashable, Sendable {
    let availability: HealthDataAvailability
    let confidence: DataConfidence
    let currentSignalCount: Int
    let baselineDayCount: Int
    let isStale: Bool

    var permitsProgressionSuggestion: Bool {
        availability == .available && confidence == .high && !isStale
    }
}

struct RecoveryState: Codable, Hashable, Sendable {
    let readinessScore: Int?
    let readinessBand: ReadinessBand
    let sleepMinutes: Int?
    let sleepTargetMinutes: Int?
    let sleepVsBaselineMinutes: Int?
    /// Fractional difference from baseline. For example, -0.07 is seven percent below baseline.
    let heartRateVariabilityVsBaseline: Double?
    let restingHeartRateDeltaBPM: Double?

    var sleepDeltaFromTargetMinutes: Int? {
        guard let sleepMinutes, let sleepTargetMinutes else { return nil }
        return sleepMinutes - sleepTargetMinutes
    }
}

struct MuscleTrainingRecency: Codable, Hashable, Sendable {
    let muscleGroup: MuscleGroup
    let daysAgo: Int
}

struct MovementTrainingLoad: Codable, Hashable, Sendable {
    let movementPattern: MovementPattern
    let workingSetsLast7Days: Int
    let targetWorkingSets: Int

    var targetDeficit: Int {
        max(targetWorkingSets - workingSetsLast7Days, 0)
    }
}

struct ExerciseTrainingHistory: Codable, Hashable, Sendable {
    let catalogID: String
    let completedSessions: Int
    let lastPerformedDaysAgo: Int
    let lastWorkingLoad: Double?
    let lastCompletedReps: Int?
    let lastRPE: Double?
    let progressionEligible: Bool
}

struct TrainingHistoryState: Codable, Hashable, Sendable {
    let sessionsLast7Days: Int
    let weeklyTrainingEffort: Double?
    /// Ratio compared with the prior 28-day weekly average. `1` means equal to baseline.
    let loadVersus28DayAverage: Double?
    let muscleRecency: [MuscleTrainingRecency]
    let movementLoads: [MovementTrainingLoad]
    let exerciseHistory: [ExerciseTrainingHistory]
    let mostRecentFocus: TrainingFocus?

    func daysSinceTraining(_ muscleGroup: MuscleGroup) -> Int? {
        muscleRecency.first(where: { $0.muscleGroup == muscleGroup })?.daysAgo
    }

    func load(for movementPattern: MovementPattern) -> MovementTrainingLoad? {
        movementLoads.first(where: { $0.movementPattern == movementPattern })
    }

    func history(for catalogID: String) -> ExerciseTrainingHistory? {
        exerciseHistory.first(where: { $0.catalogID == catalogID })
    }

    var familiarExerciseIDs: Set<String> {
        Set(exerciseHistory.filter { $0.completedSessions > 0 }.map(\.catalogID))
    }
}

enum PlannedEffort: String, Codable, CaseIterable, Hashable, Sendable {
    case asPlanned
    case easier
}

struct WorkoutConstraints: Codable, Hashable, Sendable {
    let availableMinutes: Int
    let goal: TrainingGoal
    let targetSessionsPerWeek: Int
    let equipmentProfile: EquipmentProfile
    let preferredFocus: TrainingFocus?
    let effort: PlannedEffort
    let preferredExerciseIDs: Set<String>
    let excludedExerciseIDs: Set<String>
    let excludedMovementPatterns: Set<MovementPattern>

    init(
        availableMinutes: Int,
        goal: TrainingGoal = .strengthAndMuscle,
        targetSessionsPerWeek: Int = 4,
        equipmentProfile: EquipmentProfile,
        preferredFocus: TrainingFocus? = nil,
        effort: PlannedEffort = .asPlanned,
        preferredExerciseIDs: Set<String> = [],
        excludedExerciseIDs: Set<String> = [],
        excludedMovementPatterns: Set<MovementPattern> = []
    ) {
        self.availableMinutes = availableMinutes
        self.goal = goal
        self.targetSessionsPerWeek = min(max(targetSessionsPerWeek, 1), 7)
        self.equipmentProfile = equipmentProfile
        self.preferredFocus = preferredFocus
        self.effort = effort
        self.preferredExerciseIDs = preferredExerciseIDs
        self.excludedExerciseIDs = excludedExerciseIDs
        self.excludedMovementPatterns = excludedMovementPatterns
    }
}

struct DailyTrainingState: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let stateID: UUID
    let generatedAt: Date
    let recovery: RecoveryState
    let training: TrainingHistoryState
    let constraints: WorkoutConstraints
    let dataQuality: RecommendationDataQuality
    let evidence: [EvidenceItem]

    init(
        schemaVersion: Int = DailyTrainingState.currentSchemaVersion,
        stateID: UUID = UUID(),
        generatedAt: Date,
        recovery: RecoveryState,
        training: TrainingHistoryState,
        constraints: WorkoutConstraints,
        dataQuality: RecommendationDataQuality,
        evidence: [EvidenceItem] = []
    ) {
        self.schemaVersion = schemaVersion
        self.stateID = stateID
        self.generatedAt = generatedAt
        self.recovery = recovery
        self.training = training
        self.constraints = constraints
        self.dataQuality = dataQuality
        self.evidence = evidence
    }
}

struct RepRange: Codable, Hashable, Sendable {
    let lowerBound: Int
    let upperBound: Int

    init(_ lowerBound: Int, _ upperBound: Int) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }
}

enum ExerciseRecoveryDemand: Int, Codable, CaseIterable, Comparable, Hashable, Sendable {
    case low = 1
    case moderate = 2
    case high = 3

    static func < (lhs: ExerciseRecoveryDemand, rhs: ExerciseRecoveryDemand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Reviewed metadata layered over the browsable exercise catalog. Only values in this
/// injected collection are eligible for automatic planning.
struct CuratedExerciseDefinition: Identifiable, Codable, Hashable, Sendable {
    var id: String { catalogID }

    let catalogID: String
    let name: String
    let primaryMuscleGroup: MuscleGroup
    let secondaryMuscleGroups: [MuscleGroup]
    let movementPattern: MovementPattern
    let requiredEquipment: Set<EquipmentID>
    let supportedGoals: Set<TrainingGoal>
    let recoveryDemand: ExerciseRecoveryDemand
    let defaultSets: Int
    let repRange: RepRange
    let targetRPE: Double
    let restSeconds: Int
    let secondsPerSet: Int
    let transitionSeconds: Int
    let loadIncrement: Double?

    init(
        catalogID: String,
        name: String,
        primaryMuscleGroup: MuscleGroup,
        secondaryMuscleGroups: [MuscleGroup] = [],
        movementPattern: MovementPattern,
        requiredEquipment: Set<EquipmentID> = [.bodyweight],
        supportedGoals: Set<TrainingGoal> = Set(TrainingGoal.allCases),
        recoveryDemand: ExerciseRecoveryDemand = .moderate,
        defaultSets: Int = 3,
        repRange: RepRange = RepRange(6, 10),
        targetRPE: Double = 7.5,
        restSeconds: Int = 90,
        secondsPerSet: Int = 45,
        transitionSeconds: Int = 75,
        loadIncrement: Double? = nil
    ) {
        self.catalogID = catalogID
        self.name = name
        self.primaryMuscleGroup = primaryMuscleGroup
        self.secondaryMuscleGroups = secondaryMuscleGroups
        self.movementPattern = movementPattern
        self.requiredEquipment = requiredEquipment
        self.supportedGoals = supportedGoals
        self.recoveryDemand = recoveryDemand
        self.defaultSets = defaultSets
        self.repRange = repRange
        self.targetRPE = targetRPE
        self.restSeconds = restSeconds
        self.secondsPerSet = secondsPerSet
        self.transitionSeconds = transitionSeconds
        self.loadIncrement = loadIncrement
    }
}

enum LoadUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case pounds
    case kilograms
}

enum ProgressionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case load
    case repetitions
}

struct ProgressionSuggestion: Codable, Hashable, Sendable {
    let kind: ProgressionKind
    let currentLoad: Double?
    let suggestedLoad: Double?
    let currentRepetitions: Int?
    let suggestedRepetitions: Int?
    let unit: LoadUnit
    let requiresConfirmation: Bool
}

struct ExercisePrescription: Identifiable, Codable, Hashable, Sendable {
    var id: String { catalogID }

    let catalogID: String
    let name: String
    let primaryMuscleGroup: MuscleGroup
    let movementPattern: MovementPattern
    let requiredEquipment: Set<EquipmentID>
    let workingSets: Int
    let repetitions: RepRange
    let workingLoad: Double?
    let targetRPE: Double
    let restSeconds: Int
    let secondsPerSet: Int
    let transitionSeconds: Int
    let progressionSuggestion: ProgressionSuggestion?

    var estimatedDurationSeconds: Int {
        transitionSeconds
            + workingSets * secondsPerSet
            + max(workingSets - 1, 0) * restSeconds
    }

    func workoutExercise(loadUnit: LoadUnit = .pounds, id: UUID = UUID()) -> WorkoutExercise {
        WorkoutExercise(
            id: id,
            catalogID: catalogID,
            equipment: requiredEquipment
                .sorted(by: { $0.rawValue < $1.rawValue })
                .map(\.title)
                .joined(separator: ", "),
            movementPattern: movementPattern.rawValue,
            name: name,
            muscleGroup: primaryMuscleGroup,
            workingSets: workingSets,
            targetReps: repetitions.lowerBound,
            targetWeight: workingLoad ?? 0,
            loadUnit: loadUnit,
            targetRPE: targetRPE,
            restSeconds: restSeconds
        )
    }
}

enum WorkoutPlanningMode: String, Codable, CaseIterable, Hashable, Sendable {
    case performance
    case balanced
    case reduced
}

enum WorkoutPlanReasonCode: String, Codable, CaseIterable, Hashable, Sendable {
    case highReadiness
    case moderateReadiness
    case lowReadiness
    case limitedRecoveryConfidence
    case healthDataUnavailable
    case sleepNearTarget
    case sleepBelowTarget
    case heartRateVariabilityNearBaseline
    case heartRateVariabilityBelowBaseline
    case restingHeartRateNearBaseline
    case restingHeartRateElevated
    case upperBodyDue
    case lowerBodyDue
    case balancedFullBody
    case userRequestedFocus
    case familiarExercisesPrioritized
    case equipmentMatched
    case durationMatched
    case weeklyLoadReduced
    case weeklyTargetReached
    case shorterOption
    case alternateFocus
}

struct WorkoutPlan: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let stateID: UUID
    let plannerVersion: Int
    let mode: WorkoutPlanningMode
    let title: String
    let focus: TrainingFocus
    let durationLimitMinutes: Int
    let expectedDurationMinutes: Int
    let exercises: [ExercisePrescription]
    let reasonCodes: [WorkoutPlanReasonCode]
}

enum WorkoutCandidateRole: String, Codable, CaseIterable, Hashable, Sendable {
    case primary
    case shorter
    case alternateFocus
}

struct WorkoutPlanCandidate: Identifiable, Codable, Hashable, Sendable {
    var id: String { plan.id }

    let role: WorkoutCandidateRole
    let plan: WorkoutPlan
    /// Deterministic planner score used for ranking and diagnostics, not health advice.
    let plannerScore: Int
}

/// A successful planning result always contains one and only one candidate for each role.
struct WorkoutPlanCandidates: Codable, Hashable, Sendable {
    let primary: WorkoutPlanCandidate
    let shorter: WorkoutPlanCandidate
    let alternateFocus: WorkoutPlanCandidate

    var all: [WorkoutPlanCandidate] {
        [primary, shorter, alternateFocus]
    }
}

enum WorkoutPlanValidationIssue: Error, Codable, Hashable, Sendable {
    case staleState(expected: UUID, actual: UUID)
    case unsupportedPlannerVersion(expected: Int, actual: Int)
    case invalidDurationLimit(Int)
    case durationLimitExceedsAvailable(limit: Int, available: Int)
    case durationExceeded(expected: Int, limit: Int)
    case durationMismatch(stored: Int, calculated: Int)
    case emptyWorkout
    case duplicateExercise(String)
    case unknownExercise(String)
    case excludedExercise(String)
    case excludedMovement(MovementPattern)
    case unavailableEquipment(exerciseID: String, equipment: EquipmentID)
    case unsupportedGoal(exerciseID: String, goal: TrainingGoal)
    case exerciseOutsideFocus(exerciseID: String, focus: TrainingFocus)
    case fullBodyBalanceMissing
    case catalogMetadataMismatch(String)
    case recoveryDemandExceeded(String)
    case invalidSets(exerciseID: String, sets: Int)
    case volumeEnvelopeExceeded(exerciseID: String, sets: Int, maximum: Int)
    case invalidRepetitions(exerciseID: String)
    case invalidRPE(exerciseID: String, rpe: Double, maximum: Double)
    case unsupportedWorkingLoad(String)
    case unconfirmedProgression(String)
    case ineligibleProgression(String)
    case invalidCandidateRole(expected: WorkoutCandidateRole, actual: WorkoutCandidateRole)
    case alternateFocusMatchesPrimary
}

enum WorkoutPlanningError: Error, Equatable, Sendable {
    case unsupportedStateSchema(Int)
    case invalidAvailableMinutes(Int)
    case invalidRecoveryScore(Int)
    case emptyCuratedPool
    case duplicateCatalogID(String)
    case invalidCuratedExercise(String)
    case noEligibleExercises
    case requestedFocusUnavailable(TrainingFocus)
    case insufficientFocusCoverage
    case unableToBuildCandidate(WorkoutCandidateRole)
    case validationFailed([WorkoutPlanValidationIssue])
}

extension WorkoutPlanningError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedStateSchema(let version):
            "Daily training state schema \(version) is not supported."
        case .invalidAvailableMinutes(let minutes):
            "Available workout time must be between 15 and 180 minutes, not \(minutes)."
        case .invalidRecoveryScore(let score):
            "Readiness must be between 0 and 100, not \(score)."
        case .emptyCuratedPool:
            "No reviewed exercises are available for workout planning."
        case .duplicateCatalogID(let id):
            "The reviewed exercise pool contains duplicate ID \(id)."
        case .invalidCuratedExercise(let id):
            "Reviewed exercise \(id) has an invalid prescription."
        case .noEligibleExercises:
            "No reviewed exercises match the selected equipment and exclusions."
        case .requestedFocusUnavailable(let focus):
            "No reviewed exercises can create a \(focus.title.lowercased()) workout with these constraints."
        case .insufficientFocusCoverage:
            "The reviewed exercise pool cannot provide both a primary and an alternate focus."
        case .unableToBuildCandidate(let role):
            "The planner could not build the \(role.rawValue) workout within the selected duration."
        case .validationFailed:
            "A generated workout did not pass deterministic validation."
        }
    }
}
