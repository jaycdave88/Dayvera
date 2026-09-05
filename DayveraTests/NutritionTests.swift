import XCTest
import SwiftData
@testable import Dayvera

final class NutritionEngineTests: XCTestCase {
    func profile() -> NutritionProfile {
        var p = NutritionProfile(); p.confirmedEligibility = true; p.sex = .male
        p.weightKG = 80; p.heightCM = 180; p.age = 30; p.activity = .moderate
        return p
    }
    func testEnergyAndMacroConservation() throws {
        let t = try NutritionEngine.calculate(profile())
        XCTAssertEqual(t.rmr, 1780, accuracy: 0.001)
        XCTAssertEqual(t.maintenance, 2759, accuracy: 0.001)
        XCTAssertEqual(t.averageCalories, 2896.95, accuracy: 0.001)
        XCTAssertEqual(t.trainingDay.protein, 144, accuracy: 0.001)
        XCTAssertEqual(t.trainingDay.macroCalories, t.trainingDay.calories, accuracy: 0.001)
        XCTAssertLessThan(t.maintenanceLow, t.maintenance)
        XCTAssertGreaterThan(t.maintenanceHigh, t.maintenance)
    }
    func testAllGoalsAndCyclingPreserveWeeklyCalories() throws {
        for goal in NutritionGoal.allCases {
            for days in 0...7 {
                var p = profile(); p.goal = goal; p.proteinPerKG = goal.defaultProtein
                p.calorieOffset = goal.defaultOffset; p.cyclesCalories = true; p.trainingDays = days
                if goal == .loss && (5...6).contains(days) {
                    XCTAssertThrowsError(try NutritionEngine.calculate(p), "Cycling cannot breach the conservative rest-day floor")
                    continue
                }
                let t = try NutritionEngine.calculate(p)
                XCTAssertEqual(t.trainingDay.calories * Double(days) + t.restDay.calories * Double(7 - days), t.averageCalories * 7, accuracy: 0.001)
                XCTAssertEqual(t.trainingDay.protein, t.restDay.protein)
                XCTAssertGreaterThanOrEqual(t.restDay.calories, t.rmr)
            }
        }
    }
    func testEligibilityAndInvalidInputsFailClosed() {
        var p = profile(); p.age = 17; XCTAssertThrowsError(try NutritionEngine.calculate(p))
        p = profile(); p.needsSupervision = true; XCTAssertThrowsError(try NutritionEngine.calculate(p))
        p = profile(); p.weightKG = .nan; XCTAssertThrowsError(try NutritionEngine.calculate(p))
        p = profile(); p.proteinPerKG = 4; XCTAssertThrowsError(try NutritionEngine.calculate(p))
        p = profile(); p.goal = .loss; p.weightKG = 50; p.calorieOffset = -0.1; p.proteinPerKG = 2
        XCTAssertThrowsError(try NutritionEngine.calculate(p))
        XCTAssertThrowsError(try NutritionEngine.calculate(profile(), calorieOverride: 500))
    }
    func testBothEquationsWidenRange() throws {
        var p = profile(); let male = try NutritionEngine.calculate(p); p.sex = .unspecified
        let both = try NutritionEngine.calculate(p)
        XCTAssertGreaterThan(both.maintenanceHigh - both.maintenanceLow, male.maintenanceHigh - male.maintenanceLow)
    }
    func testIllnessPausesInitialDeficitAndOverrides() throws {
        var p = profile(); p.goal = .loss; p.calorieOffset = -0.1; p.proteinPerKG = 2
        p.illnessOrSymptoms = true
        let target = try NutritionEngine.calculate(p)
        XCTAssertEqual(target.averageCalories, target.maintenance, accuracy: 0.001)
        XCTAssertThrowsError(try NutritionEngine.calculate(p, calorieOverride: target.maintenance - 100))
    }
    func testAdaptationRequiresCompleteIntakeAndRegularWeights() throws {
        var p = profile(); p.goal = .gain
        let t = try NutritionEngine.calculate(p)
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
        let days = (1...28).map { offset -> NutritionDailyEvidence in
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            return NutritionDailyEvidence(date: date, intake: NutritionIntake(t.restDay, source: "Manual", complete: true), targetCalories: t.averageCalories)
        }
        let weights = days.map { NutritionWeightPoint(date: $0.date, kg: 80, source: "Scale") }
        let result = NutritionAdaptationEngine.evaluate(profile: p, target: t, weights: weights, days: days, through: now, calendar: calendar)
        XCTAssertEqual(result.proposedCalories!, t.averageCalories + 100, accuracy: 0.001)
        let incomplete = days.map { day -> NutritionDailyEvidence in
            var intake = day.intake; intake.complete = false
            return NutritionDailyEvidence(date: day.date, intake: intake, targetCalories: day.targetCalories)
        }
        XCTAssertNil(NutritionAdaptationEngine.evaluate(profile: p, target: t, weights: weights, days: incomplete, through: now).proposedCalories)
        XCTAssertNil(NutritionAdaptationEngine.evaluate(profile: p, target: t, weights: Array(weights.prefix(3)), days: days, through: now).proposedCalories)
        p.goal = .recomp; p.calorieOffset = 0; p.proteinPerKG = 2
        XCTAssertNil(NutritionAdaptationEngine.evaluate(profile: p, target: t, weights: weights, days: days, through: now).proposedCalories)
    }
    func testRobustSlopeDoesNotFollowOneSpike() {
        let now = Date.now
        let points = (0..<21).map { NutritionWeightPoint(date: now.addingTimeInterval(Double($0) * 86_400), kg: $0 == 10 ? 95 : 80, source: "Scale") }
        XCTAssertEqual(NutritionAdaptationEngine.slope(points)!, 0, accuracy: 0.001)
    }
}

