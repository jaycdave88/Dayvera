import Foundation

enum NutritionEngine {
    static let version = "1.0-mifflin-conservative"

    static func calculate(_ p: NutritionProfile, calorieOverride: Double? = nil) throws -> NutritionTarget {
        guard p.confirmedEligibility, p.age >= 18, !p.needsSupervision else {
            throw NutritionError.invalid("Personal targets are for adults who do not need supervised nutrition. You can still keep a food journal.")
        }
        guard (18...100).contains(p.age), p.heightCM.isFinite, (120...230).contains(p.heightCM),
              p.weightKG.isFinite, (35...300).contains(p.weightKG), (0...7).contains(p.trainingDays),
              (10...240).contains(p.trainingMinutes), p.proteinPerKG.isFinite,
              p.goal.proteinRange.contains(p.proteinPerKG), p.calorieOffset.isFinite else {
            throw NutritionError.invalid("Check your age, height, weight, training and protein settings. Values outside this calculator’s scope need individualized guidance.")
        }
        if let bf = p.bodyFatPercent, !bf.isFinite || !(3...65).contains(bf) {
            throw NutritionError.invalid("Check the body-fat percentage or leave it blank.")
        }
        let bmi = p.weightKG / pow(p.heightCM / 100, 2)
        guard p.goal != .loss || bmi >= 18.5 else {
            throw NutritionError.invalid("Automated fat-loss targets are unavailable at this body weight. Choose maintenance or seek individualized guidance.")
        }
        let allowedOffset: ClosedRange<Double> = p.goal == .gain ? 0.05...0.10 : p.goal == .loss ? -0.15 ... -0.10 : 0...0
        guard allowedOffset.contains(p.calorieOffset) else { throw NutritionError.invalid("Choose a calorie change within your goal’s planning range.") }
        let rmr = 10 * p.weightKG + 6.25 * p.heightCM - 5 * Double(p.age) + p.sex.coefficient
        let tdee = rmr * p.activity.factor
        let startingOffset = p.illnessOrSymptoms ? max(0, p.calorieOffset) : p.calorieOffset
        let calories = calorieOverride ?? tdee * (1 + startingOffset)
        guard !p.illnessOrSymptoms || calories >= tdee else {
            throw NutritionError.invalid("Calorie deficits are paused while illness or concerning symptoms are reported.")
        }
        // These guardrails are conservative product limits, not clinical thresholds.
        let lower = max(rmr, tdee * (p.goal == .loss ? 0.85 : p.goal == .gain ? 1 : 0.9))
        let upper = tdee * (p.goal == .gain ? 1.15 : p.goal == .loss ? 1 : 1.1)
        guard calories.isFinite, (lower...upper).contains(calories) else {
            throw NutritionError.invalid("This scenario is outside the conservative range for your goal. Review your profile or choose a smaller change.")
        }
        let delta = p.cyclesCalories && (1...6).contains(p.trainingDays) ? 200.0 : 0
        let train = calories + delta * Double(7 - p.trainingDays) / 7
        let rest = calories - delta * Double(p.trainingDays) / 7
        guard min(train, rest) >= max(rmr, tdee * 0.85) else {
            throw NutritionError.invalid("Rest-day cycling would make intake too low. Use an even daily target.")
        }
        func macros(_ energy: Double) throws -> NutritionAmounts {
            let protein = p.weightKG * p.proteinPerKG
            let minFat = max(p.weightKG * 0.6, energy * 0.20 / 9)
            let maxFat = energy * 0.35 / 9
            guard minFat <= maxFat else { throw NutritionError.invalid("These targets cannot accommodate the fat planning range. Review your calorie and body-weight inputs.") }
            let fat = max(minFat, energy * 0.25 / 9)
            let carbs = (energy - protein * 4 - fat * 9) / 4
            guard carbs >= 0 else { throw NutritionError.invalid("Protein and fat leave no room for carbohydrates. Review your settings.") }
            return NutritionAmounts(calories: energy, protein: protein, carbs: carbs, fat: fat)
        }
        let training = try macros(train), resting = try macros(rest)
        var notes = ["An estimate, not a metabolic measurement. The working range is a heuristic, not a statistical confidence interval."]
        if p.sex == .unspecified { notes.append("Uses the midpoint of both sex-based equations; individual needs may differ.") }
        if training.carbs / p.weightKG < 2 && p.trainingDays >= 3 {
            notes.append("Carbohydrate availability may be limited for frequent training. Review performance and total intake.")
        }
        if p.illnessOrSymptoms { notes.append("Calorie reductions are paused while illness or concerning symptoms are reported.") }
        return NutritionTarget(rmr: rmr, maintenance: tdee,
            maintenanceLow: (p.sex == .unspecified ? (rmr - 83) * p.activity.factor : tdee) * 0.85,
            maintenanceHigh: (p.sex == .unspecified ? (rmr + 83) * p.activity.factor : tdee) * 1.15,
            averageCalories: calories, trainingDay: training, restDay: resting,
            proteinLow: p.weightKG * p.goal.proteinRange.lowerBound,
            proteinHigh: p.weightKG * p.goal.proteinRange.upperBound,
            fatLow: max(p.weightKG * 0.6, calories * 0.2 / 9), fatHigh: calories * 0.35 / 9,
            notes: notes, version: version)
    }
}
