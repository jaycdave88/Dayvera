import Foundation

/// The reviewed subset that the automatic planner may prescribe. RepDB remains
/// fully browsable, but an exercise is not generated until its identifier and
/// planning role appear here.
enum CuratedExerciseCatalog {
    private struct Spec {
        let id: String
        let muscle: MuscleGroup
        let pattern: MovementPattern
        let demand: ExerciseRecoveryDemand
        var extraEquipment: Set<EquipmentID> = []
    }

    private static let specs: [Spec] = [
        // Horizontal push
        .init(id: "bench-press", muscle: .chest, pattern: .horizontalPush, demand: .high, extraEquipment: [.adjustableBench]),
        .init(id: "db-bench-press", muscle: .chest, pattern: .horizontalPush, demand: .moderate, extraEquipment: [.adjustableBench]),
        .init(id: "incline-bench-press", muscle: .chest, pattern: .horizontalPush, demand: .high, extraEquipment: [.adjustableBench]),
        .init(id: "paused-bench-press", muscle: .chest, pattern: .horizontalPush, demand: .high, extraEquipment: [.adjustableBench]),
        .init(id: "cable-chest-press", muscle: .chest, pattern: .horizontalPush, demand: .moderate),
        .init(id: "chest-press-machine", muscle: .chest, pattern: .horizontalPush, demand: .moderate),
        .init(id: "push-up", muscle: .chest, pattern: .horizontalPush, demand: .low),
        .init(id: "incline-push-ups", muscle: .chest, pattern: .horizontalPush, demand: .low, extraEquipment: [.adjustableBench]),
        .init(id: "decline-push-up", muscle: .chest, pattern: .horizontalPush, demand: .moderate, extraEquipment: [.adjustableBench]),
        .init(id: "kettlebell-close-grip-floor-press", muscle: .arms, pattern: .horizontalPush, demand: .moderate),

        // Horizontal pull
        .init(id: "barbell-row", muscle: .back, pattern: .horizontalPull, demand: .high),
        .init(id: "bent-over-db-row", muscle: .back, pattern: .horizontalPull, demand: .moderate),
        .init(id: "chest-supported-db-row", muscle: .back, pattern: .horizontalPull, demand: .moderate, extraEquipment: [.adjustableBench]),
        .init(id: "single-arm-db-row", muscle: .back, pattern: .horizontalPull, demand: .moderate, extraEquipment: [.adjustableBench]),
        .init(id: "seated-cable-row", muscle: .back, pattern: .horizontalPull, demand: .moderate),
        .init(id: "cable-bent-over-row", muscle: .back, pattern: .horizontalPull, demand: .moderate),
        .init(id: "t-bar-row", muscle: .back, pattern: .horizontalPull, demand: .high),
        .init(id: "ring-row", muscle: .back, pattern: .horizontalPull, demand: .moderate),
        .init(id: "trx-row", muscle: .back, pattern: .horizontalPull, demand: .moderate),
        .init(id: "one-arm-kettlebell-row", muscle: .back, pattern: .horizontalPull, demand: .moderate),

        // Vertical push
        .init(id: "ohp", muscle: .shoulders, pattern: .verticalPush, demand: .high),
        .init(id: "dumbbell-shoulder-press", muscle: .shoulders, pattern: .verticalPush, demand: .moderate),
        .init(id: "seated-db-press", muscle: .shoulders, pattern: .verticalPush, demand: .moderate, extraEquipment: [.adjustableBench]),
        .init(id: "arnold-press", muscle: .shoulders, pattern: .verticalPush, demand: .moderate),
        .init(id: "machine-shoulder-press", muscle: .shoulders, pattern: .verticalPush, demand: .moderate),
        .init(id: "bodyweight-overhead-press", muscle: .shoulders, pattern: .verticalPush, demand: .low),
        .init(id: "pike-push-ups", muscle: .shoulders, pattern: .verticalPush, demand: .moderate),
        .init(id: "one-arm-kettlebell-shoulder-press", muscle: .shoulders, pattern: .verticalPush, demand: .moderate),

        // Vertical pull
        .init(id: "pull-up", muscle: .back, pattern: .verticalPull, demand: .high),
        .init(id: "neutral-grip-pull-ups", muscle: .back, pattern: .verticalPull, demand: .high),
        .init(id: "close-grip-pull-ups", muscle: .back, pattern: .verticalPull, demand: .high),
        .init(id: "assisted-pull-ups", muscle: .back, pattern: .verticalPull, demand: .moderate),
        .init(id: "band-assisted-pull-ups", muscle: .back, pattern: .verticalPull, demand: .moderate, extraEquipment: [.pullUpBar]),
        .init(id: "lat-pulldown", muscle: .back, pattern: .verticalPull, demand: .moderate),
        .init(id: "reverse-grip-lat-pulldown", muscle: .back, pattern: .verticalPull, demand: .moderate),
        .init(id: "one-arm-lat-pulldown", muscle: .back, pattern: .verticalPull, demand: .moderate),

        // Squat
        .init(id: "squat", muscle: .quads, pattern: .squat, demand: .high, extraEquipment: [.squatRack]),
        .init(id: "front-squat", muscle: .quads, pattern: .squat, demand: .high, extraEquipment: [.squatRack]),
        .init(id: "goblet-squat", muscle: .quads, pattern: .squat, demand: .moderate),
        .init(id: "dumbbell-front-squat", muscle: .quads, pattern: .squat, demand: .moderate),
        .init(id: "leg-press", muscle: .quads, pattern: .squat, demand: .moderate),
        .init(id: "horizontal-leg-press", muscle: .quads, pattern: .squat, demand: .moderate),
        .init(id: "close-stance-leg-press", muscle: .quads, pattern: .squat, demand: .moderate),
        .init(id: "smith-machine-front-squat", muscle: .quads, pattern: .squat, demand: .high),

        // Hinge
        .init(id: "deadlift", muscle: .hamstrings, pattern: .hinge, demand: .high),
        .init(id: "romanian-deadlift", muscle: .hamstrings, pattern: .hinge, demand: .high),
        .init(id: "dumbbell-romanian-deadlift", muscle: .hamstrings, pattern: .hinge, demand: .moderate),
        .init(id: "dumbbell-deadlift", muscle: .hamstrings, pattern: .hinge, demand: .moderate),
        .init(id: "kettlebell-deadlift", muscle: .hamstrings, pattern: .hinge, demand: .moderate),
        .init(id: "kettlebell-swing", muscle: .glutes, pattern: .hinge, demand: .moderate),
        .init(id: "hip-thrust", muscle: .glutes, pattern: .hinge, demand: .high, extraEquipment: [.adjustableBench]),
        .init(id: "dumbbell-hip-thrust", muscle: .glutes, pattern: .hinge, demand: .moderate, extraEquipment: [.adjustableBench]),

        // Single leg
        .init(id: "bulgarian-split-squat", muscle: .quads, pattern: .singleLeg, demand: .moderate, extraEquipment: [.adjustableBench]),
        .init(id: "dumbbell-split-squat", muscle: .quads, pattern: .singleLeg, demand: .moderate),
        .init(id: "split-squat", muscle: .quads, pattern: .singleLeg, demand: .low),
        .init(id: "reverse-lunge", muscle: .glutes, pattern: .singleLeg, demand: .moderate),
        .init(id: "bodyweight-reverse-lunge", muscle: .glutes, pattern: .singleLeg, demand: .low),
        .init(id: "walking-lunge", muscle: .glutes, pattern: .singleLeg, demand: .low),
        .init(id: "single-leg-romanian-deadlift", muscle: .hamstrings, pattern: .singleLeg, demand: .moderate),
        .init(id: "kettlebell-reverse-lunge", muscle: .glutes, pattern: .singleLeg, demand: .moderate),

        // Accessories
        .init(id: "lateral-raise", muscle: .shoulders, pattern: .isolation, demand: .low),
        .init(id: "bicep-curl", muscle: .arms, pattern: .elbowFlexion, demand: .low),
        .init(id: "tricep-pushdown", muscle: .arms, pattern: .elbowExtension, demand: .low),
        .init(id: "bodyweight-calf-raise", muscle: .calves, pattern: .calfRaise, demand: .low),
        .init(id: "leg-curl", muscle: .hamstrings, pattern: .isolation, demand: .low),
        .init(id: "leg-extension", muscle: .quads, pattern: .isolation, demand: .low),

        // Core and carries
        .init(id: "plank", muscle: .core, pattern: .core, demand: .low),
        .init(id: "side-plank", muscle: .core, pattern: .core, demand: .low),
        .init(id: "dead-bug", muscle: .core, pattern: .core, demand: .low),
        .init(id: "cable-pallof-press", muscle: .core, pattern: .core, demand: .low),
        .init(id: "dumbbell-farmers-walk", muscle: .fullBody, pattern: .carry, demand: .moderate),
        .init(id: "kettlebell-farmers-walk", muscle: .fullBody, pattern: .carry, demand: .moderate)
    ]

