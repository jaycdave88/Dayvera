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
    var grams: Double
    var nutrients: NutritionAmounts
    var catalogID: String?
    var catalogVersion: String?
    var provenance: FoodProvenance
    var portionNote: String = ""
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
