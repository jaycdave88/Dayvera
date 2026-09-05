import Foundation

enum NutritionGoal: String, Codable, CaseIterable, Identifiable {
    case gain = "Muscle gain", recomp = "Recomposition", maintain = "Maintenance", loss = "Fat loss"
    var id: String { rawValue }
    var proteinRange: ClosedRange<Double> { self == .recomp || self == .loss ? 1.8...2.2 : 1.6...2.2 }
    var defaultProtein: Double { self == .recomp || self == .loss ? 2 : 1.8 }
    var defaultOffset: Double { self == .gain ? 0.05 : self == .loss ? -0.10 : 0 }
    var trendBand: ClosedRange<Double> {
        switch self { case .gain: 0.1...0.25; case .loss: -0.5 ... -0.25; default: -0.1...0.1 }
    }
}

enum NutritionSex: String, Codable, CaseIterable, Identifiable {
    case female = "Female equation", male = "Male equation", unspecified = "Use both estimates"
    var id: String { rawValue }
    var coefficient: Double { self == .male ? 5 : self == .female ? -161 : -78 }
}

enum NutritionActivity: String, Codable, CaseIterable, Identifiable {
    case sedentary = "Mostly seated", light = "Lightly active", moderate = "Moderately active", high = "Very active"
    var id: String { rawValue }
    var factor: Double { switch self { case .sedentary: 1.2; case .light: 1.375; case .moderate: 1.55; case .high: 1.725 } }
    var detail: String {
        switch self {
        case .sedentary: "Mostly seated work and little regular exercise."
        case .light: "Some daily walking and light training."
        case .moderate: "Regular movement and several substantial training sessions."
        case .high: "Physically active work and/or frequent demanding training."
        }
    }
}

struct NutritionProfile: Codable, Equatable {
    var age = 30
    var sex = NutritionSex.unspecified
    var heightCM = 170.0
    var weightKG = 70.0
    var bodyFatPercent: Double?
    var activity = NutritionActivity.light
    var trainingDays = 4
    var trainingMinutes = 60
    var experience = "Intermediate"
    var goal = NutritionGoal.gain
    var proteinPerKG = 1.8
    var calorieOffset = 0.05
    var cyclesCalories = false
    var musclePriorities: Set<MuscleGroup> = []
    var usesMetric = false
    var needsSupervision = false
    var illnessOrSymptoms = false
    var confirmedEligibility = false
    var measurementSource = "User entered"
    var measurementDate = Date.now
    var completedSetup = false
}

struct NutritionAmounts: Codable, Equatable, Sendable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    static let zero = Self(calories: 0, protein: 0, carbs: 0, fat: 0)
    var isValid: Bool { [calories, protein, carbs, fat].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 100_000 } }
    var macroCalories: Double { protein * 4 + carbs * 4 + fat * 9 }
    func scaled(_ multiplier: Double) -> Self {
        Self(calories: calories * multiplier, protein: protein * multiplier, carbs: carbs * multiplier, fat: fat * multiplier)
    }
    static func + (lhs: Self, rhs: Self) -> Self {
        Self(calories: lhs.calories + rhs.calories, protein: lhs.protein + rhs.protein,
             carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat)
    }
}

struct NutritionTarget: Codable, Equatable {
    let rmr: Double
    let maintenance: Double
    let maintenanceLow: Double
    let maintenanceHigh: Double
    let averageCalories: Double
    let trainingDay: NutritionAmounts
    let restDay: NutritionAmounts
    let proteinLow: Double
    let proteinHigh: Double
    let fatLow: Double
    let fatHigh: Double
    let notes: [String]
    let version: String
    func amounts(training: Bool) -> NutritionAmounts { training ? trainingDay : restDay }
}

enum FoodProvenance: String, Codable, Sendable {
    case database = "Database + entered portion"
    case photo = "Photo-estimated portion"
    case manual = "Entered from label or manually"
}

struct FoodPortion: Codable, Hashable, Sendable {
    let label: String
    let grams: Double
}

struct CatalogFood: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let nutrients: NutritionAmounts // per 100 g
    let portions: [FoodPortion]
}

