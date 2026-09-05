import HealthKit
import XCTest
@testable import Dayvera

@MainActor
final class HealthKitServiceTests: XCTestCase {
    func testAuthorizationSchemaVersionsTheExactExpandedReadRegistry() {
        XCTAssertEqual(HealthKitService.currentAuthorizationRequestSchema.version, 3)
        XCTAssertEqual(
            HealthKitService.currentAuthorizationRequestSchema.readTypeIdentifiers,
            HealthKitService.readMetricTypeIdentifiers
        )
        XCTAssertTrue(
            Set(MetricKind.bodyCompositionMetrics).isDisjoint(
                with: Set(MetricKind.decisionMetrics + MetricKind.safetyMetrics)
            )
        )
    }

    func testBackgroundDeliveryIsLimitedToLowFrequencyDecisionTriggers() {
        XCTAssertEqual(
            HealthKitService.backgroundObservedTypeIdentifiers,
            [
                HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
                HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue,
                HKQuantityTypeIdentifier.restingHeartRate.rawValue
            ]
        )
        XCTAssertTrue(
            HealthKitService.backgroundObservedTypeIdentifiers.isSubset(
                of: HealthKitService.readMetricTypeIdentifiers
            )
        )
        XCTAssertFalse(
            HealthKitService.backgroundObservedTypeIdentifiers.contains(
                HKQuantityTypeIdentifier.heartRate.rawValue
            )
        )
    }

    func testObserverQueriesAreExecutedBeforeBackgroundDeliveryIsAwaited() async throws {
        let store = TestHealthStore()
        let factory = TestObserverQueryFactory()
        let service = HealthKitService(store: store, observerQueryFactory: factory)

        let task = try service.beginBackgroundDeliveryConfiguration { _ in }

        XCTAssertEqual(store.executedQueries.count, HealthKitService.backgroundObservedTypeIdentifiers.count)
        XCTAssertTrue(store.enabledTypeIdentifiers.isEmpty)

        try await task.value
    }

    func testConcurrentConfigurationSharesObserversAndEnableWork() async throws {
        let store = TestHealthStore()
        let factory = TestObserverQueryFactory()
        let service = HealthKitService(store: store, observerQueryFactory: factory)

        let first = try service.beginBackgroundDeliveryConfiguration { _ in }
        let second = try service.beginBackgroundDeliveryConfiguration { _ in }

        XCTAssertEqual(store.executedQueries.count, HealthKitService.backgroundObservedTypeIdentifiers.count)
        try await first.value
        try await second.value

        XCTAssertEqual(store.executedQueries.count, HealthKitService.backgroundObservedTypeIdentifiers.count)
        XCTAssertEqual(
            Set(store.enabledTypeIdentifiers),
            HealthKitService.backgroundObservedTypeIdentifiers
        )
        XCTAssertEqual(store.enabledTypeIdentifiers.count, HealthKitService.backgroundObservedTypeIdentifiers.count)
    }

    func testObserverDeliveryIsAcknowledgedAfterTypedHandlerFinishes() async throws {
        let store = TestHealthStore()
        let factory = TestObserverQueryFactory()
        let service = HealthKitService(store: store, observerQueryFactory: factory)
        let eventReceived = expectation(description: "typed observer event received")
        let completionCalled = expectation(description: "HealthKit completion called")

        try await service.configureBackgroundDelivery { event in
            guard case .dataChanged(.heartRateVariability, let identifier) = event else {
                XCTFail("Unexpected background event: \(event)")
                return
            }
            XCTAssertEqual(identifier, HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue)
            eventReceived.fulfill()
        }

        factory.emit(
            typeIdentifier: HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue,
            completion: { completionCalled.fulfill() }
        )

        await fulfillment(of: [eventReceived, completionCalled], timeout: 1)
    }

    func testObserverErrorIsSurfacedAndRegistrationCanBeRetried() async throws {
        let store = TestHealthStore()
        let factory = TestObserverQueryFactory()
        let service = HealthKitService(store: store, observerQueryFactory: factory)
        let failureReceived = expectation(description: "observer failure surfaced")
        let completionCalled = expectation(description: "observer error acknowledged after handling")
        let sleepIdentifier = HKCategoryTypeIdentifier.sleepAnalysis.rawValue

        try await service.configureBackgroundDelivery { event in
            guard case .observerFailed(.sleep, let identifier, let message) = event else {
                return
            }
            XCTAssertEqual(identifier, sleepIdentifier)
            XCTAssertEqual(message, "Observer failed")
            failureReceived.fulfill()
        }

        factory.emit(
            typeIdentifier: sleepIdentifier,
            error: NSError(domain: "HealthKitServiceTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Observer failed"
            ]),
            completion: { completionCalled.fulfill() }
        )
        await fulfillment(of: [failureReceived, completionCalled], timeout: 1)

