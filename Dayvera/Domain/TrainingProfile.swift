import Foundation

/// A one-session request from the Train tab. It is intentionally ephemeral:
/// long-term preferences live in `TrainingProfile`, while this only shapes the
/// next recommendation the user asks Dayvera to build.
struct WorkoutBuildIntent: Hashable, Sendable {
    let availableMinutes: Int
    let focus: TrainingFocus?
    let effort: PlannedEffort
}

// MARK: - Motivation summaries

enum ReturningExperience: Equatable, Sendable {
    case none
    case welcomeBack
    case trendsNeedData

    static func classify(
        previousUse: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ReturningExperience {
        guard let previousUse else { return .none }
        let previousDay = calendar.startOfDay(for: previousUse)
        let currentDay = calendar.startOfDay(for: now)
        guard previousDay <= currentDay,
              let days = calendar.dateComponents([.day], from: previousDay, to: currentDay).day,
              days >= 7 else { return .none }
        return days >= 30 ? .trendsNeedData : .welcomeBack
    }
}

struct WeeklyRhythm: Equatable, Sendable {
    let weekStart: Date
    let trainingCompleted: Int
    let trainingTarget: Int
    let completeNutritionDays: Int
    let recoveryNightsRecorded: Int
    let completedTrainingWeeksInLastFour: Int

    var trainingProgress: Double {
        min(Double(trainingCompleted) / Double(max(trainingTarget, 1)), 1)
    }

    var nutritionProgress: Double {
        min(Double(completeNutritionDays) / 7, 1)
    }

    var trainingPlanMet: Bool { trainingCompleted >= trainingTarget }

    var momentumText: String? {
        guard completedTrainingWeeksInLastFour > 0 else { return nil }
        return "Training met your plan in \(completedTrainingWeeksInLastFour) of the last 4 completed weeks."
    }
}

enum WeeklyRhythmEngine {
    static func summary(
        now: Date = .now,
        calendar suppliedCalendar: Calendar = .current,
        sessionDates: [Date],
        trainingTarget: Int,
        completedNutritionDayKeys: Set<String>,
        recoveryDates: [Date]
    ) -> WeeklyRhythm {
        let calendar = suppliedCalendar
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 86_400)

        let completedSessions = sessionDates.filter { week.contains($0) && $0 <= now }.count
        let recoveryDays = uniqueDays(recoveryDates.filter { week.contains($0) && $0 <= now }, calendar: calendar)
        let nutritionDays = dates(in: week, calendar: calendar).filter {
            $0 <= now && completedNutritionDayKeys.contains(dayKey($0, calendar: calendar))
        }.count

        let completedPriorWeeks = (1...4).filter { offset in
            guard let anchor = calendar.date(byAdding: .weekOfYear, value: -offset, to: week.start),
                  let interval = calendar.dateInterval(of: .weekOfYear, for: anchor) else { return false }
            return sessionDates.filter { interval.contains($0) && $0 <= now }.count >= max(trainingTarget, 1)
        }.count

        return WeeklyRhythm(
            weekStart: week.start,
            trainingCompleted: completedSessions,
            trainingTarget: max(trainingTarget, 1),
            completeNutritionDays: nutritionDays,
            recoveryNightsRecorded: recoveryDays.count,
            completedTrainingWeeksInLastFour: completedPriorWeeks
        )
    }

    private static func uniqueDays(_ dates: [Date], calendar: Calendar) -> Set<Date> {
        Set(dates.map { calendar.startOfDay(for: $0) })
    }

    private static func dates(in interval: DateInterval, calendar: Calendar) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
            .filter(interval.contains)
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0)
    }
}

struct TrainingProfile: Codable, Equatable, Hashable, Sendable {
    var goal: TrainingGoal
    var targetSessionsPerWeek: Int
    var loadUnit: LoadUnit
    var equipmentProfiles: [EquipmentProfile]
    var activeEquipmentProfileID: EquipmentProfileID
    var preferredExerciseIDs: Set<String>
    var excludedExerciseIDs: Set<String>
    var excludedMovementPatterns: Set<MovementPattern>
    var onDevicePersonalizationEnabled: Bool

