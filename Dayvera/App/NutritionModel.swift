import Combine
import Foundation
import SwiftData

@MainActor final class NutritionModel: ObservableObject {
    @Published private(set) var profile: NutritionProfile
    @Published private(set) var meals: [MealRecord] = []
    @Published private(set) var days: [NutritionDayRecord] = []
    @Published private(set) var measurements: [BodyMeasurementRecord] = []
    @Published private(set) var revisions: [NutritionTargetRevision] = []
    @Published private(set) var adjustments: [NutritionAdjustmentRecord] = []
    @Published private(set) var dietarySamples: [DietarySample] = []
    @Published private(set) var healthImportEnabled = false
    @Published private(set) var isRefreshing = false
    @Published var error: String?
    @Published private(set) var healthError: String?
    @Published private(set) var healthRefreshedAt: Date?
    let catalog: FoodCatalogStore?
    let recognition: any FoodRecognizing
    private let privateStore: any PrivateAppStatePersisting
    private let health: any NutritionHealthProviding
    private var context: ModelContext?
    private var healthWeights: [MetricSample] = []
    private var queuedRefresh = false

    init(privateStore: any PrivateAppStatePersisting = ApplicationSupportPrivateAppStateStore(),
         health: (any NutritionHealthProviding)? = nil,
         recognition: (any FoodRecognizing)? = nil) {
        self.privateStore = privateStore; self.health = health ?? NutritionHealthService(); self.recognition = recognition ?? AppleFoodRecognitionService()
        profile = privateStore.data(forKey: "nutritionProfile").flatMap { try? JSONDecoder().decode(NutritionProfile.self, from: $0) } ?? NutritionProfile()
        healthImportEnabled = privateStore.data(forKey: "nutritionHealthEnabled") == Data([1])
        catalog = try? FoodCatalogStore()
    }