        try await service.configureBackgroundDelivery { _ in }

        XCTAssertEqual(store.stoppedQueries.count, 1)
        XCTAssertEqual(
            store.executedQueries.count,
            HealthKitService.backgroundObservedTypeIdentifiers.count + 1
        )
        XCTAssertEqual(store.enabledTypeIdentifiers.filter { $0 == sleepIdentifier }.count, 2)
    }

    func testObserverFailureDuringEnableIsRepairedBeforeConfigurationReturns() async throws {
        let store = TestHealthStore()
        let factory = TestObserverQueryFactory()
        let service = HealthKitService(store: store, observerQueryFactory: factory)
        let sleepIdentifier = HKCategoryTypeIdentifier.sleepAnalysis.rawValue
        let enableStarted = expectation(description: "sleep enable suspended")
        let observerFailureHandled = expectation(description: "observer failure handled")
        let observerCompletionCalled = expectation(description: "observer completion called")
        store.suspendEnableTypeIdentifier = sleepIdentifier
        store.onSuspendedEnableStarted = { enableStarted.fulfill() }

        let configuration = Task {
            try await service.configureBackgroundDelivery { event in
                if case .observerFailed(.sleep, let identifier, _) = event,
                   identifier == sleepIdentifier {
                    observerFailureHandled.fulfill()
                }
            }
        }
        await fulfillment(of: [enableStarted], timeout: 1)

        factory.emit(
            typeIdentifier: sleepIdentifier,
            error: NSError(domain: "HealthKitServiceTests", code: 3),
            completion: { observerCompletionCalled.fulfill() }
        )
        await fulfillment(of: [observerFailureHandled, observerCompletionCalled], timeout: 1)
        store.resumeSuspendedEnable()
        try await configuration.value

        XCTAssertEqual(
            store.executedQueries.count,
            HealthKitService.backgroundObservedTypeIdentifiers.count + 1
        )
        XCTAssertEqual(Set(store.enabledTypeIdentifiers), HealthKitService.backgroundObservedTypeIdentifiers)
        XCTAssertEqual(store.enabledTypeIdentifiers.filter { $0 == sleepIdentifier }.count, 2)
    }

    func testEnableFailureStopsNewObserversAndAllowsCleanRetry() async throws {
        let store = TestHealthStore()
        let factory = TestObserverQueryFactory()
        let service = HealthKitService(store: store, observerQueryFactory: factory)
        store.enableFailureTypeIdentifier = HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue

        do {
            try await service.configureBackgroundDelivery { _ in }
            XCTFail("Expected background delivery configuration to fail")
        } catch let error as HealthDataError {
            guard case .backgroundDeliveryConfigurationFailed = error else {
                XCTFail("Unexpected HealthDataError: \(error)")
                return
            }
        }

        XCTAssertEqual(store.executedQueries.count, HealthKitService.backgroundObservedTypeIdentifiers.count)
        XCTAssertEqual(store.stoppedQueries.count, HealthKitService.backgroundObservedTypeIdentifiers.count)

        store.enableFailureTypeIdentifier = nil
        try await service.configureBackgroundDelivery { _ in }

        XCTAssertEqual(store.executedQueries.count, HealthKitService.backgroundObservedTypeIdentifiers.count * 2)
    }

    func testDiagnosticsRetainDeviceProvenanceAndObservedCoverage() throws {
        let first = Date(timeIntervalSince1970: 1_000)
        let second = first.addingTimeInterval(24 * 3600)
        let watch = HealthDeviceProvenance(
            manufacturer: "Apple Inc.",
            model: "Watch"
        )
        let samples = [first, second].map { date in
            MetricSample(
                kind: .respiratoryRate,
                startDate: date,
                endDate: date,
                value: 15,
                sourceName: "Apple Watch",
                sourceBundleIdentifier: "com.apple.health",
                sourceProductType: "Watch7,5",
                device: watch
            )
        }

        let diagnostic = try XCTUnwrap(HealthKitService.diagnostics(from: samples).first)
        let coverage = try XCTUnwrap(
            HealthKitService.observedCoverage(from: samples).first { $0.kind == .respiratoryRate }
        )

        XCTAssertEqual(diagnostic.devices, [watch])
        XCTAssertEqual(diagnostic.observedDayCount, 2)
        XCTAssertEqual(diagnostic.firstSample, first)
        XCTAssertEqual(diagnostic.latestSample, second)
        XCTAssertEqual(coverage.sampleCount, 2)
        XCTAssertEqual(coverage.observedDayCount, 2)
        XCTAssertEqual(coverage.sourceCount, 1)
        XCTAssertEqual(coverage.deviceCount, 1)
    }

    func testDiagnosticsSeparateProductTypesAndRetainUserEnteredProvenance() throws {
        let date = Date(timeIntervalSince1970: 2_000)
        let samples = [
            MetricSample(
                kind: .heartRate,
                startDate: date,
                endDate: date,
                value: 52,
                sourceName: "Health",
                sourceBundleIdentifier: "com.apple.health",
                sourceProductType: "Watch7,5"
            ),
            MetricSample(
                kind: .heartRate,
                startDate: date,
                endDate: date,
                value: 60,
                sourceName: "Health",
                sourceBundleIdentifier: "com.apple.health",
                sourceProductType: "iPhone18,1",
                wasUserEntered: true
            )
        ]

        let diagnostics = HealthKitService.diagnostics(from: samples)

        XCTAssertEqual(diagnostics.count, 2)
        XCTAssertEqual(Set(diagnostics.compactMap(\.sourceProductType)), ["Watch7,5", "iPhone18,1"])
        XCTAssertEqual(diagnostics.reduce(0) { $0 + $1.userEnteredSampleCount }, 1)
        XCTAssertEqual(
            HealthKitService.observedCoverage(from: samples)
                .first { $0.kind == .heartRate }?.sourceCount,
            2
        )
    }

    func testObservedCoverageUsesNoSamplesObservedWithoutInferringAuthorization() throws {
        let coverage = HealthKitService.observedCoverage(from: [])

        XCTAssertEqual(coverage.map(\.kind), MetricKind.healthReadMetrics)
        XCTAssertTrue(coverage.allSatisfy { !$0.hasObservedSamples })
        XCTAssertTrue(coverage.allSatisfy { $0.sampleCount == 0 && $0.latestSample == nil })
    }

    func testQuantityNormalizationIncludesNonIdentifyingDeviceAndUserEnteredProvenance() throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .bodyTemperature))
        let device = HKDevice(
            name: "Jay’s Apple Watch",
            manufacturer: "Apple Inc.",
            model: "Watch",
            hardwareVersion: "private-hardware-version",
            firmwareVersion: "private-firmware-version",
            softwareVersion: "26.0",
            localIdentifier: "private-local-identifier",
            udiDeviceIdentifier: "private-udi"
        )
        let date = Date(timeIntervalSince1970: 10_000)
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .degreeCelsius(), doubleValue: 37.2),
            start: date,
            end: date,
            device: device,
            metadata: [HKMetadataKeyWasUserEntered: true]
        )

        let normalized = try XCTUnwrap(HealthKitService.normalize(sample))

        XCTAssertEqual(normalized.kind, .bodyTemperature)
        XCTAssertEqual(normalized.value ?? 0, 37.2, accuracy: 0.001)
        XCTAssertEqual(
            normalized.device,
            HealthDeviceProvenance(manufacturer: "Apple Inc.", model: "Watch")
        )
        XCTAssertTrue(normalized.wasUserEntered)
    }

    func testBodyCompositionTypesNormalizeIntoContextOnlyCanonicalUnits() throws {
        let date = Date(timeIntervalSince1970: 20_000)
        let fixtures: [(HKQuantityTypeIdentifier, HKUnit, Double, MetricKind, Double)] = [
            (.bodyMass, .gramUnit(with: .kilo), 82.4, .bodyMass, 82.4),
            (.bodyFatPercentage, .percent(), 0.183, .bodyFatPercentage, 18.3),
            (.leanBodyMass, .gramUnit(with: .kilo), 67.3, .leanBodyMass, 67.3),
            (.bodyMassIndex, .count(), 24.1, .bodyMassIndex, 24.1)
        ]

        for (identifier, unit, rawValue, expectedKind, expectedValue) in fixtures {
            let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: identifier))
            let sample = HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: rawValue),
                start: date,
                end: date
            )

            let normalized = try XCTUnwrap(HealthKitService.normalize(sample))

            XCTAssertEqual(normalized.kind, expectedKind)
            XCTAssertEqual(normalized.value ?? 0, expectedValue, accuracy: 0.001)
        }
    }

    func testBodyCompositionDisplayUsesPreferredMassUnitAndLeavesBMIUnitless() {
        XCTAssertEqual(
            bodyCompositionDisplayValue(value: 82.4, kind: .bodyMass, loadUnit: .kilograms),
            "82.4 kg"
        )
        XCTAssertEqual(
            bodyCompositionDisplayValue(value: 82.4, kind: .bodyMass, loadUnit: .pounds),
            "181.7 lb"
        )
        XCTAssertEqual(
            bodyCompositionDisplayValue(value: 18.3, kind: .bodyFatPercentage, loadUnit: .pounds),
            "18.3%"
        )
        XCTAssertEqual(
            bodyCompositionDisplayValue(value: 24.1, kind: .bodyMassIndex, loadUnit: .pounds),
            "24.1"
        )
        XCTAssertEqual(
            bodyCompositionDeltaDisplayValue(value: -1, kind: .bodyMass, loadUnit: .pounds),
            "−2.2 lb"
        )
        XCTAssertEqual(
            bodyCompositionDeltaDisplayValue(value: 0.8, kind: .bodyFatPercentage, loadUnit: .pounds),
            "+0.8 pp"
        )
    }

    func testRawHeartRateQueryUsesFiniteTwentyOneDayWindowAndLimit() throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let end = Date(timeIntervalSince1970: 5_000_000)
        let requestedStart = end.addingTimeInterval(-35 * 24 * 3600)

        XCTAssertEqual(
            HealthKitService.queryStartDate(
                for: type,
                requestedStart: requestedStart,
                endDate: end
            ),
            end.addingTimeInterval(-21 * 24 * 3600)
        )
        XCTAssertEqual(HealthKitService.sampleLimit(for: type), 20_000)
        XCTAssertNotEqual(HealthKitService.sampleLimit(for: type), HKObjectQueryNoLimit)
    }
}

