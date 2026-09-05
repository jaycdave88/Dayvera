import Foundation
import SwiftData

enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest, back, shoulders, arms, quads, hamstrings, glutes, calves, core, fullBody

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fullBody: "Full body"
        default: rawValue.capitalized
        }
    }
}

struct WorkoutExercise: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var catalogID: String? = nil
    /// Durable planning metadata. Optional values keep templates created before
    /// workout generation fully decodable.
    var equipment: String? = nil
    var movementPattern: String? = nil
    var name: String
    var muscleGroup: MuscleGroup
    var workingSets: Int
    var targetReps: Int
    /// Upper end of a generated prescription's repetition range. Templates
    /// created before range-aware progression (and custom templates with a
    /// single target) use `targetReps` as both ends of the range.
    var targetRepRangeUpper: Int? = nil
    var targetWeight: Double
    /// Unit paired with `targetWeight`. Templates created before unit tracking
    /// decode as `nil` and are treated as pounds, the app's historical unit.
    var loadUnit: LoadUnit? = nil
    var targetRPE: Double
    var restSeconds: Int
    var supersetGroup: String?
    /// Nil identifies the legacy strength/resistance prescription.
    var modalityRaw: String? = nil
    /// Used by cardio, balance, and mobility sessions. Strength sessions keep
    /// their existing set/rep prescription.
    var durationSeconds: Int? = nil
    var intensityCue: String? = nil
    var coachingCue: String? = nil

    var resolvedLoadUnit: LoadUnit { loadUnit ?? .pounds }

    var modality: TrainingModality {
        modalityRaw.flatMap(TrainingModality.init(rawValue:)) ?? .strengthResistance
    }

    var progressionUpperReps: Int {
        max(targetReps, targetRepRangeUpper ?? targetReps)
    }

    func converted(to destination: LoadUnit) -> WorkoutExercise {
        guard resolvedLoadUnit != destination else {
            var tagged = self
            tagged.loadUnit = destination
            return tagged
        }
        var converted = self
        converted.targetWeight = resolvedLoadUnit.convert(targetWeight, to: destination)
        converted.loadUnit = destination
        return converted
    }
}

struct CompletedSet: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var exerciseID: UUID
    /// Stable catalog identity when the exercise came from the bundled library.
    /// Optional so sessions written before catalog integration continue to decode.
    var catalogID: String? = nil
    /// Snapshot the context needed for future planning so deleting or editing a
    /// template never rewrites what the user actually trained.
    var muscleGroup: MuscleGroup? = nil
    var equipment: String? = nil
    var movementPattern: String? = nil
    var exerciseName: String
    var setNumber: Int
    var weight: Double
    /// Unit paired with `weight`. Legacy records used pounds.
    var loadUnit: LoadUnit? = nil
    var reps: Int
    /// User-reported effort. New active workouts intentionally leave this nil:
    /// a planned RPE is not an observed RPE. Optional decoding keeps legacy
    /// sessions (which stored a number) compatible.
    var rpe: Double? = nil
    var isWarmup: Bool
    var completedAt: Date

    var volume: Double { weight * Double(reps) }

    var progressionKey: String {
        if let catalogID, !catalogID.isEmpty { return "catalog:\(catalogID)" }
        let normalizedName = exerciseName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "name:\(normalizedName)"
    }

    var estimatedOneRepMax: Double? {
        guard !isWarmup, weight > 0, reps > 0 else { return nil }
        return weight * (1 + Double(reps) / 30)
    }

    var resolvedLoadUnit: LoadUnit { loadUnit ?? .pounds }
}

struct ExerciseProgressOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct ExercisePerformancePoint: Identifiable, Hashable, Sendable {
    var id: UUID { sessionID }
    let sessionID: UUID
    let exerciseKey: String
    let exerciseName: String
    let date: Date
    let weight: Double
    let loadUnit: LoadUnit
    let reps: Int
    let rpe: Double?
    let estimatedOneRepMax: Double
    var isPersonalBest: Bool
}

struct PreviousSetPerformance: Hashable, Sendable {
    let sessionID: UUID
    let completedAt: Date
    let weight: Double
    let loadUnit: LoadUnit
    let reps: Int
}

