import HealthKit
import XCTest
@testable import SleepCoach

@MainActor
final class HealthKitServiceTests: XCTestCase {
    func testObserverQueriesAreExecutedBeforeBackgroundDeliveryIsAwaited() async throws {
        let store = TestHealthStore()
        let factory = TestObserverQueryFactory()
        let service = HealthKitService(store: store, observerQueryFactory: factory)

        let task = try service.beginBackgroundDeliveryConfiguration { _ in }

        XCTAssertEqual(store.executedQueries.count, HealthKitService.readMetricTypeIdentifiers.count)
        XCTAssertTrue(store.enabledTypeIdentifiers.isEmpty)

        try await task.value
    }

    func testConcurrentConfigurationSharesObserversAndEnableWork() async throws {
        let store = TestHealthStore()
        let factory = TestObserverQueryFactory()
        let service = HealthKitService(store: store, observerQueryFactory: factory)

        let first = try service.beginBackgroundDeliveryConfiguration { _ in }
        let second = try service.beginBackgroundDeliveryConfiguration { _ in }

        XCTAssertEqual(store.executedQueries.count, HealthKitService.readMetricTypeIdentifiers.count)
        try await first.value
        try await second.value

        XCTAssertEqual(store.executedQueries.count, HealthKitService.readMetricTypeIdentifiers.count)
        XCTAssertEqual(
            Set(store.enabledTypeIdentifiers),
            HealthKitService.readMetricTypeIdentifiers
        )
        XCTAssertEqual(store.enabledTypeIdentifiers.count, HealthKitService.readMetricTypeIdentifiers.count)
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
            HealthKitService.readMetricTypeIdentifiers.count + 1
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
            HealthKitService.readMetricTypeIdentifiers.count + 1
        )
        XCTAssertEqual(Set(store.enabledTypeIdentifiers), HealthKitService.readMetricTypeIdentifiers)
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

        XCTAssertEqual(store.executedQueries.count, HealthKitService.readMetricTypeIdentifiers.count)
        XCTAssertEqual(store.stoppedQueries.count, HealthKitService.readMetricTypeIdentifiers.count)

        store.enableFailureTypeIdentifier = nil
        try await service.configureBackgroundDelivery { _ in }

        XCTAssertEqual(store.executedQueries.count, HealthKitService.readMetricTypeIdentifiers.count * 2)
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
