import Foundation

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