    static var reviewedExerciseIDs: Set<String> { Set(specs.map(\.id)) }

    static func makePool(from catalog: [ExerciseDefinition]) -> [CuratedExerciseDefinition] {
        let definitions = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        return specs.map { spec in
            let exercise = definitions[spec.id]
            let isAccessory = [.isolation, .elbowFlexion, .elbowExtension, .calfRaise, .core].contains(spec.pattern)
            let defaultSets = isAccessory ? 2 : 3
            let repetitions = isAccessory ? RepRange(10, 15) : RepRange(6, 10)
            let equipment = exercise.map { requiredEquipment(for: $0) }
                .orElse(fallbackEquipment(for: spec.id))
                .union(spec.extraEquipment)
            return CuratedExerciseDefinition(
                catalogID: spec.id,
                name: exercise?.name ?? fallbackName(for: spec.id),
                primaryMuscleGroup: spec.muscle,
                movementPattern: spec.pattern,
                requiredEquipment: equipment,
                recoveryDemand: spec.demand,
                defaultSets: defaultSets,
                repRange: repetitions,
                targetRPE: isAccessory ? 7 : 7.5,
                restSeconds: spec.demand == .high ? 150 : (isAccessory ? 75 : 105),
                secondsPerSet: 45,
                transitionSeconds: 60,
                loadIncrement: loadIncrement(for: equipment)
            )
        }
    }