/// Embedded snapshots keep a meal atomic and independent of future catalog edits.
struct FoodEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// User-facing quantity. `grams` remains the canonical amount used for nutrient math.
    var amount: Double
    var unit: String
    var count: Double
    var gramsPerUnit: Double
    var grams: Double
    var nutrients: NutritionAmounts
    var catalogID: String?
    var catalogVersion: String?
    var provenance: FoodProvenance
    var portionNote: String = ""

    init(id: UUID = UUID(), name: String, grams: Double, nutrients: NutritionAmounts,
         catalogID: String? = nil, catalogVersion: String? = nil, provenance: FoodProvenance,
         portionNote: String = "", amount: Double? = nil, unit: String = "g",
         count: Double = 1, gramsPerUnit: Double? = nil) {
        self.id = id
        self.name = name
        self.grams = grams
        self.nutrients = nutrients
        self.catalogID = catalogID
        self.catalogVersion = catalogVersion
        self.provenance = provenance
        self.portionNote = portionNote
        let resolvedAmount = amount ?? (unit == "g" ? grams : 1)
        self.amount = resolvedAmount
        self.unit = unit
        self.count = count
        self.gramsPerUnit = gramsPerUnit ?? (unit == "g" ? 1 : grams / max(resolvedAmount * count, 0.000_001))
    }

    var quantityDescription: String {
        let value = amount.formatted(.number.precision(.fractionLength(0...2)))
        let multiplier = count == 1 ? "" : " × \(count.formatted(.number.precision(.fractionLength(0...2))))"
        return "\(value) \(unit)\(multiplier)"
    }

    var quantityIsValid: Bool {
        let derivedGrams = amount * count * gramsPerUnit
        return amount.isFinite && amount > 0 && count.isFinite && count > 0 && gramsPerUnit.isFinite && gramsPerUnit > 0 &&
        grams.isFinite && (0.1...10_000).contains(grams) && !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        abs(derivedGrams - grams) <= max(0.01, grams * 0.001)
    }

    mutating func updateQuantity(amount: Double, unit: String, count: Double, gramsPerUnit: Double) {
        let updatedGrams = amount * count * gramsPerUnit
        if grams > 0, updatedGrams.isFinite, updatedGrams > 0 {
            nutrients = nutrients.scaled(updatedGrams / grams)
        }
        self.amount = amount
        self.unit = unit
        self.count = count
        self.gramsPerUnit = gramsPerUnit
        grams = updatedGrams
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, amount, unit, count, gramsPerUnit, grams, nutrients, catalogID, catalogVersion, provenance, portionNote
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        grams = try values.decode(Double.self, forKey: .grams)
        nutrients = try values.decode(NutritionAmounts.self, forKey: .nutrients)
        catalogID = try values.decodeIfPresent(String.self, forKey: .catalogID)
        catalogVersion = try values.decodeIfPresent(String.self, forKey: .catalogVersion)
        provenance = try values.decode(FoodProvenance.self, forKey: .provenance)
        portionNote = try values.decodeIfPresent(String.self, forKey: .portionNote) ?? ""
        let decodedAmount = try values.decodeIfPresent(Double.self, forKey: .amount)
        let decodedUnit = try values.decodeIfPresent(String.self, forKey: .unit)
        let decodedCount = try values.decodeIfPresent(Double.self, forKey: .count)
        let decodedGramsPerUnit = try values.decodeIfPresent(Double.self, forKey: .gramsPerUnit)
        if let decodedAmount, let decodedUnit, let decodedCount, let decodedGramsPerUnit,
           decodedAmount.isFinite, decodedAmount > 0, decodedCount.isFinite, decodedCount > 0,
           decodedGramsPerUnit.isFinite, decodedGramsPerUnit > 0,
           !decodedUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           abs(decodedAmount * decodedCount * decodedGramsPerUnit - grams) <= max(0.01, grams * 0.001) {
            amount = decodedAmount
            unit = decodedUnit
            count = decodedCount
            gramsPerUnit = decodedGramsPerUnit
        } else {
            // Legacy and partially written entries remain usable because their canonical grams and nutrient snapshot are authoritative.
            amount = grams
            unit = "g"
            count = 1
            gramsPerUnit = 1
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(amount, forKey: .amount)
        try values.encode(unit, forKey: .unit)
        try values.encode(count, forKey: .count)
        try values.encode(gramsPerUnit, forKey: .gramsPerUnit)
        try values.encode(grams, forKey: .grams)
        try values.encode(nutrients, forKey: .nutrients)
        try values.encodeIfPresent(catalogID, forKey: .catalogID)
        try values.encodeIfPresent(catalogVersion, forKey: .catalogVersion)
        try values.encode(provenance, forKey: .provenance)
        try values.encode(portionNote, forKey: .portionNote)
    }
}

struct MealSaveResult: Equatable {
    let mealID: UUID
    let date: Date
    let dayKey: String
    let total: NutritionAmounts
    let created: Bool
}

struct NutritionIntake: Equatable {
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var source: String
    var complete: Bool
    static let missing = Self(source: "Not logged", complete: false)
    init(calories: Double? = nil, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil,
         source: String, complete: Bool) {
        self.calories = calories; self.protein = protein; self.carbs = carbs; self.fat = fat
        self.source = source; self.complete = complete
    }
    init(_ amounts: NutritionAmounts, source: String, complete: Bool) {
        self.init(calories: amounts.calories, protein: amounts.protein, carbs: amounts.carbs,
                  fat: amounts.fat, source: source, complete: complete)
    }
}

struct NutritionWeightPoint: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let kg: Double
    let source: String
}

struct NutritionDailyEvidence {
    let date: Date
    let intake: NutritionIntake
    let targetCalories: Double?
}

enum NutritionError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}

extension Double {
    var nutritionCalories: String { "\(Int((self / 50).rounded() * 50))" }
    var nutritionGrams: String { "\(Int((self / 5).rounded() * 5))" }
}
