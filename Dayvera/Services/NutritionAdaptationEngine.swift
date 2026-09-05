import Foundation

enum NutritionAdaptationEngine {
    struct Evaluation {
        let slopePercent: Double?
        let completeDays: Int
        let eligible: Bool
        let reason: String
        let proposedCalories: Double?
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let i = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[i - 1] + sorted[i]) / 2 : sorted[i]
    }

    static func slope(_ weights: [NutritionWeightPoint]) -> Double? {
        guard weights.count >= 4, let middle = median(weights.map(\.kg)), middle > 0 else { return nil }
        var slopes: [Double] = []
        for i in weights.indices {
            for j in weights.indices where j > i {
                let days = weights[j].date.timeIntervalSince(weights[i].date) / 86_400
                if abs(days) >= 1 { slopes.append((weights[j].kg - weights[i].kg) / days * 7 / middle * 100) }
            }
        }
        return median(slopes)
    }

    static func evaluate(profile: NutritionProfile, target: NutritionTarget,
                         weights: [NutritionWeightPoint], days: [NutritionDailyEvidence],
                         through end: Date, calendar: Calendar = .current) -> Evaluation {
        let upper = calendar.startOfDay(for: end)
        let lower = calendar.date(byAdding: .day, value: -21, to: upper)!
        let window = days.filter { $0.date >= lower && $0.date < upper }
        let complete = window.filter { $0.intake.complete && $0.intake.calories != nil }
        let observations = weights.filter { $0.date >= lower && $0.date < upper }
        let trend = slope(observations)
        func result(_ reason: String, eligible: Bool = false, proposal: Double? = nil) -> Evaluation {
            Evaluation(slopePercent: trend, completeDays: complete.count, eligible: eligible, reason: reason, proposedCalories: proposal)
        }
        guard complete.count >= 18 else { return result("Confirm at least 18 complete intake days in the last 21 days before adjusting calories.") }
        for week in 0..<3 {
            let start = calendar.date(byAdding: .day, value: week * 7, to: lower)!
            let finish = calendar.date(byAdding: .day, value: 7, to: start)!
            let weekWeights = observations.filter { $0.date >= start && $0.date < finish }
            guard Set(weekWeights.map { calendar.startOfDay(for: $0.date) }).count >= 4 else {
                return result("At least four weigh-in days each week are needed. Daily fluctuations are normal.")
            }
        }
        guard Set(observations.map(\.source)).count == 1 else { return result("Use a consistent weight source before adjusting targets.") }
        let adherence = complete.compactMap { day -> Double? in
            guard let intake = day.intake.calories, let goal = day.targetCalories, goal > 0 else { return nil }
            return abs(intake - goal) / goal
        }
        guard adherence.count == complete.count, adherence.reduce(0, +) / Double(adherence.count) <= 0.10 else {
            return result("First work toward your current target; logged intake has differed by more than 10% on average.")
        }
        guard let trend else { return result("More weight observations are needed.") }
        guard profile.goal != .recomp else { return result("For recomposition, review strength and measurements alongside weight. Scale change alone does not justify a calorie change.", eligible: true) }
        guard !profile.goal.trendBand.contains(trend) else { return result("Your weight trend is within the planning range. Keep the current target.", eligible: true) }
        let direction = trend < profile.goal.trendBand.lowerBound ? 1.0 : -1.0
        guard !(direction < 0 && (profile.illnessOrSymptoms || trend < -0.75)) else {
            return result("Calorie reductions are paused. Review illness, symptoms, and recent weight changes.")
        }
        let candidate = target.averageCalories + direction * min(100, target.averageCalories * 0.05)
        guard (try? NutritionEngine.calculate(profile, calorieOverride: candidate)) != nil else {
            return result("A further change would exceed this calculator’s conservative limits. Review the profile or seek individualized guidance.")
        }
        return result(direction > 0 ? "Weight is trending below your goal’s planning range. A modest increase may help." : "Weight is trending above your goal’s planning range. Consider a modest reduction.", eligible: true, proposal: candidate)
    }
}
