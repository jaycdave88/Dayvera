import Foundation
import SwiftData

@Model final class MealRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var timeZoneID: String
    var name: String
    var entriesData: Data
    var photoFilename: String?
    var favorite: Bool = false
    init(id: UUID = UUID(), date: Date, name: String, entries: [FoodEntry], photoFilename: String? = nil) throws {
        self.id = id; self.date = date; timeZoneID = TimeZone.current.identifier
        self.name = name; entriesData = try JSONEncoder().encode(entries); self.photoFilename = photoFilename
    }
    var entries: [FoodEntry] { (try? JSONDecoder().decode([FoodEntry].self, from: entriesData)) ?? [] }
    var total: NutritionAmounts { entries.reduce(.zero) { $0 + $1.nutrients } }
}

@Model final class NutritionDayRecord {
    @Attribute(.unique) var dayKey: String
    /// "meals", "manual", or "health:<bundle ID>"; never sum overlapping sources.
    var source: String = "meals"
    var isComplete = false
    var manualData: Data?
    var trainingDay = false
    init(dayKey: String) { self.dayKey = dayKey }
    var manualAmounts: NutritionAmounts? {
        guard let manualData else { return nil }
        return try? JSONDecoder().decode(NutritionAmounts.self, from: manualData)
    }
}

@Model final class BodyMeasurementRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var weightKG: Double?
    var waistCM: Double?
    var hipsCM: Double?
    var armCM: Double?
    var thighCM: Double?
    init(date: Date, weightKG: Double?, waistCM: Double?, hipsCM: Double?, armCM: Double?, thighCM: Double?) {
        id = UUID(); self.date = date; self.weightKG = weightKG; self.waistCM = waistCM
        self.hipsCM = hipsCM; self.armCM = armCM; self.thighCM = thighCM
    }
}

@Model final class NutritionTargetRevision {
    @Attribute(.unique) var id: UUID
    var effectiveDate: Date
    var createdAt: Date
    var targetData: Data
    var profileData: Data
    var reason: String
    init(target: NutritionTarget, profile: NutritionProfile, effectiveDate: Date, reason: String) throws {
        id = UUID(); createdAt = .now; self.effectiveDate = effectiveDate; self.reason = reason
        targetData = try JSONEncoder().encode(target); profileData = try JSONEncoder().encode(profile)
    }
    var target: NutritionTarget? { try? JSONDecoder().decode(NutritionTarget.self, from: targetData) }
    var profile: NutritionProfile? { try? JSONDecoder().decode(NutritionProfile.self, from: profileData) }
}

@Model final class NutritionAdjustmentRecord {
    @Attribute(.unique) var id: UUID
    var evaluatedAt: Date
    var proposedCalories: Double
    var slopePercent: Double
    var evidenceDays: Int
    var reason: String
    var status: String = "pending"
    var targetRevisionID: UUID
    init(calories: Double, slope: Double, reason: String, revisionID: UUID, date: Date) {
        id = UUID(); evaluatedAt = date; proposedCalories = calories; slopePercent = slope
        evidenceDays = 21; self.reason = reason; targetRevisionID = revisionID
    }
}