@MainActor final class NutritionPersistenceTests: XCTestCase {
    private func schema() -> Schema {
        Schema([WorkoutTemplateRecord.self, WorkoutSessionRecord.self, MealRecord.self, NutritionDayRecord.self,
                BodyMeasurementRecord.self, NutritionTargetRevision.self, NutritionAdjustmentRecord.self])
    }
    private func model(store: NutritionMemoryStore = NutritionMemoryStore(), health: NutritionMockHealth? = nil) throws -> (NutritionModel, ModelContainer) {
        let schema = schema()
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let model = NutritionModel(privateStore: store, health: health, recognition: NutritionMockRecognition())
        model.attach(container.mainContext)
        return (model, container)
    }
    private var food: FoodEntry { FoodEntry(name: "Label food", grams: 100, nutrients: NutritionAmounts(calories: 200, protein: 20, carbs: 20, fat: 4), provenance: .manual) }

    func testLegacyStoreSurvivesModuleRenameAndAdditiveSchema() throws {
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(bundle.url(forResource: "legacy-workouts", withExtension: "store"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("default.store")
        try FileManager.default.copyItem(at: source, to: url)
        let schema = schema()
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let templates = try container.mainContext.fetch(FetchDescriptor<WorkoutTemplateRecord>())
        XCTAssertEqual(templates.first?.name, "Legacy migration fixture")
        let sessions = try container.mainContext.fetch(FetchDescriptor<WorkoutSessionRecord>())
        XCTAssertEqual(sessions.first?.notes, "Keep this history")
        XCTAssertEqual(sessions.first?.healthExportState, .exported)
        XCTAssertEqual(sessions.first?.id.uuidString, "00000000-0000-0000-0000-000000000102")
        container.mainContext.insert(try MealRecord(date: .now, name: "New meal", entries: [food]))
        try container.mainContext.save()
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<MealRecord>()), 1)
    }

    func testMealTransactionsSourceOverrideAndRepeat() throws {
        let (m, container) = try model(); let _ = container
        let now = Date.now
        XCTAssertNil(m.intake(on: now).calories)
        try m.saveMeal(name: "Lunch", date: now, entries: [food], photo: nil)
        XCTAssertEqual(m.intake(on: now).calories, 200)
        try m.updateDay(now, complete: true)
        let meal = try XCTUnwrap(m.meals.first)
        try m.repeatMeal(meal)
        XCTAssertEqual(m.intake(on: now).calories, 400)
        XCTAssertFalse(m.intake(on: now).complete)
        try m.updateDay(now, manual: NutritionAmounts(calories: 1500, protein: 120, carbs: 160, fat: 40))
        XCTAssertEqual(m.intake(on: now).calories, 1500)
        try m.updateDay(now, source: "meals")
        XCTAssertEqual(m.intake(on: now).calories, 400)
        try m.deleteMeal(meal)
        XCTAssertEqual(m.intake(on: now).calories, 200)
        try m.saveMeal(id: m.meals[0].id, name: "Edited", date: now, entries: [food, food], photo: nil)
        XCTAssertEqual(m.intake(on: now).calories, 400)
        XCTAssertThrowsError(try m.saveMeal(name: "Broken", date: now, entries: [], photo: nil))
        XCTAssertEqual(m.intake(on: now).calories, 400)
    }