    init(
        goal: TrainingGoal = .strengthAndMuscle,
        targetSessionsPerWeek: Int = 4,
        loadUnit: LoadUnit = .pounds,
        equipmentProfiles: [EquipmentProfile] = [.fullGym, .home, .travel],
        activeEquipmentProfileID: EquipmentProfileID = .fullGym,
        preferredExerciseIDs: Set<String> = [],
        excludedExerciseIDs: Set<String> = [],
        excludedMovementPatterns: Set<MovementPattern> = [],
        onDevicePersonalizationEnabled: Bool = false
    ) {
        self.goal = goal
        self.targetSessionsPerWeek = min(max(targetSessionsPerWeek, 2), 6)
        self.loadUnit = loadUnit
        self.equipmentProfiles = Self.normalizedProfiles(equipmentProfiles)
        self.activeEquipmentProfileID = self.equipmentProfiles.contains(where: { $0.id == activeEquipmentProfileID })
            ? activeEquipmentProfileID
            : .fullGym
        self.preferredExerciseIDs = preferredExerciseIDs
        self.excludedExerciseIDs = excludedExerciseIDs
        self.excludedMovementPatterns = excludedMovementPatterns
        self.onDevicePersonalizationEnabled = onDevicePersonalizationEnabled
    }

    var activeEquipmentProfile: EquipmentProfile {
        equipmentProfiles.first(where: { $0.id == activeEquipmentProfileID }) ?? .fullGym
    }

    private enum CodingKeys: String, CodingKey {
        case goal
        case targetSessionsPerWeek
        case loadUnit
        case equipmentProfiles
        case activeEquipmentProfileID
        case preferredExerciseIDs
        case excludedExerciseIDs
        case excludedMovementPatterns
        case onDevicePersonalizationEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            goal: try container.decodeIfPresent(TrainingGoal.self, forKey: .goal) ?? .strengthAndMuscle,
            targetSessionsPerWeek: try container.decodeIfPresent(Int.self, forKey: .targetSessionsPerWeek) ?? 4,
            loadUnit: try container.decodeIfPresent(LoadUnit.self, forKey: .loadUnit) ?? .pounds,
            equipmentProfiles: try container.decodeIfPresent([EquipmentProfile].self, forKey: .equipmentProfiles)
                ?? [.fullGym, .home, .travel],
            activeEquipmentProfileID: try container.decodeIfPresent(EquipmentProfileID.self, forKey: .activeEquipmentProfileID)
                ?? .fullGym,
            preferredExerciseIDs: try container.decodeIfPresent(Set<String>.self, forKey: .preferredExerciseIDs) ?? [],
            excludedExerciseIDs: try container.decodeIfPresent(Set<String>.self, forKey: .excludedExerciseIDs) ?? [],
            excludedMovementPatterns: try container.decodeIfPresent(Set<MovementPattern>.self, forKey: .excludedMovementPatterns) ?? [],
            onDevicePersonalizationEnabled: try container.decodeIfPresent(Bool.self, forKey: .onDevicePersonalizationEnabled) ?? false
        )
    }

    static let `default` = TrainingProfile()

    private static func normalizedProfiles(_ profiles: [EquipmentProfile]) -> [EquipmentProfile] {
        var seen = Set<EquipmentProfileID>()
        var result = profiles.filter { seen.insert($0.id).inserted }
        for required in [EquipmentProfile.fullGym, .home, .travel] where seen.insert(required.id).inserted {
            result.append(required)
        }
        return result
    }
}

extension LoadUnit {
    var symbol: String { self == .pounds ? "lb" : "kg" }
    var spokenName: String { self == .pounds ? "pounds" : "kilograms" }
    var maximumWorkoutLoad: Double { self == .pounds ? 1_000 : 500 }
    var inputStep: Double { self == .pounds ? 2.5 : 1 }

    func convert(_ value: Double, to destination: LoadUnit) -> Double {
        guard self != destination else { return value }
        return switch (self, destination) {
        case (.pounds, .kilograms): value * 0.453_592_37
        case (.kilograms, .pounds): value / 0.453_592_37
        default: value
        }
    }
}

extension MovementPattern {
    var title: String {
        switch self {
        case .squat: "Squat"
        case .hinge: "Hip Hinge"
        case .singleLeg: "Single-Leg"
        case .horizontalPush: "Horizontal Push"
        case .verticalPush: "Vertical Push"
        case .horizontalPull: "Horizontal Pull"
        case .verticalPull: "Vertical Pull"
        case .elbowFlexion: "Biceps / Elbow Flexion"
        case .elbowExtension: "Triceps / Elbow Extension"
        case .calfRaise: "Calf Raise"
        case .carry: "Loaded Carry"
        case .core: "Core"
        case .isolation: "Other Isolation"
        }
    }
}