enum WorkoutProgressionAction: String, Hashable, Sendable {
    case increaseLoad
    case increaseRepetitions
    case hold
}

struct WorkoutProgressionRecommendation: Identifiable, Hashable, Sendable {
    var id: String { "\(exerciseID.uuidString):\(action.rawValue)" }

    let exerciseID: UUID
    let action: WorkoutProgressionAction
    let currentLoad: Double
    let suggestedLoad: Double
    let currentRepetitions: Int
    let suggestedRepetitions: Int
    let loadUnit: LoadUnit
    let rationale: String

    var canApply: Bool {
        action != .hold
            && (suggestedLoad != currentLoad || suggestedRepetitions != currentRepetitions)
    }
}

/// Finds the matching set from the most recent local, exercise-level session.
/// Stable catalog identity wins; normalized names are used only for custom or
/// legacy sets that do not have a catalog identifier.
func previousSetPerformance(
    catalogID: String?,
    exerciseName: String,
    setNumber: Int,
    from sessions: [WorkoutSessionRecord],
    displayedIn displayUnit: LoadUnit
) -> PreviousSetPerformance? {
    let orderedSessions = sessions.sorted { lhs, rhs in
        if lhs.startedAt == rhs.startedAt { return lhs.endedAt > rhs.endedAt }
        return lhs.startedAt > rhs.startedAt
    }

    for session in orderedSessions {
        guard let previous = session.sets.first(where: {
            !$0.isWarmup
                && $0.setNumber == setNumber
                && completedSet($0, matchesCatalogID: catalogID, exerciseName: exerciseName)
        }) else { continue }
        return PreviousSetPerformance(
            sessionID: session.id,
            completedAt: previous.completedAt,
            weight: previous.resolvedLoadUnit.convert(previous.weight, to: displayUnit),
            loadUnit: displayUnit,
            reps: previous.reps
        )
    }
    return nil
}

/// Double progression for an active workout. Exercise history can justify an
/// increase, while today's recovery gate can only keep the prescription flat.
/// Health workouts without logged exercise sets never enter this calculation.
func workoutProgressionRecommendation(
    for exercise: WorkoutExercise,
    sessions: [WorkoutSessionRecord],
    displayedIn displayUnit: LoadUnit,
    allowsProgression: Bool
) -> WorkoutProgressionRecommendation? {
    struct SessionPerformance {
        let load: Double
        let repetitions: Int
        let reachedUpperRange: Bool
    }

    let upperRepetitions = exercise.progressionUpperReps
    let performances = sessions
        .sorted { lhs, rhs in
            if lhs.startedAt == rhs.startedAt { return lhs.endedAt > rhs.endedAt }
            return lhs.startedAt > rhs.startedAt
        }
        .compactMap { session -> SessionPerformance? in
            let workingSets = session.sets
                .filter {
                    !$0.isWarmup
                        && completedSet(
                            $0,
                            matchesCatalogID: exercise.catalogID,
                            exerciseName: exercise.name
                        )
                }
                .sorted { $0.setNumber < $1.setNumber }
            guard let minimumRepetitions = workingSets.map(\.reps).min() else { return nil }
            let convertedLoads = workingSets.map {
                $0.resolvedLoadUnit.convert($0.weight, to: displayUnit)
            }
            let hasUniqueSetNumbers = Set(workingSets.map(\.setNumber)).count == workingSets.count
            let usesOneWorkingLoad = convertedLoads.allSatisfy {
                abs($0 - convertedLoads[0]) < 0.05
            }
            return SessionPerformance(
                load: convertedLoads[0],
                repetitions: minimumRepetitions,
                reachedUpperRange: workingSets.count >= max(exercise.workingSets, 1)
                    && hasUniqueSetNumbers
                    && usesOneWorkingLoad
                    && workingSets.allSatisfy { $0.reps >= upperRepetitions }
            )
        }

    guard let latest = performances.first else { return nil }
    let currentLoad = latest.load
    let currentRepetitions = latest.repetitions

    guard allowsProgression else {
        return WorkoutProgressionRecommendation(
            exerciseID: exercise.id,
            action: .hold,
            currentLoad: currentLoad,
            suggestedLoad: currentLoad,
            currentRepetitions: currentRepetitions,
            suggestedRepetitions: currentRepetitions,
            loadUnit: displayUnit,
            rationale: "Today's recovery plan keeps this exercise at its prior load and repetitions. Recovery can block an increase, but it never creates one."
        )
    }

    if currentLoad > 0,
       performances.count >= 2,
       performances[0].reachedUpperRange,
       performances[1].reachedUpperRange,
       abs(performances[0].load - performances[1].load) < 0.05 {
        let increment = displayUnit == .pounds ? 5.0 : 2.5
        return WorkoutProgressionRecommendation(
            exerciseID: exercise.id,
            action: .increaseLoad,
            currentLoad: currentLoad,
            suggestedLoad: currentLoad + increment,
            currentRepetitions: currentRepetitions,
            suggestedRepetitions: exercise.targetReps,
            loadUnit: displayUnit,
            rationale: "Your two latest logged sessions reached the top of this exercise's repetition range at the same load. Add the minimum \(increment.formatted(.number.precision(.fractionLength(0...1)))) \(displayUnit.symbol) step and return to the bottom of the range."
        )
    }

    if currentRepetitions < upperRepetitions {
        return WorkoutProgressionRecommendation(
            exerciseID: exercise.id,
            action: .increaseRepetitions,
            currentLoad: currentLoad,
            suggestedLoad: currentLoad,
            currentRepetitions: currentRepetitions,
            suggestedRepetitions: currentRepetitions + 1,
            loadUnit: displayUnit,
            rationale: "Add one repetition at the same load. A load increase waits until two logged sessions reach the top of the range."
        )
    }

    return WorkoutProgressionRecommendation(
        exerciseID: exercise.id,
        action: .hold,
        currentLoad: currentLoad,
        suggestedLoad: currentLoad,
        currentRepetitions: currentRepetitions,
        suggestedRepetitions: currentRepetitions,
        loadUnit: displayUnit,
        rationale: "Repeat the top of the repetition range at the same load once more. Load increases only after two complete logged sessions confirm it."
    )
}