    func testProfileFailureAndHistoricalTargetPreservation() throws {
        let store = NutritionMemoryStore(); let (m, container) = try model(store: store); let _ = container
        var p = NutritionProfile(); p.confirmedEligibility = true
        store.failsWrites = true
        XCTAssertThrowsError(try m.saveProfile(p)); XCTAssertFalse(m.profile.completedSetup)
        store.failsWrites = false; try m.saveProfile(p)
        let current = try XCTUnwrap(m.target(on: .now))
        p.goal = .maintain; p.calorieOffset = 0
        try m.saveProfile(p)
        XCTAssertEqual(m.target(on: .now), current)
        XCTAssertEqual(m.revisions.count, 2)
        XCTAssertTrue(m.revisions.last!.effectiveDate > .now)
    }

    func testHealthSourcesNeverMergeAndMissingMacrosRemainUnknown() async throws {
        let health = NutritionMockHealth()
        health.samples = [DietarySample(id: UUID(), date: .now, sourceID: "a", sourceName: "Tracker A", nutrient: "calories", value: 1800),
                          DietarySample(id: UUID(), date: .now, sourceID: "b", sourceName: "Tracker B", nutrient: "calories", value: 1900)]
        let (m, container) = try model(health: health); let _ = container
        await m.setHealthImport(true)
        try m.updateDay(.now, source: "health:a", complete: true)
        XCTAssertEqual(m.intake(on: .now).calories, 1800)
        XCTAssertNil(m.intake(on: .now).protein)
        health.samples = []; await m.refreshHealth()
        XCTAssertNil(m.intake(on: .now).calories)
        XCTAssertFalse(m.intake(on: .now).complete)
        health.fail = true; await m.refreshHealth()
        XCTAssertNotNil(m.healthError)
        XCTAssertNil(m.intake(on: .now).calories)
    }

    func testSavingIllnessCannotLowerExistingTarget() throws {
        let (m, container) = try model(); let _ = container
        var p = NutritionProfile(); p.confirmedEligibility = true; p.calorieOffset = 0.1
        try m.saveProfile(p)
        let original = try XCTUnwrap(m.target(on: .now))
        p.calorieOffset = 0.05; p.illnessOrSymptoms = true
        try m.saveProfile(p)
        XCTAssertTrue(m.profile.illnessOrSymptoms)
        XCTAssertEqual(m.revisions.last?.target?.averageCalories, original.averageCalories)
        XCTAssertThrowsError(try m.applyScenario(calories: original.averageCalories - 100, protein: 1.8, cycling: false))
    }

    func testCatalogAndInvalidRecognition() throws {
        let catalog = try FoodCatalogStore()
        XCTAssertGreaterThan(catalog.foods.count, 7000)
        let match = try XCTUnwrap(catalog.search("rice cooked").first)
        let entry = try catalog.entry(food: match, grams: 250, photo: true)
        XCTAssertEqual(entry.nutrients.calories, match.nutrients.calories * 2.5, accuracy: 0.001)
        XCTAssertEqual(entry.provenance, .photo)
        XCTAssertThrowsError(try catalog.entry(food: match, grams: .infinity))
        XCTAssertThrowsError(try AppleFoodRecognitionService.validate([RecognizedFood(name: "Rice", estimatedGrams: .nan, question: "")]))
        XCTAssertEqual(try AppleFoodRecognitionService.validate([]), [])
    }

    func testLegacyCalendarMarkersRemainRecognizable() {
        let now = Date.now, end = Date.now.addingTimeInterval(3600)
        XCTAssertTrue(CalendarService.isFallbackOwnedGymEvent(title: "Gym · Sleep Coach plan", note: "Created by Sleep Coach.", startDate: now, endDate: end, expectedStart: now, expectedEnd: end))
        XCTAssertFalse(CalendarService.isFallbackOwnedGymEvent(title: "Gym · Sleep Coach plan", note: "Someone else’s event", startDate: now, endDate: end, expectedStart: now, expectedEnd: end))
    }
}

private final class NutritionMemoryStore: PrivateAppStatePersisting {
    var removesLegacyDefaultsAfterSave = false
    var values: [String: Data] = [:]
    var failsWrites = false
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data, forKey key: String) -> Bool { if failsWrites { return false }; values[key] = data; return true }
    func removeData(forKey key: String) -> Bool { values.removeValue(forKey: key); return true }
}
@MainActor private final class NutritionMockHealth: NutritionHealthProviding {
    var samples: [DietarySample] = []
    var fail = false
    func requestAccess() async throws {}
    func fetch(since: Date, through: Date) async throws -> [DietarySample] {
        if fail { throw NutritionError.invalid("Test query failure") }
        return samples
    }
}
@MainActor private final class NutritionMockRecognition: FoodRecognizing {
    var unavailableReason: String? { "Fixture" }
    func recognize(imageData: Data) async throws -> [RecognizedFood] { [] }
}
