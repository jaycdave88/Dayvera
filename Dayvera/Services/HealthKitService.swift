import Foundation
import HealthKit

protocol HealthDataProviding {
    var isAvailable: Bool { get }
    var authorizationRequestSchema: HealthAuthorizationRequestSchema { get }
    func requestAuthorization() async throws
    func authorizationRequestStatus() async throws -> HealthAccessRequestStatus
    func fetchSamples(since startDate: Date, through endDate: Date) async throws -> HealthSampleFetchResult
    func saveStrengthWorkout(
        sessionID: UUID,
        syncVersion: Int,
        start: Date,
        end: Date
    ) async throws
    @MainActor
    func configureBackgroundDelivery(
        onUpdate: @escaping @MainActor @Sendable (HealthBackgroundEvent) async -> Void
    ) async throws
}

struct HealthAuthorizationRequestSchema: Codable, Equatable, Sendable {
    let version: Int
    let readTypeIdentifiers: Set<String>
}

/// Whether HealthKit believes presenting an authorization request may be useful.
/// This never reports which read permissions were granted or denied.
enum HealthAccessRequestStatus: Equatable, Sendable {
    case shouldRequest
    case unnecessary
    case unknown
}

extension HealthDataProviding {
    /// Test/demo providers can remain source-compatible. Production exposes the
    /// exact current schema from HealthKitService.
    var authorizationRequestSchema: HealthAuthorizationRequestSchema {
        HealthAuthorizationRequestSchema(version: 0, readTypeIdentifiers: [])
    }

    func authorizationRequestStatus() async throws -> HealthAccessRequestStatus {
        .unknown
    }
}

/// The exact reason HealthKit invoked an observer. Keeping the triggering type
/// lets the refresh layer avoid acknowledging an update when that one query was
/// part of an otherwise-successful partial refresh.
enum HealthBackgroundEvent: Equatable, Sendable {
    case dataChanged(kind: MetricKind?, typeIdentifier: String)
    case observerFailed(kind: MetricKind?, typeIdentifier: String, message: String)
}

protocol HealthStoreProviding: AnyObject {
    var underlyingHealthStore: HKHealthStore { get }
    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws
    func execute(_ query: HKQuery)
    func stop(_ query: HKQuery)
    func enableBackgroundDelivery(
        for type: HKObjectType,
        frequency: HKUpdateFrequency
    ) async throws
}

extension HKHealthStore: HealthStoreProviding {
    var underlyingHealthStore: HKHealthStore { self }
}

protocol HealthObserverQueryMaking {
    @MainActor
    func makeObserverQuery(
        sampleType: HKSampleType,
        updateHandler: @escaping @Sendable (
            HKObserverQuery,
            @escaping HKObserverQueryCompletionHandler,
            (any Error)?
        ) -> Void
    ) -> HKObserverQuery
}

struct HealthObserverQueryFactory: HealthObserverQueryMaking {
    @MainActor
    func makeObserverQuery(
        sampleType: HKSampleType,
        updateHandler: @escaping @Sendable (
            HKObserverQuery,
            @escaping HKObserverQueryCompletionHandler,
            (any Error)?
        ) -> Void
    ) -> HKObserverQuery {
        HKObserverQuery(sampleType: sampleType, predicate: nil, updateHandler: updateHandler)
    }
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
    /// Query types that completed, including types for which HealthKit returned
    /// zero samples. This is execution coverage, not authorization status.
    let successfulQueryTypeIdentifiers: Set<String>

    init(
        samples: [MetricSample],
        queryFailures: [HealthQueryFailure],
        successfulQueryTypeIdentifiers: Set<String> = []
    ) {
        self.samples = samples
        self.queryFailures = queryFailures
        self.successfulQueryTypeIdentifiers = successfulQueryTypeIdentifiers
    }

    var isPartial: Bool { !queryFailures.isEmpty }
}

final class HealthKitService: HealthDataProviding {
    private struct SampleQueryOutcome: Sendable {
        let samples: [MetricSample]
        let failure: HealthQueryFailure?
    }