/// Reconciles a history-derived recommendation with values the user already
/// has in today's draft. A recommendation is allowed to raise a draft value,
/// but never to silently lower or overwrite a stronger user choice.
func nonRegressiveProgressionRecommendation(
    _ recommendation: WorkoutProgressionRecommendation,
    currentDraftLoad: Double,
    currentDraftRepetitions: Int
) -> WorkoutProgressionRecommendation {
    let currentLoad = max(currentDraftLoad, 0)
    let currentRepetitions = max(currentDraftRepetitions, 1)
    let suggestedLoad = max(recommendation.suggestedLoad, currentLoad)
    let suggestedRepetitions = max(recommendation.suggestedRepetitions, currentRepetitions)

    let action: WorkoutProgressionAction
    if suggestedLoad > currentLoad + 0.000_1 {
        action = .increaseLoad
    } else if suggestedRepetitions > currentRepetitions {
        action = .increaseRepetitions
    } else {
        action = .hold
    }

    let rationale = action == .hold && recommendation.action != .hold
        ? "Your current draft already meets or exceeds the history-based suggestion. Keep your entered values unless you choose to change them."
        : recommendation.rationale

    return WorkoutProgressionRecommendation(
        exerciseID: recommendation.exerciseID,
        action: action,
        currentLoad: currentLoad,
        suggestedLoad: suggestedLoad,
        currentRepetitions: currentRepetitions,
        suggestedRepetitions: suggestedRepetitions,
        loadUnit: recommendation.loadUnit,
        rationale: rationale
    )
}

private func completedSet(
    _ set: CompletedSet,
    matchesCatalogID catalogID: String?,
    exerciseName: String
) -> Bool {
    let requestedCatalogID = catalogID?.trimmingCharacters(in: .whitespacesAndNewlines)
    let storedCatalogID = set.catalogID?.trimmingCharacters(in: .whitespacesAndNewlines)

    if let requestedCatalogID, !requestedCatalogID.isEmpty {
        if let storedCatalogID, !storedCatalogID.isEmpty {
            return storedCatalogID == requestedCatalogID
        }
        return normalizedExerciseName(set.exerciseName) == normalizedExerciseName(exerciseName)
    }
    // A custom exercise has no catalog identity. It may use legacy/custom
    // name-based history, but must never borrow same-name history from a
    // catalog exercise with different semantics or equipment.
    if let storedCatalogID, !storedCatalogID.isEmpty { return false }
    return normalizedExerciseName(set.exerciseName) == normalizedExerciseName(exerciseName)
}