private final class TestHealthStore: HealthStoreProviding, @unchecked Sendable {
    let underlyingHealthStore = HKHealthStore()
    private(set) var executedQueries: [HKQuery] = []
    private(set) var stoppedQueries: [HKQuery] = []
    private(set) var enabledTypeIdentifiers: [String] = []
    var enableFailureTypeIdentifier: String?
    var suspendEnableTypeIdentifier: String?
    var onSuspendedEnableStarted: (() -> Void)?
    private var suspendedEnableContinuation: CheckedContinuation<Void, Never>?

    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws {}

    func execute(_ query: HKQuery) {
        executedQueries.append(query)
    }

    func stop(_ query: HKQuery) {
        stoppedQueries.append(query)
    }

    func enableBackgroundDelivery(
        for type: HKObjectType,
        frequency: HKUpdateFrequency
    ) async throws {
        enabledTypeIdentifiers.append(type.identifier)
        if type.identifier == suspendEnableTypeIdentifier {
            suspendEnableTypeIdentifier = nil
            await withCheckedContinuation { continuation in
                suspendedEnableContinuation = continuation
                onSuspendedEnableStarted?()
            }
        }
        if type.identifier == enableFailureTypeIdentifier {
            throw NSError(domain: "HealthKitServiceTests", code: 2)
        }
    }

    func resumeSuspendedEnable() {
        suspendedEnableContinuation?.resume()
        suspendedEnableContinuation = nil
    }
}

@MainActor
private final class TestObserverQueryFactory: HealthObserverQueryMaking {
    typealias UpdateHandler = @Sendable (
        HKObserverQuery,
        @escaping HKObserverQueryCompletionHandler,
        (any Error)?
    ) -> Void

    private var queries: [String: HKObserverQuery] = [:]
    private var updateHandlers: [String: UpdateHandler] = [:]

    func makeObserverQuery(
        sampleType: HKSampleType,
        updateHandler: @escaping UpdateHandler
    ) -> HKObserverQuery {
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completion, _ in
            completion()
        }
        queries[sampleType.identifier] = query
        updateHandlers[sampleType.identifier] = updateHandler
        return query
    }

    func emit(
        typeIdentifier: String,
        error: (any Error)? = nil,
        completion: @escaping HKObserverQueryCompletionHandler
    ) {
        guard let query = queries[typeIdentifier],
              let updateHandler = updateHandlers[typeIdentifier] else {
            XCTFail("No observer installed for \(typeIdentifier)")
            return
        }
        updateHandler(query, completion, error)
    }
}