    private let store: any HealthStoreProviding
    private let observerQueryFactory: any HealthObserverQueryMaking
    @MainActor private var observersByTypeIdentifier: [String: HKObserverQuery] = [:]
    @MainActor private var backgroundDeliveryEnabledTypeIdentifiers: Set<String> = []
    @MainActor private var backgroundDeliveryConfigurationTask: Task<Void, Error>?
    @MainActor private var backgroundUpdateHandler: (
        @MainActor @Sendable (HealthBackgroundEvent) async -> Void
    )?

    static let readMetricTypeIdentifiers: Set<String> = [
        HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
        HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue,
        HKQuantityTypeIdentifier.restingHeartRate.rawValue,
        HKQuantityTypeIdentifier.respiratoryRate.rawValue,
        HKQuantityTypeIdentifier.oxygenSaturation.rawValue,
        HKQuantityTypeIdentifier.appleSleepingWristTemperature.rawValue,
        HKQuantityTypeIdentifier.bodyTemperature.rawValue,
        HKQuantityTypeIdentifier.bodyMass.rawValue,
        HKQuantityTypeIdentifier.bodyFatPercentage.rawValue,
        HKQuantityTypeIdentifier.leanBodyMass.rawValue,
        HKQuantityTypeIdentifier.bodyMassIndex.rawValue,
        HKQuantityTypeIdentifier.heartRate.rawValue,
        HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
        HKQuantityTypeIdentifier.appleExerciseTime.rawValue,
        HKQuantityTypeIdentifier.stepCount.rawValue,
        HKObjectType.workoutType().identifier
    ]

    /// Only observe the three low-frequency signals that can materially change
    /// the daily recommendation. A sleep/HRV/RHR update triggers a full bounded
    /// refresh, which also picks up safety, activity, workout, and body context.
    /// Observing raw heart rate, steps, and energy at `.immediate` would wake the
    /// app repeatedly throughout the day without improving the current plan.
    static let backgroundObservedTypeIdentifiers: Set<String> = [
        HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
        HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue,
        HKQuantityTypeIdentifier.restingHeartRate.rawValue
    ]