    func attach(_ supplied: ModelContext) {
        guard context == nil else { return }
        // Isolate rollback from an in-progress workout in the UI context.
        context = ModelContext(supplied.container); context?.autosaveEnabled = false
        reload()
    }
    func reload() {
        guard let context else { return }
        do {
            meals = try context.fetch(FetchDescriptor<MealRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
            days = try context.fetch(FetchDescriptor<NutritionDayRecord>())
            measurements = try context.fetch(FetchDescriptor<BodyMeasurementRecord>(sortBy: [SortDescriptor(\.date)]))
            revisions = try context.fetch(FetchDescriptor<NutritionTargetRevision>(sortBy: [SortDescriptor(\.effectiveDate), SortDescriptor(\.createdAt)]))
            adjustments = try context.fetch(FetchDescriptor<NutritionAdjustmentRecord>(sortBy: [SortDescriptor(\.evaluatedAt, order: .reverse)]))
        } catch { self.error = "Nutrition history could not be loaded. \(error.localizedDescription)" }
    }
    private func transaction(_ body: (ModelContext) throws -> Void) throws {
        guard let context else { throw NutritionError.invalid("Nutrition storage is not ready. Try reopening the screen.") }
        do { try body(context); try context.save(); reload() }
        catch { context.rollback(); reload(); throw error }
    }

    func saveProfile(_ value: NutritionProfile) throws {
        var updated = value; updated.completedSetup = true
        var target: NutritionTarget?
        if updated.age < 18 || updated.needsSupervision || !updated.confirmedEligibility { target = nil }
        else { target = try NutritionEngine.calculate(updated) }
        if updated.illnessOrSymptoms, let current = self.target(on: .now),
           let proposed = target, proposed.averageCalories < current.averageCalories {
            // Saving a safety flag must not itself lower an existing target.
            // An incompatible goal change must be resolved before saving.
            target = try NutritionEngine.calculate(updated, calorieOverride: current.averageCalories)
        }
        let encoded = try JSONEncoder().encode(updated)
        let old = privateStore.data(forKey: "nutritionProfile")
        guard privateStore.set(encoded, forKey: "nutritionProfile") else { throw NutritionError.invalid("Your profile could not be securely saved.") }
        do {
            try transaction { context in
                for adjustment in adjustments where adjustment.status == "pending" { adjustment.status = "superseded" }
                if let target {
                    let effective = revisions.isEmpty ? Calendar.current.startOfDay(for: .now) : Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
                    context.insert(try NutritionTargetRevision(target: target, profile: updated, effectiveDate: effective, reason: "Profile and goal settings"))
                }
            }
        } catch {
            if let old { _ = privateStore.set(old, forKey: "nutritionProfile") } else { _ = privateStore.removeData(forKey: "nutritionProfile") }
            throw error
        }
        profile = updated
    }

    func revision(on date: Date) -> NutritionTargetRevision? { revisions.last { $0.effectiveDate <= date } }
    func target(on date: Date) -> NutritionTarget? {
        guard profile.confirmedEligibility, profile.age >= 18, !profile.needsSupervision else { return nil }
        return revision(on: date)?.target
    }
    func day(on date: Date) -> NutritionDayRecord? { days.first { $0.dayKey == NutritionStore.dayKey(date) } }
    func meals(on date: Date) -> [MealRecord] { meals.filter { NutritionStore.mealDayKey($0) == NutritionStore.dayKey(date) } }
    func intake(on date: Date) -> NutritionIntake {
        let day = day(on: date), source = day?.source ?? "meals", complete = day?.isComplete ?? false
        if source == "manual" {
            return day?.manualAmounts.map { NutritionIntake($0, source: "Daily total", complete: complete) } ?? .missing
        }
        if source.hasPrefix("health:") {
            guard healthImportEnabled, healthError == nil else { return .missing }
            let bundle = String(source.dropFirst(7))
            let samples = dietarySamples.filter { $0.sourceID == bundle && Calendar.current.isDate($0.date, inSameDayAs: date) }
            func sum(_ key: String) -> Double? {
                let values = samples.filter { $0.nutrient == key }; return values.isEmpty ? nil : values.reduce(0) { $0 + $1.value }
            }
            return NutritionIntake(calories: sum("calories"), protein: sum("protein"), carbs: sum("carbs"), fat: sum("fat"),
                                   source: samples.first?.sourceName ?? "No Health samples", complete: complete && !samples.isEmpty)
        }
        let entries = meals(on: date)
        guard !entries.isEmpty else { return .missing }
        return NutritionIntake(entries.reduce(.zero) { $0 + $1.total }, source: "Dayvera meals", complete: complete)
    }

    func updateDay(_ date: Date, source: String? = nil, complete: Bool? = nil, training: Bool? = nil, manual: NutritionAmounts? = nil) throws {
        if let manual, !manual.isValid { throw NutritionError.invalid("Enter finite, nonnegative nutrition values.") }
        try transaction { context in
            let record = day(on: date) ?? NutritionDayRecord(dayKey: NutritionStore.dayKey(date))
            if record.modelContext == nil { context.insert(record) }
            if let source { record.source = source; record.isComplete = false }
            if let complete { record.isComplete = complete }
            if let training { record.trainingDay = training }
            if let manual { record.manualData = try JSONEncoder().encode(manual); record.source = "manual"; record.isComplete = false }
        }
    }

    @discardableResult
    func saveMeal(id: UUID? = nil, name: String, date: Date, entries: [FoodEntry], photo: Data?) throws -> MealSaveResult {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120,
              !entries.isEmpty, entries.count <= 100,
              entries.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 300 && $0.quantityIsValid && $0.nutrients.isValid }) else {
            throw NutritionError.invalid("Add a meal name and valid food portions before saving.")
        }
        let existingMeal = meals.first(where: { $0.id == id })
        let savedID = existingMeal?.id ?? UUID()
        let created = existingMeal == nil
        let newPhoto = try photo.map { try NutritionStore.savePhoto($0) }
        var previousPhoto: String?
        do {
            try transaction { context in
                if let existing = existingMeal {
                    let oldKey = NutritionStore.mealDayKey(existing)
                    days.first { $0.dayKey == oldKey }?.isComplete = false
                    existing.name = name; existing.date = date; existing.timeZoneID = TimeZone.current.identifier
                    existing.entriesData = try JSONEncoder().encode(entries)
                    if let newPhoto { previousPhoto = existing.photoFilename; existing.photoFilename = newPhoto }
                } else { context.insert(try MealRecord(id: savedID, date: date, name: name, entries: entries, photoFilename: newPhoto)) }
                day(on: date)?.isComplete = false
            }
            NutritionStore.removePhoto(previousPhoto)
        } catch { NutritionStore.removePhoto(newPhoto); throw error }
        return MealSaveResult(mealID: savedID, date: date, dayKey: NutritionStore.dayKey(date),
                              total: entries.reduce(.zero) { $0 + $1.nutrients }, created: created)
    }
    func deleteMeal(_ meal: MealRecord) throws {
        let photo = meal.photoFilename
        try transaction { context in
            days.first { $0.dayKey == NutritionStore.mealDayKey(meal) }?.isComplete = false
            context.delete(meal)
        }
        NutritionStore.removePhoto(photo)
    }
    func toggleFavorite(_ meal: MealRecord) throws { try transaction { _ in meal.favorite.toggle() } }
    func repeatMeal(_ meal: MealRecord, date: Date = .now) throws {
        try saveMeal(name: meal.name, date: date, entries: meal.entries, photo: nil)
    }
    func saveMeasurement(date: Date, weight: Double?, waist: Double?, hips: Double?, arm: Double?, thigh: Double?) throws {
        guard [weight, waist, hips, arm, thigh].contains(where: { $0 != nil }),
              [waist, hips, arm, thigh].compactMap({ $0 }).allSatisfy({ $0.isFinite && (5...300).contains($0) }),
              weight == nil || (weight!.isFinite && (20...400).contains(weight!)) else {
            throw NutritionError.invalid("Check the measurement values and units.")
        }
        try transaction { $0.insert(BodyMeasurementRecord(date: date, weightKG: weight, waistCM: waist, hipsCM: hips, armCM: arm, thighCM: thigh)) }
    }
    func deleteMeasurement(_ item: BodyMeasurementRecord) throws { try transaction { $0.delete(item) } }

    func updateHealthContext(_ snapshot: DailyHealthSnapshot) {
        healthWeights = snapshot.samples.filter { $0.kind == .bodyMass }
        objectWillChange.send()
    }
    var weightPoints: [NutritionWeightPoint] {
        // Consistent manual series takes priority; otherwise use the most recent Health source.
        let manual = measurements.compactMap { m in m.weightKG.map { NutritionWeightPoint(date: m.date, kg: $0, source: "Manual weigh-in") } }
        let source = healthWeights.max(by: { $0.endDate < $1.endDate })?.sourceIdentity
        let imported = healthWeights.filter { $0.sourceIdentity == source }.compactMap { s -> NutritionWeightPoint? in
            guard let kg = s.value, kg.isFinite, kg > 0 else { return nil }
            return NutritionWeightPoint(date: s.endDate, kg: kg, source: s.sourceName)
        }
        let chosen = manual.isEmpty ? imported : manual
        return Dictionary(grouping: chosen) { Calendar.current.startOfDay(for: $0.date) }.compactMap { date, points in
            NutritionAdaptationEngine.median(points.map(\.kg)).map { NutritionWeightPoint(date: date, kg: $0, source: points[0].source) }
        }.sorted { $0.date < $1.date }
    }
    var healthSources: [(id: String, name: String)] {
        Dictionary(grouping: dietarySamples, by: \.sourceID).map { (id: "health:" + $0.key, name: $0.value[0].sourceName) }.sorted { $0.name < $1.name }
    }
    func setHealthImport(_ enabled: Bool) async {
        do {
            if enabled { try await health.requestAccess() }
            guard privateStore.set(Data([enabled ? 1 : 0]), forKey: "nutritionHealthEnabled") else { throw NutritionError.invalid("The Health preference could not be saved.") }
            healthImportEnabled = enabled
            if enabled { await refreshHealth() } else { dietarySamples = []; healthRefreshedAt = nil }
        } catch { self.error = error.localizedDescription }
    }
    func refreshHealth() async {
        guard healthImportEnabled else { return }
        if isRefreshing { queuedRefresh = true; return }
        isRefreshing = true
        repeat {
            queuedRefresh = false
            do {
                let samples = try await health.fetch(since: Calendar.current.date(byAdding: .day, value: -35, to: .now)!, through: .now)
                if healthImportEnabled { dietarySamples = samples; healthRefreshedAt = .now; healthError = nil }
            } catch { dietarySamples = []; healthError = "Dietary import could not refresh. Imported totals are unavailable until the next successful refresh." }
        } while queuedRefresh && healthImportEnabled
        isRefreshing = false
    }

    func evidence(through date: Date = .now) -> [NutritionDailyEvidence] {
        (1...35).map { offset in
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: Calendar.current.startOfDay(for: date))!
            let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!.addingTimeInterval(-1)
            return NutritionDailyEvidence(date: day, intake: intake(on: day), targetCalories: revision(on: end)?.target?.amounts(training: self.day(on: day)?.trainingDay ?? false).calories)
        }
    }
    func evaluation(through date: Date = .now) -> NutritionAdaptationEngine.Evaluation? {
        guard let revision = revision(on: date), let target = revision.target, var profile = revision.profile else { return nil }
        profile.illnessOrSymptoms = self.profile.illnessOrSymptoms
        guard self.profile.confirmedEligibility, !self.profile.needsSupervision, self.profile.age >= 18 else { return nil }
        return NutritionAdaptationEngine.evaluate(profile: profile, target: target, weights: weightPoints, days: evidence(through: date), through: date)
    }
    func evaluateAdjustment(now: Date = .now) {
        guard let current = evaluation(through: now), let calories = current.proposedCalories,
              let revision = revision(on: now), let target = revision.target,
              revisions.last?.id == revision.id,
              now.timeIntervalSince(revision.effectiveDate) >= 28 * 86_400,
              !adjustments.contains(where: { $0.status == "pending" || now.timeIntervalSince($0.evaluatedAt) < 7 * 86_400 }),
              let previous = evaluation(through: now.addingTimeInterval(-7 * 86_400)),
              let priorCalories = previous.proposedCalories,
              (priorCalories - target.averageCalories) * (calories - target.averageCalories) > 0 else { return }
        do {
            try transaction { $0.insert(NutritionAdjustmentRecord(calories: calories, slope: current.slopePercent ?? 0,
                reason: current.reason, revisionID: revision.id, date: now)) }
        } catch { self.error = error.localizedDescription }
    }
    func accept(_ adjustment: NutritionAdjustmentRecord) throws {
        guard adjustment.status == "pending", let current = revision(on: .now), current.id == adjustment.targetRevisionID,
              Date.now.timeIntervalSince(adjustment.evaluatedAt) < 7 * 86_400,
              let evaluation = evaluation(), let candidate = evaluation.proposedCalories,
              abs(candidate - adjustment.proposedCalories) < 1 else {
            throw NutritionError.invalid("This suggestion is no longer current. Refresh and review your latest progress.")
        }
        try applyCalories(adjustment.proposedCalories, reason: adjustment.reason, adjustment: adjustment)
    }
    func dismiss(_ adjustment: NutritionAdjustmentRecord) throws { try transaction { _ in adjustment.status = "dismissed" } }
    func applyCalories(_ calories: Double, reason: String, adjustment: NutritionAdjustmentRecord? = nil) throws {
        guard let current = revision(on: .now), let currentTarget = current.target, var p = current.profile else { return }
        guard profile.confirmedEligibility, !profile.needsSupervision, profile.age >= 18 else { throw NutritionError.invalid("Personal targets are unavailable for this profile.") }
        p.illnessOrSymptoms = profile.illnessOrSymptoms
        if p.illnessOrSymptoms && calories < currentTarget.averageCalories { throw NutritionError.invalid("Calorie reductions are paused while illness or concerning symptoms are reported.") }
        let target = try NutritionEngine.calculate(p, calorieOverride: calories)
        try transaction { context in
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
            context.insert(try NutritionTargetRevision(target: target, profile: p, effectiveDate: tomorrow, reason: reason))
            for pending in adjustments where pending.status == "pending" { pending.status = pending.id == adjustment?.id ? "accepted" : "superseded" }
        }
    }

    func applyScenario(calories: Double, protein: Double, cycling: Bool) throws {
        guard let current = target(on: .now), var p = revision(on: .now)?.profile else { throw NutritionError.invalid("No current target.") }
        guard revisions.last?.effectiveDate ?? .distantPast <= .now else { throw NutritionError.invalid("A target change is already scheduled for tomorrow. Review it in target history before adding another.") }
        if profile.illnessOrSymptoms && calories < current.averageCalories { throw NutritionError.invalid("Calorie reductions are paused while illness or concerning symptoms are reported.") }
        p.proteinPerKG = protein; p.cyclesCalories = cycling; p.illnessOrSymptoms = profile.illnessOrSymptoms
        let target = try NutritionEngine.calculate(p, calorieOverride: calories)
        try transaction { context in
            context.insert(try NutritionTargetRevision(target: target, profile: p,
                effectiveDate: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!, reason: "Reviewed what-if scenario"))
            for pending in adjustments where pending.status == "pending" { pending.status = "superseded" }
        }
    }

    var underfuelingMessage: String? {
        guard let current = target(on: .now), revision(on: .now)?.profile?.goal == .gain else { return nil }
        let days = evidence().prefix(7).filter { $0.intake.complete && $0.intake.calories != nil }
        guard days.count >= 5 else { return nil }
        let average = days.reduce(0) { $0 + ($1.intake.calories ?? 0) } / Double(days.count)
        guard average < current.averageCalories * 0.9 else { return nil }
        return "Your last \(days.count) complete days average \(average.nutritionCalories) kcal, below the muscle-gain target. Intake may be insufficient for your stated goal. Check logging, portions and recent training before changing the target."
    }

    var observedMaintenance: Double? {
        guard let evaluation = evaluation(), evaluation.eligible, let slope = evaluation.slopePercent, abs(slope) <= 0.1 else { return nil }
        let days = evidence().prefix(21).filter { $0.intake.complete && $0.intake.calories != nil }
        guard days.count >= 18 else { return nil }
        return days.reduce(0) { $0 + ($1.intake.calories ?? 0) } / Double(days.count)
    }

    #if DEBUG
    func seedDemo() {
        guard !profile.completedSetup, meals.isEmpty else { return }
        var p = NutritionProfile(); p.confirmedEligibility = true; p.completedSetup = true
        p.weightKG = 76; p.heightCM = 178; p.sex = .male; p.activity = .moderate
        p.musclePriorities = [.glutes, .back, .shoulders]
        do {
            try saveProfile(p)
            guard let catalog, let rice = catalog.search("rice white cooked").first,
                  let chicken = catalog.search("chicken breast roasted").first else { return }
            let foods = [try catalog.entry(food: rice, grams: 200), try catalog.entry(food: chicken, grams: 180)]
            try saveMeal(name: "Chicken and rice bowl", date: .now, entries: foods, photo: nil)
            let target = try NutritionEngine.calculate(p)
            try transaction { context in
                context.insert(try NutritionTargetRevision(target: target, profile: p,
                    effectiveDate: Calendar.current.date(byAdding: .day, value: -35, to: .now)!, reason: "Demo starting estimate"))
                for index in 1...28 {
                    let date = Calendar.current.date(byAdding: .day, value: -index, to: .now)!
                    let record = NutritionDayRecord(dayKey: NutritionStore.dayKey(date))
                    record.source = "manual"; record.isComplete = index % 8 != 0
                    record.manualData = try JSONEncoder().encode(target.restDay.scaled(index % 5 == 0 ? 0.9 : 1))
                    context.insert(record)
                    context.insert(BodyMeasurementRecord(date: date, weightKG: 76 - Double(index) * 0.015 + Double(index % 3) * 0.08,
                        waistCM: index % 7 == 0 ? 80 : nil, hipsCM: nil, armCM: nil, thighCM: nil))
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    #endif
}
