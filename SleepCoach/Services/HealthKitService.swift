import Foundation
import HealthKit

protocol HealthDataProviding {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func fetchSamples(since startDate: Date, through endDate: Date) async throws -> HealthSampleFetchResult
    func saveStrengthWorkout(start: Date, end: Date) async throws
    func configureBackgroundDelivery(onUpdate: @escaping @Sendable () async -> Void) async
}

/// A type-specific read failure. HealthKit intentionally does not disclose whether
/// a read returned no data because access was denied or because no samples exist,
/// so this describes query execution failures only.
struct HealthQueryFailure: Identifiable, Hashable, Sendable {
    var id: String { typeIdentifier }
    let kind: MetricKind?
    let typeIdentifier: String
    let message: String
}

/// Successful HealthKit reads and their independently failed sibling queries.
/// Callers can safely render the successful subset while disclosing partial data.
struct HealthSampleFetchResult: Sendable {
    let samples: [MetricSample]
    let queryFailures: [HealthQueryFailure]

    var isPartial: Bool { !queryFailures.isEmpty }
}

final class HealthKitService: HealthDataProviding {
    private struct SampleQueryOutcome: Sendable {
        let samples: [MetricSample]
        let failure: HealthQueryFailure?
    }

    private let store: HKHealthStore
    private var sleepObserver: HKObserverQuery?

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        let identifiers: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN,
            .restingHeartRate
        ]
        identifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        return types
    }

    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType()]
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    func fetchSamples(since startDate: Date, through endDate: Date = .now) async throws -> HealthSampleFetchResult {
        guard isAvailable else { throw HealthDataError.unavailable }
        let sampleTypes = readTypes.compactMap { $0 as? HKSampleType }
        let outcome = await withTaskGroup(of: SampleQueryOutcome.self) { group in
            for sampleType in sampleTypes {
                let queryStart = Self.queryStartDate(for: sampleType, requestedStart: startDate, endDate: endDate)
                let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: endDate, options: [])
                let limit = Self.sampleLimit(for: sampleType)
                group.addTask { [store] in
                    do {
                        let samples = try await Self.query(store: store, type: sampleType, predicate: predicate, limit: limit)
                        return SampleQueryOutcome(samples: samples.compactMap(Self.normalize), failure: nil)
                    } catch {
                        return SampleQueryOutcome(
                            samples: [],
                            failure: HealthQueryFailure(
                                kind: Self.metricKind(for: sampleType),
                                typeIdentifier: sampleType.identifier,
                                message: error.localizedDescription
                            )
                        )
                    }
                }
            }
            var normalized: [MetricSample] = []
            var successfulQueries = 0
            var errors: [HealthQueryFailure] = []
            for await result in group {
                normalized.append(contentsOf: result.samples)
                if let failure = result.failure { errors.append(failure) }
                else { successfulQueries += 1 }
            }
            return (normalized, successfulQueries, errors)
        }
        guard outcome.1 > 0 else {
            throw HealthDataError.queryFailed(outcome.2)
        }
        return HealthSampleFetchResult(
            samples: outcome.0.sorted { $0.startDate < $1.startDate },
            queryFailures: outcome.2.sorted { $0.typeIdentifier < $1.typeIdentifier }
        )
    }

    func saveStrengthWorkout(start: Date, end: Date) async throws {
        guard end > start else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(
            healthStore: store,
            configuration: configuration,
            device: .local()
        )
        try await builder.beginCollection(at: start)
        try await builder.addMetadata([HKMetadataKeyIndoorWorkout: true])
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }

    func configureBackgroundDelivery(onUpdate: @escaping @Sendable () async -> Void) async {
        guard sleepObserver == nil,
              let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let observer = HKObserverQuery(sampleType: sleep, predicate: nil) { _, completion, error in
            guard error == nil else {
                completion()
                return
            }
            Task {
                await onUpdate()
                completion()
            }
        }
        sleepObserver = observer
        store.execute(observer)
        try? await store.enableBackgroundDelivery(for: sleep, frequency: .immediate)
    }

    static func diagnostics(from samples: [MetricSample]) -> [SourceDiagnostic] {
        let groups = Dictionary(grouping: samples) { "\($0.sourceBundleIdentifier)|\($0.kind.rawValue)" }
        return groups.values.compactMap { group in
            guard let sample = group.first else { return nil }
            return SourceDiagnostic(
                sourceName: sample.sourceName,
                bundleIdentifier: sample.sourceBundleIdentifier,
                kind: sample.kind,
                sampleCount: group.count,
                latestSample: group.map(\.endDate).max()
            )
        }.sorted {
            if $0.vendorLabel == $1.vendorLabel { return $0.kind.title < $1.kind.title }
            return $0.vendorLabel < $1.vendorLabel
        }
    }

    private static func query(
        store: HKHealthStore,
        type: HKSampleType,
        predicate: NSPredicate,
        limit: Int
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }

    private static func queryStartDate(for type: HKSampleType, requestedStart: Date, endDate: Date) -> Date {
        let shortWindowIdentifiers: Set<String> = [
            HKQuantityTypeIdentifier.heartRate.rawValue,
            HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
            HKQuantityTypeIdentifier.stepCount.rawValue,
            HKQuantityTypeIdentifier.appleExerciseTime.rawValue
        ]
        guard shortWindowIdentifiers.contains(type.identifier) else { return requestedStart }
        return max(requestedStart, endDate.addingTimeInterval(-3 * 24 * 3600))
    }

    private static func sampleLimit(for type: HKSampleType) -> Int {
        if type == HKObjectType.workoutType() { return 500 }
        return switch type.identifier {
        case HKCategoryTypeIdentifier.sleepAnalysis.rawValue: 4_000
        case HKQuantityTypeIdentifier.heartRate.rawValue: 1_200
        default: 1_000
        }
    }

    private static func normalize(_ sample: HKSample) -> MetricSample? {
        let source = sample.sourceRevision.source
        let sourceName = source.name
        let bundle = source.bundleIdentifier

        if let category = sample as? HKCategorySample,
           category.categoryType.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue {
            return MetricSample(
                id: category.uuid,
                kind: .sleep,
                startDate: category.startDate,
                endDate: category.endDate,
                sleepStage: sleepStage(for: category.value),
                sourceName: sourceName,
                sourceBundleIdentifier: bundle
            )
        }

        if let workout = sample as? HKWorkout {
            return MetricSample(
                id: workout.uuid,
                kind: .workout,
                startDate: workout.startDate,
                endDate: workout.endDate,
                value: workout.duration / 60,
                sourceName: sourceName,
                sourceBundleIdentifier: bundle
            )
        }

        guard let quantity = sample as? HKQuantitySample,
              let kind = metricKind(for: quantity.quantityType.identifier),
              let value = quantityValue(quantity, kind: kind) else { return nil }
        return MetricSample(
            id: quantity.uuid,
            kind: kind,
            startDate: quantity.startDate,
            endDate: quantity.endDate,
            value: value,
            sourceName: sourceName,
            sourceBundleIdentifier: bundle
        )
    }

    private static func metricKind(for identifier: String) -> MetricKind? {
        switch identifier {
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue: .heartRateVariability
        case HKQuantityTypeIdentifier.restingHeartRate.rawValue: .restingHeartRate
        case HKQuantityTypeIdentifier.heartRate.rawValue: .heartRate
        case HKQuantityTypeIdentifier.respiratoryRate.rawValue: .respiratoryRate
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue: .oxygenSaturation
        case HKQuantityTypeIdentifier.appleSleepingWristTemperature.rawValue: .sleepingWristTemperature
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue: .activeEnergy
        case HKQuantityTypeIdentifier.stepCount.rawValue: .steps
        case HKQuantityTypeIdentifier.appleExerciseTime.rawValue: .exerciseMinutes
        default: nil
        }
    }

    private static func metricKind(for type: HKSampleType) -> MetricKind? {
        if type.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue { return .sleep }
        if type == HKObjectType.workoutType() { return .workout }
        return metricKind(for: type.identifier)
    }

    private static func quantityValue(_ sample: HKQuantitySample, kind: MetricKind) -> Double? {
        switch kind {
        case .heartRateVariability:
            sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
        case .heartRate, .restingHeartRate:
            sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        case .respiratoryRate:
            sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        case .oxygenSaturation:
            sample.quantity.doubleValue(for: .percent()) * 100
        case .sleepingWristTemperature:
            sample.quantity.doubleValue(for: .degreeCelsius())
        case .activeEnergy:
            sample.quantity.doubleValue(for: .kilocalorie())
        case .steps:
            sample.quantity.doubleValue(for: .count())
        case .exerciseMinutes:
            sample.quantity.doubleValue(for: .minute())
        default:
            nil
        }
    }

    private static func sleepStage(for rawValue: Int) -> SleepStage {
        switch rawValue {
        case HKCategoryValueSleepAnalysis.inBed.rawValue: .inBed
        case HKCategoryValueSleepAnalysis.awake.rawValue: .awake
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: .asleep
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: .rem
        default: .unknown
        }
    }
}

enum HealthDataError: LocalizedError {
    case unavailable
    case queryFailed([HealthQueryFailure])

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Health is unavailable on this device."
        case .queryFailed(let failures):
            let detail = failures
                .map { failure in
                    let label = failure.kind?.title ?? failure.typeIdentifier
                    return "\(label): \(failure.message)"
                }
                .joined(separator: "; ")
            return "Apple Health data could not be refreshed. \(detail.isEmpty ? "No requested category could be read." : detail)"
        }
    }
}