    /// Increment when the requested read registry changes. Existing installs
    /// can compare this with their persisted schema and re-present HealthKit's
    /// system sheet for newly added types without inferring individual grants.
    static let currentAuthorizationRequestSchema = HealthAuthorizationRequestSchema(
        version: 3,
        readTypeIdentifiers: readMetricTypeIdentifiers
    )

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
        self.observerQueryFactory = HealthObserverQueryFactory()
    }

    init(
        store: any HealthStoreProviding,
        observerQueryFactory: any HealthObserverQueryMaking
    ) {
        self.store = store
        self.observerQueryFactory = observerQueryFactory
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var authorizationRequestSchema: HealthAuthorizationRequestSchema {
        Self.currentAuthorizationRequestSchema
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        let identifiers: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .respiratoryRate,
            .oxygenSaturation,
            .appleSleepingWristTemperature,
            .bodyTemperature,
            .bodyMass,
            .bodyFatPercentage,
            .leanBodyMass,
            .bodyMassIndex,
            .heartRate,
            .activeEnergyBurned,
            .appleExerciseTime,
            .stepCount
        ]
        identifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType()]
    }

    private var backgroundObservedTypes: [HKSampleType] {
        readTypes.compactMap { $0 as? HKSampleType }
            .filter { Self.backgroundObservedTypeIdentifiers.contains($0.identifier) }
            .sorted { $0.identifier < $1.identifier }
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func authorizationRequestStatus() async throws -> HealthAccessRequestStatus {
        guard isAvailable else { throw HealthDataError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            store.underlyingHealthStore.getRequestStatusForAuthorization(
                toShare: Set<HKSampleType>(),
                read: readTypes
            ) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let result: HealthAccessRequestStatus = switch status {
                case .shouldRequest: .shouldRequest
                case .unnecessary: .unnecessary
                case .unknown: .unknown
                @unknown default: .unknown
                }
                continuation.resume(returning: result)
            }
        }
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
            var successfulTypeIdentifiers = Set<String>()
            var errors: [HealthQueryFailure] = []
            for await result in group {
                normalized.append(contentsOf: result.samples)
                if let failure = result.failure { errors.append(failure) }
            }
            // Empty successful queries have no normalized sample from which to
            // recover an identifier, so derive them from the attempted set.
            let failedIdentifiers = Set(errors.map(\.typeIdentifier))
            successfulTypeIdentifiers.formUnion(
                sampleTypes.map(\.identifier).filter { !failedIdentifiers.contains($0) }
            )
            return (normalized, successfulTypeIdentifiers, errors)
        }
        guard !outcome.1.isEmpty else {
            throw HealthDataError.queryFailed(outcome.2)
        }
        return HealthSampleFetchResult(
            samples: outcome.0.sorted { $0.startDate < $1.startDate },
            queryFailures: outcome.2.sorted { $0.typeIdentifier < $1.typeIdentifier },
            successfulQueryTypeIdentifiers: outcome.1
        )
    }

    func saveStrengthWorkout(
        sessionID: UUID,
        syncVersion: Int,
        start: Date,
        end: Date
    ) async throws {
        guard end > start else { throw HealthDataError.invalidWorkoutInterval }
        guard syncVersion > 0 else { throw HealthDataError.invalidWorkoutSyncVersion }
        try await store.requestAuthorization(toShare: shareTypes, read: [])

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(
            healthStore: store.underlyingHealthStore,
            configuration: configuration,
            device: .local()
        )
        try await builder.beginCollection(at: start)
        try await builder.addMetadata(Self.workoutMetadata(
            sessionID: sessionID,
            syncVersion: syncVersion
        ))
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }

    @MainActor
    func configureBackgroundDelivery(
        onUpdate: @escaping @MainActor @Sendable (HealthBackgroundEvent) async -> Void
    ) async throws {
        // An observer can fail while an enable task is suspended. In that case a
        // re-entrant caller initially joins the old task; verify after it settles
        // and run one repair pass so the failed metric is not left unobserved.
        for _ in 0..<2 {
            let task = try beginBackgroundDeliveryConfiguration(onUpdate: onUpdate)
            try await task.value
            if Set(observersByTypeIdentifier.keys) == Self.backgroundObservedTypeIdentifiers,
               backgroundDeliveryEnabledTypeIdentifiers == Self.backgroundObservedTypeIdentifiers {
                return
            }
        }

        let missing = Self.backgroundObservedTypeIdentifiers
            .subtracting(observersByTypeIdentifier.keys)
            .sorted()
            .first
        throw HealthDataError.backgroundDeliveryConfigurationFailed(
            typeIdentifier: missing,
            message: "One or more Apple Health observers could not be restored."
        )
    }

    /// Installs every observer query synchronously before starting the first
    /// asynchronous `enableBackgroundDelivery` request. The app delegate uses
    /// this through AppModel during `didFinishLaunching`, as Apple recommends.
    /// Concurrent callers share the same configuration task.
    @MainActor
    @discardableResult
    func beginBackgroundDeliveryConfiguration(
        onUpdate: @escaping @MainActor @Sendable (HealthBackgroundEvent) async -> Void
    ) throws -> Task<Void, Error> {
        guard isAvailable else { throw HealthDataError.unavailable }
        let sampleTypes = backgroundObservedTypes
        guard Set(sampleTypes.map(\.identifier)) == Self.backgroundObservedTypeIdentifiers else {
            throw HealthDataError.backgroundDeliveryConfigurationFailed(
                typeIdentifier: nil,
                message: "One or more requested Apple Health data types are unavailable."
            )
        }

        backgroundUpdateHandler = onUpdate
        if let backgroundDeliveryConfigurationTask {
            return backgroundDeliveryConfigurationTask
        }

        var newlyInstalledObservers: [String: HKObserverQuery] = [:]
        for sampleType in sampleTypes where observersByTypeIdentifier[sampleType.identifier] == nil {
            let typeIdentifier = sampleType.identifier
            let kind = Self.metricKind(for: sampleType)
            let observer = observerQueryFactory.makeObserverQuery(sampleType: sampleType) { [weak self] query, completion, error in
                Task { @MainActor [weak self] in
                    guard let self else {
                        completion()
                        return
                    }
                    await self.handleObserverUpdate(
                        query: query,
                        kind: kind,
                        typeIdentifier: typeIdentifier,
                        completion: completion,
                        error: error
                    )
                }
            }
            observersByTypeIdentifier[typeIdentifier] = observer
            newlyInstalledObservers[typeIdentifier] = observer
            store.execute(observer)
        }

        let newlyInstalledTypeIdentifiers = Set(newlyInstalledObservers.keys)
        let sampleTypesToEnable = sampleTypes.filter {
            !backgroundDeliveryEnabledTypeIdentifiers.contains($0.identifier)
                || newlyInstalledTypeIdentifiers.contains($0.identifier)
        }
        let configurationTask = Task { @MainActor [weak self] () throws -> Void in
            guard let self else { return }
            defer { self.backgroundDeliveryConfigurationTask = nil }

            do {
                for sampleType in sampleTypesToEnable {
                    try Task.checkCancellation()
                    try await self.store.enableBackgroundDelivery(for: sampleType, frequency: .immediate)
                    if self.observersByTypeIdentifier[sampleType.identifier] != nil {
                        self.backgroundDeliveryEnabledTypeIdentifiers.insert(sampleType.identifier)
                    }
                }
            } catch {
                for (typeIdentifier, observer) in newlyInstalledObservers
                where self.observersByTypeIdentifier[typeIdentifier] === observer {
                    self.store.stop(observer)
                    self.observersByTypeIdentifier.removeValue(forKey: typeIdentifier)
                    self.backgroundDeliveryEnabledTypeIdentifiers.remove(typeIdentifier)
                }
                let failedIdentifier = sampleTypesToEnable.first {
                    !self.backgroundDeliveryEnabledTypeIdentifiers.contains($0.identifier)
                }?.identifier
                throw HealthDataError.backgroundDeliveryConfigurationFailed(
                    typeIdentifier: failedIdentifier,
                    message: error.localizedDescription
                )
            }
        }
        backgroundDeliveryConfigurationTask = configurationTask
        return configurationTask
    }

    @MainActor
    private func handleObserverUpdate(
        query: HKObserverQuery,
        kind: MetricKind?,
        typeIdentifier: String,
        completion: @escaping HKObserverQueryCompletionHandler,
        error: (any Error)?
    ) async {
        let event: HealthBackgroundEvent
        if let error {
            if observersByTypeIdentifier[typeIdentifier] === query {
                store.stop(query)
                observersByTypeIdentifier.removeValue(forKey: typeIdentifier)
            }
            backgroundDeliveryEnabledTypeIdentifiers.remove(typeIdentifier)
            event = .observerFailed(
                kind: kind,
                typeIdentifier: typeIdentifier,
                message: error.localizedDescription
            )
        } else {
            event = .dataChanged(kind: kind, typeIdentifier: typeIdentifier)
        }

        await backgroundUpdateHandler?(event)
        // Apple requires every background delivery to be acknowledged promptly;
        // withholding this callback three times can disable future delivery. The
        // app retains query failures and refreshes the rolling window again on
        // foreground, so a failed read remains recoverable without starving the
        // observer pipeline.
        completion()
    }

    static func workoutMetadata(sessionID: UUID, syncVersion: Int) -> [String: Any] {
        [
            HKMetadataKeyIndoorWorkout: true,
            HKMetadataKeySyncIdentifier: sessionID.uuidString,
            HKMetadataKeySyncVersion: NSNumber(value: syncVersion)
        ]
    }

    static func diagnostics(from samples: [MetricSample]) -> [SourceDiagnostic] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: samples) { "\($0.sourceIdentity)|\($0.kind.rawValue)" }
        return groups.values.compactMap { group in
            guard let sample = group.max(by: { $0.endDate < $1.endDate }) else { return nil }
            let devices = Array(Set(group.compactMap(\.device))).sorted {
                if $0.displayName == $1.displayName {
                    return ($0.model ?? "") < ($1.model ?? "")
                }
                return $0.displayName < $1.displayName
            }
            return SourceDiagnostic(
                sourceName: sample.sourceName,
                bundleIdentifier: sample.sourceBundleIdentifier,
                sourceProductType: sample.sourceProductType,
                kind: sample.kind,
                sampleCount: group.count,
                userEnteredSampleCount: group.filter(\.wasUserEntered).count,
                latestSample: group.map(\.endDate).max(),
                firstSample: group.map(\.startDate).min(),
                observedDayCount: Set(group.map { calendar.startOfDay(for: $0.endDate) }).count,
                devices: devices
            )
        }.sorted {
            if $0.vendorLabel == $1.vendorLabel { return $0.kind.title < $1.kind.title }
            return $0.vendorLabel < $1.vendorLabel
        }
    }

    static func observedCoverage(from samples: [MetricSample]) -> [MetricObservedCoverage] {
        let calendar = Calendar.current
        let samplesByKind = Dictionary(grouping: samples, by: \.kind)
        return MetricKind.healthReadMetrics.map { kind in
            let matching = samplesByKind[kind] ?? []
            return MetricObservedCoverage(
                kind: kind,
                sampleCount: matching.count,
                observedDayCount: Set(matching.map { calendar.startOfDay(for: $0.endDate) }).count,
                firstSample: matching.map(\.startDate).min(),
                latestSample: matching.map(\.endDate).max(),
                sourceCount: Set(matching.map(\.sourceIdentity)).count,
                deviceCount: Set(matching.compactMap(\.device)).count
            )
        }
    }

    private static func query(
        store: any HealthStoreProviding,
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

    static func queryStartDate(for type: HKSampleType, requestedStart: Date, endDate: Date) -> Date {
        let shortWindowIdentifiers: Set<String> = [
            HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
            HKQuantityTypeIdentifier.stepCount.rawValue,
            HKQuantityTypeIdentifier.appleExerciseTime.rawValue
        ]
        if shortWindowIdentifiers.contains(type.identifier) {
            return max(requestedStart, endDate.addingTimeInterval(-3 * 24 * 3600))
        }
        // Raw heart-rate samples are high-volume. Twenty-one days is enough for
        // the approved nightly baseline while keeping each query bounded.
        if type.identifier == HKQuantityTypeIdentifier.heartRate.rawValue {
            return max(requestedStart, endDate.addingTimeInterval(-21 * 24 * 3600))
        }
        return requestedStart
    }

    static func sampleLimit(for type: HKSampleType) -> Int {
        if type == HKObjectType.workoutType() { return 500 }
        return switch type.identifier {
        case HKCategoryTypeIdentifier.sleepAnalysis.rawValue: 4_000
        case HKQuantityTypeIdentifier.heartRate.rawValue: 20_000
        default: 1_000
        }
    }

    static func normalize(_ sample: HKSample) -> MetricSample? {
        let source = sample.sourceRevision.source
        let sourceName = source.name
        let bundle = source.bundleIdentifier
        let sourceProductType = sample.sourceRevision.productType
        let device = deviceProvenance(sample.device)
        let metadata = sample.metadata ?? [:]
        let wasUserEntered = (metadata[HKMetadataKeyWasUserEntered] as? NSNumber)?.boolValue ?? false

        if let category = sample as? HKCategorySample,
           category.categoryType.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue {
            return MetricSample(
                id: category.uuid,
                kind: .sleep,
                startDate: category.startDate,
                endDate: category.endDate,
                sleepStage: sleepStage(for: category.value),
                sourceName: sourceName,
                sourceBundleIdentifier: bundle,
                sourceProductType: sourceProductType,
                device: device,
                wasUserEntered: wasUserEntered
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
                sourceBundleIdentifier: bundle,
                sourceProductType: sourceProductType,
                device: device,
                wasUserEntered: wasUserEntered,
                workoutSyncIdentifier: metadata[HKMetadataKeySyncIdentifier] as? String,
                workoutSyncVersion: (metadata[HKMetadataKeySyncVersion] as? NSNumber)?.intValue
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
            sourceBundleIdentifier: bundle,
            sourceProductType: sourceProductType,
            device: device,
            wasUserEntered: wasUserEntered
        )
    }

    private static func deviceProvenance(_ device: HKDevice?) -> HealthDeviceProvenance? {
        guard let device else { return nil }
        // HKDevice.name may contain the person's custom device name. Hardware,
        // firmware, and software versions add fingerprinting surface without
        // helping source selection, so production retains only broad maker/model.
        return HealthDeviceProvenance(
            manufacturer: device.manufacturer,
            model: device.model
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
        case HKQuantityTypeIdentifier.bodyTemperature.rawValue: .bodyTemperature
        case HKQuantityTypeIdentifier.bodyMass.rawValue: .bodyMass
        case HKQuantityTypeIdentifier.bodyFatPercentage.rawValue: .bodyFatPercentage
        case HKQuantityTypeIdentifier.leanBodyMass.rawValue: .leanBodyMass
        case HKQuantityTypeIdentifier.bodyMassIndex.rawValue: .bodyMassIndex
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
        case .sleepingWristTemperature, .bodyTemperature:
            sample.quantity.doubleValue(for: .degreeCelsius())
        case .bodyMass, .leanBodyMass:
            sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
        case .bodyFatPercentage:
            sample.quantity.doubleValue(for: .percent()) * 100
        case .bodyMassIndex:
            sample.quantity.doubleValue(for: .count())
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
    case invalidWorkoutInterval
    case invalidWorkoutSyncVersion
    case backgroundDeliveryConfigurationFailed(typeIdentifier: String?, message: String)

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
        case .invalidWorkoutInterval:
            return "The workout end time must be later than its start time."
        case .invalidWorkoutSyncVersion:
            return "The Apple Health workout sync version is invalid."
        case .backgroundDeliveryConfigurationFailed(let typeIdentifier, _):
            let typeLabel = switch typeIdentifier {
            case .some(HKCategoryTypeIdentifier.sleepAnalysis.rawValue): "sleep"
            case .some(HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue): "heart rate variability"
            case .some(HKQuantityTypeIdentifier.restingHeartRate.rawValue): "resting heart rate"
            case .some(HKQuantityTypeIdentifier.respiratoryRate.rawValue): "respiratory rate"
            case .some(HKQuantityTypeIdentifier.oxygenSaturation.rawValue): "blood oxygen"
            case .some(HKQuantityTypeIdentifier.appleSleepingWristTemperature.rawValue): "sleeping wrist temperature"
            case .some(HKQuantityTypeIdentifier.bodyTemperature.rawValue): "body temperature"
            case .some(HKQuantityTypeIdentifier.heartRate.rawValue): "heart rate"
            case .some(HKQuantityTypeIdentifier.activeEnergyBurned.rawValue): "active energy"
            case .some(HKQuantityTypeIdentifier.appleExerciseTime.rawValue): "exercise minutes"
            case .some(HKQuantityTypeIdentifier.stepCount.rawValue): "steps"
            case .some(let identifier) where identifier == HKObjectType.workoutType().identifier: "workouts"
            case .some(_): "one requested data type"
            case nil: "all requested data types"
            }
            return "Apple Health background updates couldn’t be enabled for \(typeLabel). Your current data is still available; use Refresh Apple Health to try again."
        }
    }
}
