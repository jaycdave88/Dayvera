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
    var targetWeight: Double
    /// Unit paired with `targetWeight`. Templates created before unit tracking
    /// decode as `nil` and are treated as pounds, the app's historical unit.
    var loadUnit: LoadUnit? = nil
    var targetRPE: Double
    var restSeconds: Int
    var supersetGroup: String?

    var resolvedLoadUnit: LoadUnit { loadUnit ?? .pounds }

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
    var rpe: Double
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
    let rpe: Double
    let estimatedOneRepMax: Double
    var isPersonalBest: Bool
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
        healthExportErrorMessage: String? = nil
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
    }

    var readiness: ReadinessBand {
        ReadinessBand(rawValue: readinessRaw) ?? .moderate
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