private func normalizedExerciseName(_ name: String) -> String {
    name
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

enum WorkoutHealthExportState: String, Codable, CaseIterable, Sendable {
    case unknown
    case pending
    case exported
    case failed
}

func exerciseProgressOptions(from sessions: [WorkoutSessionRecord]) -> [ExerciseProgressOption] {
    var namesByKey: [String: String] = [:]
    for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
        for set in session.sets where !set.isWarmup {
            namesByKey[set.progressionKey] = set.exerciseName
        }
    }
    return namesByKey
        .map { ExerciseProgressOption(id: $0.key, name: $0.value) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

func exercisePerformanceHistory(
    from sessions: [WorkoutSessionRecord],
    exerciseKey: String,
    displayedIn displayUnit: LoadUnit? = nil
) -> [ExercisePerformancePoint] {
    var points = sessions.compactMap { session -> ExercisePerformancePoint? in
        let candidates = session.sets.filter {
            !$0.isWarmup && $0.progressionKey == exerciseKey && $0.estimatedOneRepMax != nil
        }
        guard let topSet = candidates.max(by: {
            ($0.estimatedOneRepMax ?? 0) < ($1.estimatedOneRepMax ?? 0)
        }), let estimate = topSet.estimatedOneRepMax else { return nil }
        let unit = displayUnit ?? topSet.resolvedLoadUnit
        return ExercisePerformancePoint(
            sessionID: session.id,
            exerciseKey: exerciseKey,
            exerciseName: topSet.exerciseName,
            date: session.startedAt,
            weight: topSet.resolvedLoadUnit.convert(topSet.weight, to: unit),
            loadUnit: unit,
            reps: topSet.reps,
            rpe: topSet.rpe,
            estimatedOneRepMax: topSet.resolvedLoadUnit.convert(estimate, to: unit),
            isPersonalBest: false
        )
    }.sorted { $0.date < $1.date }

    if let bestIndex = points.indices.max(by: { lhs, rhs in
        let left = points[lhs]
        let right = points[rhs]
        if left.estimatedOneRepMax == right.estimatedOneRepMax {
            return left.date < right.date
        }
        return left.estimatedOneRepMax < right.estimatedOneRepMax
    }) {
        points[bestIndex].isPersonalBest = true
    }
    return points
}

func adaptedWorkingSetCounts(
    for exercises: [WorkoutExercise],
    volumeMultiplier: Double
) -> [UUID: Int] {
    guard !exercises.isEmpty else { return [:] }
    let multiplier = min(max(volumeMultiplier, 0), 1)
    let originalTotal = exercises.reduce(0) { $0 + $1.workingSets }
    let targetTotal = max(exercises.count, Int((Double(originalTotal) * multiplier).rounded()))

    var counts = Dictionary(uniqueKeysWithValues: exercises.map { exercise in
        (exercise.id, max(1, min(exercise.workingSets, Int((Double(exercise.workingSets) * multiplier).rounded(.down)))))
    })
    let priority = exercises.sorted { lhs, rhs in
        let leftRemainder = Double(lhs.workingSets) * multiplier - floor(Double(lhs.workingSets) * multiplier)
        let rightRemainder = Double(rhs.workingSets) * multiplier - floor(Double(rhs.workingSets) * multiplier)
        return leftRemainder == rightRemainder ? lhs.workingSets > rhs.workingSets : leftRemainder > rightRemainder
    }

    var remaining = targetTotal - counts.values.reduce(0, +)
    while remaining > 0 {
        var added = false
        for exercise in priority where remaining > 0 {
            let current = counts[exercise.id, default: 1]
            guard current < exercise.workingSets else { continue }
            counts[exercise.id] = current + 1
            remaining -= 1
            added = true
        }
        if !added { break }
    }
    return counts
}

@Model
final class WorkoutTemplateRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var exercisesData: Data

    init(id: UUID = UUID(), name: String, createdAt: Date = .now, exercises: [WorkoutExercise] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.exercisesData = (try? JSONEncoder().encode(exercises)) ?? Data()
    }

    var exercises: [WorkoutExercise] {
        get { (try? JSONDecoder().decode([WorkoutExercise].self, from: exercisesData)) ?? [] }
        set { exercisesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var modality: TrainingModality {
        exercises.first?.modality ?? .strengthResistance
    }
}

@Model
final class WorkoutSessionRecord {
    @Attribute(.unique) var id: UUID
    var templateID: UUID?
    var templateName: String
    var startedAt: Date
    var endedAt: Date
    var readinessRaw: String
    var readinessScore: Int
    /// `nil` identifies records created before availability was persisted. For
    /// those records, a nonzero score is the only evidence that recovery existed.
    var readinessWasAvailable: Bool? = nil
    var totalVolume: Double
    var setsData: Data
    var notes: String
    /// Persisted separately from the enum. Existing records predate sync metadata,
    /// so migration leaves their status unknown instead of offering a retry that
    /// could duplicate a legacy Health workout. New records initialize pending.
    var healthExportStateRaw: String = WorkoutHealthExportState.unknown.rawValue
    /// HealthKit uses this with the stable session UUID to replace, rather than
    /// duplicate, a workout when a newer export attempt is saved.
    var healthExportSyncVersion: Int = 1
    var healthExportErrorMessage: String?
    var modalityRaw: String?

    init(
        id: UUID = UUID(),
        templateID: UUID?,
        templateName: String,
        startedAt: Date,
        endedAt: Date,
        readiness: ReadinessBand,
        readinessScore: Int,
        readinessAvailable: Bool = true,
        sets: [CompletedSet],
        notes: String = "",
        healthExportState: WorkoutHealthExportState = .pending,
        healthExportSyncVersion: Int = 1,
        healthExportErrorMessage: String? = nil,
        modality: TrainingModality = .strengthResistance
    ) {
        self.id = id
        self.templateID = templateID
        self.templateName = templateName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.readinessRaw = readiness.rawValue
        self.readinessScore = readinessScore
        self.readinessWasAvailable = readinessAvailable
        self.totalVolume = sets.filter { !$0.isWarmup }.reduce(0) { $0 + $1.volume }
        self.setsData = (try? JSONEncoder().encode(sets)) ?? Data()
        self.notes = notes
        self.healthExportStateRaw = healthExportState.rawValue
        self.healthExportSyncVersion = max(healthExportSyncVersion, 1)
        self.healthExportErrorMessage = healthExportErrorMessage
        self.modalityRaw = modality.rawValue
    }

    var readiness: ReadinessBand {
        ReadinessBand(rawValue: readinessRaw) ?? .moderate
    }

    var modality: TrainingModality {
        modalityRaw.flatMap(TrainingModality.init(rawValue:)) ?? .strengthResistance
    }

    /// Preserves a genuine score of zero for new records while treating the
    /// historical zero sentinel as missing recovery data.
    var recordedReadinessScore: Int? {
        let wasAvailable = readinessWasAvailable ?? (readinessScore > 0)
        return wasAvailable ? readinessScore : nil
    }

    var sets: [CompletedSet] {
        (try? JSONDecoder().decode([CompletedSet].self, from: setsData)) ?? []
    }

    var healthExportState: WorkoutHealthExportState {
        get { WorkoutHealthExportState(rawValue: healthExportStateRaw) ?? .unknown }
        set { healthExportStateRaw = newValue.rawValue }
    }

    /// Every retry gets a greater version. If an earlier HealthKit save succeeded
    /// before its local acknowledgement was committed, the new version replaces it.
    @discardableResult
    func prepareHealthExportRetry() -> Bool {
        guard healthExportState == .pending || healthExportState == .failed,
              healthExportSyncVersion < Int.max else { return false }
        healthExportSyncVersion = max(healthExportSyncVersion + 1, 1)
        healthExportState = .pending
        healthExportErrorMessage = nil
        return true
    }

    func markHealthExported() {
        healthExportState = .exported
        healthExportErrorMessage = nil
    }

    func markHealthExportFailed(message: String) {
        healthExportState = .failed
        healthExportErrorMessage = message
    }

    var durationMinutes: Double {
        max(endedAt.timeIntervalSince(startedAt) / 60, 0)
    }
}