    private static func fallbackName(for identifier: String) -> String {
        if identifier == "ohp" { return "Barbell Overhead Press" }
        return identifier
            .replacingOccurrences(of: "db", with: "dumbbell")
            .replacingOccurrences(of: "trx", with: "TRX")
            .split(separator: "-")
            .map { word in word == "TRX" ? "TRX" : word.capitalized }
            .joined(separator: " ")
    }

    private static func fallbackEquipment(for identifier: String) -> Set<EquipmentID> {
        if identifier.contains("dumbbell") || identifier.contains("-db-") || identifier.hasPrefix("db-") {
            return [.dumbbell]
        }
        if identifier.contains("kettlebell") { return [.kettlebell] }
        if identifier.contains("cable") || identifier.contains("pulldown") || identifier == "tricep-pushdown" {
            return [.cableMachine]
        }
        if identifier.contains("pull-up") { return [.pullUpBar] }
        if identifier.contains("trx") || identifier.contains("ring-row") { return [.suspensionTrainer] }
        if identifier.contains("machine") || identifier.contains("leg-press") || identifier == "leg-curl" || identifier == "leg-extension" {
            return [.selectorizedMachine]
        }
        let bodyweightIDs: Set<String> = [
            "push-up", "incline-push-ups", "decline-push-up", "bodyweight-overhead-press",
            "pike-push-ups", "split-squat", "bodyweight-reverse-lunge", "walking-lunge",
            "bodyweight-calf-raise", "plank", "side-plank", "dead-bug"
        ]
        if bodyweightIDs.contains(identifier) { return [.bodyweight] }
        return [.barbell]
    }

    private static func requiredEquipment(for exercise: ExerciseDefinition) -> Set<EquipmentID> {
        if exercise.isBodyweight { return [.bodyweight] }
        switch exercise.equipment?.lowercased() {
        case "barbell": return [.barbell]
        case "dumbbell": return [.dumbbell]
        case "kettlebell": return [.kettlebell]
        case "cable": return [.cableMachine]
        case "pull_up_bar": return [.pullUpBar]
        case "resistance_band", "loop_band": return [.resistanceBand]
        case "suspension_trainer", "rings": return [.suspensionTrainer]
        case "medicine_ball": return [.medicineBall]
        case nil, "bodyweight": return [.bodyweight]
        default: return [.selectorizedMachine]
        }
    }

    private static func loadIncrement(for equipment: Set<EquipmentID>) -> Double? {
        if equipment.contains(.barbell) || equipment.contains(.cableMachine) || equipment.contains(.selectorizedMachine) {
            return 5
        }
        if equipment.contains(.dumbbell) || equipment.contains(.kettlebell) { return 2.5 }
        return nil
    }
}

private extension Optional where Wrapped == Set<EquipmentID> {
    func orElse(_ fallback: @autoclosure () -> Set<EquipmentID>) -> Set<EquipmentID> {
        self ?? fallback()
    }
}
