import Foundation
import HealthKit

struct DietarySample: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let sourceID: String
    let sourceName: String
    let nutrient: String
    let value: Double
}

@MainActor protocol NutritionHealthProviding {
    func requestAccess() async throws
    func fetch(since: Date, through: Date) async throws -> [DietarySample]
}

@MainActor final class NutritionHealthService: NutritionHealthProviding {
    private let store = HKHealthStore()
    private static let identifiers: [(HKQuantityTypeIdentifier, String)] = [
        (.dietaryEnergyConsumed, "calories"), (.dietaryProtein, "protein"),
        (.dietaryCarbohydrates, "carbs"), (.dietaryFatTotal, "fat")
    ]
    func requestAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw NutritionError.invalid("Apple Health is unavailable on this device.") }
        let types = Set(Self.identifiers.map { HKQuantityType.quantityType(forIdentifier: $0.0)! })
        try await store.requestAuthorization(toShare: [], read: types)
    }
    func fetch(since: Date, through: Date) async throws -> [DietarySample] {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: through, options: .strictStartDate)
        var result: [DietarySample] = []
        for (identifier, nutrient) in Self.identifiers {
            let type = HKQuantityType.quantityType(forIdentifier: identifier)!
            let query = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate)], limit: 50_000)
            let samples = try await query.result(for: store)
            guard samples.count < 50_000 else { throw NutritionError.invalid("Dietary history exceeded the bounded import window. No partial totals were used.") }
            let unit: HKUnit = nutrient == "calories" ? .kilocalorie() : .gram()
            result += samples.compactMap { sample in
                let value = sample.quantity.doubleValue(for: unit)
                guard value.isFinite, value >= 0 else { return nil }
                return DietarySample(id: sample.uuid, date: sample.startDate,
                    sourceID: sample.sourceRevision.source.bundleIdentifier,
                    sourceName: sample.sourceRevision.source.name, nutrient: nutrient, value: value)
            }
        }
        var seen = Set<UUID>()
        return result.filter { seen.insert($0.id).inserted }
    }
}
