import Foundation
import HealthKit
import SwiftData

protocol PrivateAppStatePersisting: AnyObject {
    var removesLegacyDefaultsAfterSave: Bool { get }
    func data(forKey key: String) -> Data?
    @discardableResult func set(_ data: Data, forKey key: String) -> Bool
    @discardableResult func removeData(forKey key: String) -> Bool
}

final class ApplicationSupportPrivateAppStateStore: PrivateAppStatePersisting {
    private let directoryURL: URL?

    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("PrivateState", isDirectory: true)
    }

    let removesLegacyDefaultsAfterSave = true

    func data(forKey key: String) -> Data? {
        guard let fileURL = fileURL(forKey: key) else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    @discardableResult
    func set(_ data: Data, forKey key: String) -> Bool {
        guard var directoryURL, var fileURL = fileURL(forKey: key) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            var directoryValues = URLResourceValues()
            directoryValues.isExcludedFromBackup = true
            try directoryURL.setResourceValues(directoryValues)
            try data.write(
                to: fileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            var fileValues = URLResourceValues()
            fileValues.isExcludedFromBackup = true
            try fileURL.setResourceValues(fileValues)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func removeData(forKey key: String) -> Bool {
        guard let fileURL = fileURL(forKey: key) else { return false }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return true }
        do {
            try FileManager.default.removeItem(at: fileURL)
            return true
        } catch {
            return false
        }
    }

    private func fileURL(forKey key: String) -> URL? {
        directoryURL?.appendingPathComponent("\(key).json", isDirectory: false)
    }
}

#if DEBUG
private final class UserDefaultsPrivateAppStateStore: PrivateAppStatePersisting {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    let removesLegacyDefaultsAfterSave = false

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func set(_ data: Data, forKey key: String) -> Bool {
        defaults.set(data, forKey: key)
        return true
    }

    func removeData(forKey key: String) -> Bool {
        defaults.removeObject(forKey: key)
        return true
    }
}
#endif

enum HealthConnectionState: Equatable, Sendable {
    case notRequested
    case accessRequested
    case dataReceived(sampleCount: Int)
    case partialData(sampleCount: Int, failedQueryCount: Int)
    case noReadableSamples
    case refreshFailed
    case demoData

    var label: String {
        switch self {
        case .notRequested:
            "Not requested"
        case .accessRequested:
            "Access requested"
        case .dataReceived(let sampleCount):
            "Data received · \(sampleCount) samples"
        case .partialData(let sampleCount, _):
            "Partial data · \(sampleCount) samples"
        case .noReadableSamples:
            "No readable samples"
        case .refreshFailed:
            "Refresh failed"
        case .demoData:
            "Demo data"
        }
    }

    var canRequestAccess: Bool {
        self == .notRequested
    }
}

struct PlanApplicationRequest: Sendable {
    let wakeTime: Date
    let gymStart: Date
    let gymEnd: Date
    let workoutTitle: String
    let readinessScore: Int
    let confidence: DataConfidence
    let includesCalendarEvent: Bool
}

struct AppliedPlanStatus: Codable, Equatable, Sendable {
    let wakeTime: Date
    let gymStart: Date
    let gymEnd: Date
    let wakeAlarmApplied: Bool
    let calendarEventApplied: Bool
    let calendarEventRequested: Bool?

    init(
        wakeTime: Date,
        gymStart: Date,
        gymEnd: Date,
        wakeAlarmApplied: Bool,
        calendarEventApplied: Bool,
        calendarEventRequested: Bool? = nil
    ) {
        self.wakeTime = wakeTime
        self.gymStart = gymStart
        self.gymEnd = gymEnd
        self.wakeAlarmApplied = wakeAlarmApplied
        self.calendarEventApplied = calendarEventApplied
        self.calendarEventRequested = calendarEventRequested
    }

    var expectsCalendarEvent: Bool {
        calendarEventRequested ?? calendarEventApplied
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: DailyHealthSnapshot = .empty
    @Published private(set) var plan: DailyPlan = .placeholder()
    @Published private(set) var diagnostics: [SourceDiagnostic] = []
    @Published private(set) var healthQueryFailures: [HealthQueryFailure] = []
    @Published private(set) var healthBackgroundDeliveryFailure: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var healthConnectionState: HealthConnectionState = .notRequested
    @Published private(set) var calendarStatus = "Not connected"
    @Published private(set) var calendarReadFailure: String?
    @Published private(set) var alarmStatus = "Not connected"
    @Published private(set) var isApplying = false
    @Published private(set) var appliedPlanStatus: AppliedPlanStatus?
    @Published private(set) var appliedPlanVerificationMessage: String?
    @Published private(set) var exportingWorkoutIDs: Set<UUID> = []
    @Published var notice: String?
    @Published var preferences: WellnessPreferences {
        didSet {
            savePreferences()
            snapshot = wellness.snapshot(from: snapshot.samples, preferences: preferences, now: .now)
            plan = wellness.plan(snapshot: snapshot, commitment: latestCommitment, preferences: preferences, now: .now)
        }
    }

    var healthStatus: String {
        guard healthBackgroundDeliveryFailure != nil else { return healthConnectionState.label }
        return "\(healthConnectionState.label) · Background updates unavailable"
    }

    private let health: HealthDataProviding
    private let calendar: CalendarProviding
    private let alarms: AlarmScheduling
    private let wellness: WellnessEvaluating
    private let defaults: UserDefaults
    private let privateStateStore: PrivateAppStatePersisting
    private let demoMode: Bool
    private var healthAuthorizationRequested = false
    private var latestCommitment: CalendarCommitment?
    private var refreshQueued = false
    private var refreshQueuedBackgroundDeliveryRetry = false
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    private static let healthAuthorizationRequestedKey = "healthAuthorizationRequested"
    private static let wellnessPreferencesKey = "wellnessPreferences"
    private static let appliedPlanStatusKey = "appliedPlanStatus"

    init(
        health: HealthDataProviding = HealthKitService(),
        calendar: CalendarProviding = CalendarService(),
        alarms: AlarmScheduling = AlarmService(),
        wellness: WellnessEvaluating = WellnessEngine(),
        defaults: UserDefaults = .standard,
        privateStateStore: PrivateAppStatePersisting? = nil,
        demoMode: Bool = false
    ) {
        self.health = health
        self.calendar = calendar
        self.alarms = alarms
        self.wellness = wellness
        self.defaults = defaults
        self.demoMode = demoMode
        let resolvedPrivateStateStore: PrivateAppStatePersisting
        if let privateStateStore {
            resolvedPrivateStateStore = privateStateStore
        } else {
            #if DEBUG
            resolvedPrivateStateStore = (demoMode || defaults !== UserDefaults.standard)
                ? UserDefaultsPrivateAppStateStore(defaults: defaults)
                : ApplicationSupportPrivateAppStateStore()
            #else
            resolvedPrivateStateStore = ApplicationSupportPrivateAppStateStore()
            #endif
        }
        self.privateStateStore = resolvedPrivateStateStore

        if !resolvedPrivateStateStore.removesLegacyDefaultsAfterSave {
            self.healthAuthorizationRequested = defaults.bool(
                forKey: Self.healthAuthorizationRequestedKey
            )
        } else if let data = resolvedPrivateStateStore.data(
            forKey: Self.healthAuthorizationRequestedKey
        ), let requested = try? JSONDecoder().decode(Bool.self, from: data) {
            self.healthAuthorizationRequested = requested
        } else if let requested = defaults.object(
            forKey: Self.healthAuthorizationRequestedKey
        ) as? Bool {
            self.healthAuthorizationRequested = requested
            if let data = try? JSONEncoder().encode(requested),
               resolvedPrivateStateStore.set(
                   data,
                   forKey: Self.healthAuthorizationRequestedKey
               ) {
                defaults.removeObject(forKey: Self.healthAuthorizationRequestedKey)
            }
        }

        if let data = resolvedPrivateStateStore.data(forKey: Self.wellnessPreferencesKey),
           let saved = try? JSONDecoder().decode(WellnessPreferences.self, from: data) {
            self.preferences = saved
        } else if let legacyData = defaults.data(forKey: Self.wellnessPreferencesKey),
                  let saved = try? JSONDecoder().decode(WellnessPreferences.self, from: legacyData) {
            self.preferences = saved
            if resolvedPrivateStateStore.set(legacyData, forKey: Self.wellnessPreferencesKey),
               resolvedPrivateStateStore.removesLegacyDefaultsAfterSave {
                defaults.removeObject(forKey: Self.wellnessPreferencesKey)
            }
        } else {
            self.preferences = .default
        }
        self.healthConnectionState = demoMode
            ? .demoData
            : (healthAuthorizationRequested ? .accessRequested : .notRequested)
        self.calendarStatus = calendar.authorizationLabel
        self.alarmStatus = alarms.authorizationLabel
        if let data = resolvedPrivateStateStore.data(forKey: Self.appliedPlanStatusKey) {
            self.appliedPlanStatus = try? JSONDecoder().decode(AppliedPlanStatus.self, from: data)
        } else if let legacyData = defaults.data(forKey: Self.appliedPlanStatusKey),
                  let status = try? JSONDecoder().decode(AppliedPlanStatus.self, from: legacyData) {
            self.appliedPlanStatus = status
            if resolvedPrivateStateStore.set(legacyData, forKey: Self.appliedPlanStatusKey),
               resolvedPrivateStateStore.removesLegacyDefaultsAfterSave {
                defaults.removeObject(forKey: Self.appliedPlanStatusKey)
            }
        }
    }

    @discardableResult
    func connectHealth() async -> Bool {
        do {
            try await health.requestAuthorization()
            healthAuthorizationRequested = true
            let savedAuthorizationState = saveHealthAuthorizationRequested()
            healthConnectionState = .accessRequested
            await observeHealthUpdates()
            await refresh(retryingBackgroundDeliveryIfNeeded: false)
            if !savedAuthorizationState, notice == nil {
                notice = "Health access was requested, but Sleep Coach couldn’t securely save that setup state. You may need to connect again after relaunching."
            }
            return true
        } catch {
            healthConnectionState = healthAuthorizationRequested
                ? .accessRequested
                : .notRequested
            notice = error.localizedDescription
            return false
        }
    }

    func connectCalendar() async {
        do {
            calendarStatus = try await calendar.requestAccess() ? "Connected" : "Denied"
            await refresh()
        } catch {
            calendarStatus = "Denied"
            notice = error.localizedDescription
        }
    }

    func refresh() async {
        await refresh(retryingBackgroundDeliveryIfNeeded: true)
    }

    private func refresh(retryingBackgroundDeliveryIfNeeded: Bool) async {
        if isRefreshing {
            refreshQueued = true
            refreshQueuedBackgroundDeliveryRetry = refreshQueuedBackgroundDeliveryRetry
                || retryingBackgroundDeliveryIfNeeded
            await withCheckedContinuation { continuation in
                refreshWaiters.append(continuation)
            }
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            let waiters = refreshWaiters
            refreshWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }

        var shouldRetryBackgroundDelivery = retryingBackgroundDeliveryIfNeeded
        repeat {
            refreshQueued = false
            shouldRetryBackgroundDelivery = shouldRetryBackgroundDelivery
                || refreshQueuedBackgroundDeliveryRetry
            refreshQueuedBackgroundDeliveryRetry = false

            if shouldRetryBackgroundDelivery,
               healthBackgroundDeliveryFailure != nil,
               (demoMode || healthAuthorizationRequested) {
                await observeHealthUpdates()
            }

            shouldRetryBackgroundDelivery = false
            await performRefresh()
        } while refreshQueued
    }

    private func performRefresh() async {
        if demoMode || healthAuthorizationRequested {
            do {
                let start = Calendar.current.date(byAdding: .day, value: -35, to: .now)!
                let result = try await health.fetchSamples(since: start, through: .now)
                let samples = result.samples
                let wellness = self.wellness
                let preferences = self.preferences
                let processed = await Task.detached(priority: .userInitiated) {
                    (
                        HealthKitService.diagnostics(from: samples),
                        wellness.snapshot(from: samples, preferences: preferences, now: .now)
                    )
                }.value
                diagnostics = processed.0
                snapshot = processed.1
                healthQueryFailures = result.queryFailures
                if result.isPartial {
                    healthConnectionState = .partialData(
                        sampleCount: samples.count,
                        failedQueryCount: result.queryFailures.count
                    )
                } else if demoMode {
                    healthConnectionState = .demoData
                } else if samples.isEmpty {
                    healthConnectionState = .noReadableSamples
                } else {
                    healthConnectionState = .dataReceived(sampleCount: samples.count)
                }
            } catch {
                // Never leave a previously generated recommendation looking current
                // after every requested HealthKit query failed.
                diagnostics = []
                snapshot = wellness.snapshot(from: [], preferences: preferences, now: .now)
                if let healthError = error as? HealthDataError,
                   case .queryFailed(let failures) = healthError {
                    healthQueryFailures = failures
                } else {
                    healthQueryFailures = []
                }
                healthConnectionState = .refreshFailed
                notice = error.localizedDescription
            }
        } else {
            diagnostics = []
            snapshot = wellness.snapshot(from: [], preferences: preferences, now: .now)
            healthQueryFailures = []
            healthConnectionState = .notRequested
        }

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let commitment: CalendarCommitment?
        do {
            commitment = try await calendar.firstCommitment(on: tomorrow)
            calendarReadFailure = nil
        } catch CalendarError.accessRequired where calendarStatus != "Connected" {
            // Calendar is optional. A user who has not connected it is an expected
            // state, not a failed refresh; the Plan screen already offers access.
            commitment = nil
            calendarReadFailure = nil
        } catch {
            commitment = nil
            calendarReadFailure = error.localizedDescription
        }
        latestCommitment = commitment
        plan = wellness.plan(snapshot: snapshot, commitment: commitment, preferences: preferences, now: .now)
        alarmStatus = alarms.authorizationLabel
        reconcileAppliedPlan()
    }

    func start() async {
        if demoMode || healthAuthorizationRequested {
            await observeHealthUpdates()
        }
        await refresh(retryingBackgroundDeliveryIfNeeded: false)
    }

    /// Called from the application delegate during launch so HealthKit observer
    /// setup is not coupled to the first SwiftUI view appearing.
    func prepareHealthObservationAtLaunch() async {
        guard shouldPrepareHealthObservationAtLaunch else { return }
        await observeHealthUpdates()
    }

    var shouldPrepareHealthObservationAtLaunch: Bool {
        !demoMode && healthAuthorizationRequested
    }

    func handleHealthBackgroundEvent(
        _ event: HealthBackgroundEvent
    ) async {
        switch event {
        case .dataChanged:
            await refresh(retryingBackgroundDeliveryIfNeeded: false)

        case .observerFailed(_, let typeIdentifier, let message):
            let failure = HealthDataError.backgroundDeliveryConfigurationFailed(
                typeIdentifier: typeIdentifier,
                message: message
            ).localizedDescription
            healthBackgroundDeliveryFailure = failure
            notice = failure

            // HealthKitService removes the invalid query before reporting this
            // event. Reconfiguration installs a fresh observer and keeps the
            // failure visible if that retry does not succeed.
            await observeHealthUpdates()
        }
    }

    func recomputePlan() {
        plan = wellness.plan(snapshot: snapshot, commitment: latestCommitment, preferences: preferences, now: .now)
    }

    func refreshConnectionStatuses() {
        guard !demoMode else { return }
        calendarStatus = calendar.authorizationLabel
        alarmStatus = alarms.authorizationLabel
    }

    func refreshForForeground() async {
        refreshConnectionStatuses()
        await refresh()
    }

    func planApplicationRequest() -> PlanApplicationRequest {
        PlanApplicationRequest(
            wakeTime: plan.wakeTime,
            gymStart: plan.gymStart,
            gymEnd: plan.gymEnd,
            workoutTitle: plan.workoutAdjustment.title,
            readinessScore: snapshot.readinessScore,
            confidence: snapshot.confidence,
            includesCalendarEvent: calendarStatus == "Connected"
        )
    }

    func applyPlan(_ requestedPlan: PlanApplicationRequest? = nil) async {
        guard !isApplying else { return }
        let requestedPlan = requestedPlan ?? planApplicationRequest()
        let previouslyAppliedPlan = appliedPlanStatus
        let previousVerificationMessage = appliedPlanVerificationMessage
        guard requestedPlan.wakeTime > .now else {
            notice = "This wake time has passed. Refresh the plan before applying it."
            return
        }
        isApplying = true
        defer { isApplying = false }

        // Persist intent before crossing either system-write boundary. If iOS
        // terminates the app during a permission sheet or between writes, the
        // next launch retains an Undo path for any app-owned item that may exist.
        let journal = AppliedPlanStatus(
            wakeTime: requestedPlan.wakeTime,
            gymStart: requestedPlan.gymStart,
            gymEnd: requestedPlan.gymEnd,
            wakeAlarmApplied: true,
            calendarEventApplied: requestedPlan.includesCalendarEvent
                || previouslyAppliedPlan?.calendarEventApplied == true,
            calendarEventRequested: requestedPlan.includesCalendarEvent
                || previouslyAppliedPlan?.calendarEventApplied == true
        )
        appliedPlanStatus = journal
        appliedPlanVerificationMessage = "Plan application is in progress. If it was interrupted, use Undo before applying again."
        guard saveAppliedPlanStatus() else {
            appliedPlanStatus = previouslyAppliedPlan
            appliedPlanVerificationMessage = previousVerificationMessage
            notice = "Sleep Coach couldn’t securely save the plan before applying it. No system changes were requested."
            return
        }

        var successes: [String] = []
        var failures: [String] = []
        var replacementWarnings: [String] = []
        var wakeAlarmMayNeedCleanup = previouslyAppliedPlan?.wakeAlarmApplied == true
        var alarmFailureMayHaveTrackedAlarm = false

        if requestedPlan.includesCalendarEvent {
            do {
                try await calendar.createGymEvent(
                    start: requestedPlan.gymStart,
                    end: requestedPlan.gymEnd,
                    note: "Created by Sleep Coach."
                )
                successes.append("gym event")
            } catch {
                failures.append("Calendar: \(error.localizedDescription)")
                if previouslyAppliedPlan?.calendarEventApplied == true {
                    replacementWarnings.append(
                        "A previously applied gym event may still be active because its replacement failed. Use Undo to remove it before applying again."
                    )
                }
            }
        } else if previouslyAppliedPlan?.calendarEventApplied == true {
            replacementWarnings.append(
                "A previously applied gym event may still be active because this plan did not replace it. Use Undo to remove it before applying again."
            )
        }

        do {
            try await alarms.scheduleWakeAlarm(at: requestedPlan.wakeTime)
            successes.append("wake alarm")
        } catch {
            failures.append("Alarm: \(error.localizedDescription)")
            let alarmServiceError = error as? AlarmServiceError
            alarmFailureMayHaveTrackedAlarm = alarmServiceError?.mayHaveTrackedAlarm == true
            wakeAlarmMayNeedCleanup = wakeAlarmMayNeedCleanup
                || alarmFailureMayHaveTrackedAlarm
            if alarmFailureMayHaveTrackedAlarm {
                replacementWarnings.append(
                    "Sleep Coach could not verify every app-owned wake alarm. Use Undo before applying again."
                )
            } else if previouslyAppliedPlan?.wakeAlarmApplied == true {
                replacementWarnings.append(
                    "A previously applied wake alarm may still be active because its replacement failed. Use Undo to remove it before applying again."
                )
            }
        }

        alarmStatus = alarms.authorizationLabel
        let status: AppliedPlanStatus
        if successes.isEmpty, let previouslyAppliedPlan {
            if alarmFailureMayHaveTrackedAlarm && !previouslyAppliedPlan.wakeAlarmApplied {
                // A calendar-only prior state cannot represent a newly created,
                // unverified alarm. Promote the conservative journal so the
                // alarm remains visible, reconciled, and removable through Undo.
                status = AppliedPlanStatus(
                    wakeTime: requestedPlan.wakeTime,
                    gymStart: requestedPlan.gymStart,
                    gymEnd: requestedPlan.gymEnd,
                    wakeAlarmApplied: true,
                    calendarEventApplied: previouslyAppliedPlan.calendarEventApplied,
                    calendarEventRequested: requestedPlan.includesCalendarEvent
                        || previouslyAppliedPlan.expectsCalendarEvent
                )
            } else {
                status = previouslyAppliedPlan
            }
        } else if successes.isEmpty {
            status = journal
            replacementWarnings.append(
                "Sleep Coach could not confirm whether a system item was created. Use Undo before applying again."
            )
        } else {
            status = AppliedPlanStatus(
                wakeTime: requestedPlan.wakeTime,
                gymStart: requestedPlan.gymStart,
                gymEnd: requestedPlan.gymEnd,
                wakeAlarmApplied: successes.contains("wake alarm")
                    || wakeAlarmMayNeedCleanup,
                calendarEventApplied: successes.contains("gym event")
                    || previouslyAppliedPlan?.calendarEventApplied == true,
                calendarEventRequested: requestedPlan.includesCalendarEvent
                    || previouslyAppliedPlan?.calendarEventApplied == true
            )
        }
        if status.wakeAlarmApplied || status.calendarEventApplied {
            appliedPlanStatus = status
            appliedPlanVerificationMessage = replacementWarnings.isEmpty
                ? nil
                : replacementWarnings.joined(separator: " ")
            if !saveAppliedPlanStatus() {
                appliedPlanVerificationMessage = "The system items may be active, but Sleep Coach couldn’t securely update their local status. Use Undo before applying again."
            }
        }
        if failures.isEmpty {
            notice = nil
        } else if successes.isEmpty {
            notice = failures.joined(separator: "\n")
        } else {
            notice = "Applied \(successes.joined(separator: " and ")). \(failures.joined(separator: " "))"
        }
    }

    func undoAppliedPlan() {
        guard !isApplying else {
            notice = "Wait for the current plan application to finish before undoing it."
            return
        }
        guard let status = appliedPlanStatus else { return }
        var failures: [String] = []
        var wakeAlarmRemaining = status.wakeAlarmApplied
        var calendarEventRemaining = status.calendarEventApplied
        // Both services scope cancellation to their persisted app-owned identifier,
        // so attempting both also cleans up an item whose external state drifted.
        do {
            try calendar.cancelGymEvent(start: status.gymStart, end: status.gymEnd)
            calendarEventRemaining = false
        } catch {
            failures.append("Calendar: \(error.localizedDescription)")
        }
        do {
            try alarms.cancelWakeAlarm()
            wakeAlarmRemaining = false
        } catch {
            failures.append("Alarm: \(error.localizedDescription)")
        }
        if !wakeAlarmRemaining && !calendarEventRemaining {
            if privateStateStore.removeData(forKey: Self.appliedPlanStatusKey) {
                appliedPlanStatus = nil
                appliedPlanVerificationMessage = nil
                alarmStatus = alarms.authorizationLabel
            } else {
                appliedPlanVerificationMessage = "The system items were removed, but Sleep Coach couldn’t clear their local status. Try Undo again."
                notice = "The plan was removed from Calendar and Clock, but its local status could not be cleared."
            }
        } else {
            appliedPlanStatus = AppliedPlanStatus(
                wakeTime: status.wakeTime,
                gymStart: status.gymStart,
                gymEnd: status.gymEnd,
                wakeAlarmApplied: wakeAlarmRemaining,
                calendarEventApplied: calendarEventRemaining,
                calendarEventRequested: status.calendarEventRequested
            )
            appliedPlanVerificationMessage = "Some app-owned items could not be removed. Try Undo again after restoring permission."
            if !saveAppliedPlanStatus() {
                appliedPlanVerificationMessage = "Some system items and their last saved local status may remain. Restore permission, then try Undo again."
            }
            notice = "Couldn’t undo the full plan. \(failures.joined(separator: " "))"
        }
    }

    func recordStrengthWorkout(_ session: WorkoutSessionRecord, in modelContext: ModelContext) async {
        await exportPersistedStrengthWorkout(session, in: modelContext, prepareRetry: false)
    }

    func retryStrengthWorkoutExport(_ session: WorkoutSessionRecord, in modelContext: ModelContext) async {
        await exportPersistedStrengthWorkout(session, in: modelContext, prepareRetry: true)
    }

    func isExportingWorkout(_ sessionID: UUID) -> Bool {
        exportingWorkoutIDs.contains(sessionID)
    }

    private func exportPersistedStrengthWorkout(
        _ session: WorkoutSessionRecord,
        in modelContext: ModelContext,
        prepareRetry: Bool
    ) async {
        guard !exportingWorkoutIDs.contains(session.id) else { return }
        if prepareRetry {
            guard session.healthExportState == .pending || session.healthExportState == .failed else { return }
        } else {
            guard session.healthExportState == .pending else { return }
        }

        if prepareRetry {
            let previous = workoutExportSnapshot(session)
            guard session.prepareHealthExportRetry() else {
                notice = "This workout can’t be retried because its Apple Health sync version is invalid."
                return
            }
            do {
                // Commit the attempt version before touching HealthKit. If the app
                // exits after this point, replaying the pending version is safe.
                try modelContext.save()
            } catch {
                restoreWorkoutExportSnapshot(previous, to: session)
                notice = "The workout is still saved, but its Apple Health retry could not be prepared. Please try again."
                return
            }
        }

        guard session.healthExportState == .pending else { return }
        exportingWorkoutIDs.insert(session.id)
        defer { exportingWorkoutIDs.remove(session.id) }

        do {
            try await health.saveStrengthWorkout(
                sessionID: session.id,
                syncVersion: session.healthExportSyncVersion,
                start: session.startedAt,
                end: session.endedAt
            )
            let previous = workoutExportSnapshot(session)
            session.markHealthExported()
            do {
                try modelContext.save()
            } catch {
                // Keep the locally durable state pending. The next retry commits a
                // greater version so HealthKit replaces any accepted prior attempt.
                restoreWorkoutExportSnapshot(previous, to: session)
                notice = "Apple Health accepted the workout, but its local export status could not be saved. Retrying from Training History is safe."
            }
        } catch {
            let exportMessage = error.localizedDescription
            let previous = workoutExportSnapshot(session)
            session.markHealthExportFailed(message: exportMessage)
            do {
                try modelContext.save()
                notice = "Workout saved in Sleep Coach, but it couldn’t be added to Apple Health. Retry from Training History when you’re ready."
            } catch {
                restoreWorkoutExportSnapshot(previous, to: session)
                notice = "Workout saved in Sleep Coach, but it couldn’t be added to Apple Health or update its export status. Retry from Training History."
            }
        }
    }

    private typealias WorkoutExportSnapshot = (stateRaw: String, syncVersion: Int, errorMessage: String?)

    private func workoutExportSnapshot(_ session: WorkoutSessionRecord) -> WorkoutExportSnapshot {
        (session.healthExportStateRaw, session.healthExportSyncVersion, session.healthExportErrorMessage)
    }

    private func restoreWorkoutExportSnapshot(
        _ snapshot: WorkoutExportSnapshot,
        to session: WorkoutSessionRecord
    ) {
        session.healthExportStateRaw = snapshot.stateRaw
        session.healthExportSyncVersion = snapshot.syncVersion
        session.healthExportErrorMessage = snapshot.errorMessage
    }

    private func savePreferences() {
        if let data = try? JSONEncoder().encode(preferences) {
            if privateStateStore.set(data, forKey: Self.wellnessPreferencesKey) {
                if privateStateStore.removesLegacyDefaultsAfterSave {
                    defaults.removeObject(forKey: Self.wellnessPreferencesKey)
                }
            } else {
                notice = "Sleep Coach couldn’t securely save your preferences. Keep the app open and try again after unlocking your iPhone."
            }
        }
    }

    @discardableResult
    private func saveHealthAuthorizationRequested() -> Bool {
        if !privateStateStore.removesLegacyDefaultsAfterSave {
            defaults.set(healthAuthorizationRequested, forKey: Self.healthAuthorizationRequestedKey)
            return true
        }
        guard let data = try? JSONEncoder().encode(healthAuthorizationRequested) else {
            return false
        }
        let saved = privateStateStore.set(data, forKey: Self.healthAuthorizationRequestedKey)
        if saved { defaults.removeObject(forKey: Self.healthAuthorizationRequestedKey) }
        return saved
    }

    @discardableResult
    private func saveAppliedPlanStatus() -> Bool {
        guard let appliedPlanStatus,
              let data = try? JSONEncoder().encode(appliedPlanStatus) else { return false }
        let saved = privateStateStore.set(data, forKey: Self.appliedPlanStatusKey)
        if saved, privateStateStore.removesLegacyDefaultsAfterSave {
            defaults.removeObject(forKey: Self.appliedPlanStatusKey)
        }
        return saved
    }

    private func reconcileAppliedPlan() {
        // Applying a plan journals its identifiers before either external write.
        // Do not inspect that intentionally in-flight state: AlarmKit may not yet
        // expose the new alarm, and reconciliation would otherwise prune the
        // identifier that makes an interrupted apply recoverable through Undo.
        guard !isApplying else { return }
        guard let current = appliedPlanStatus else { return }
        var messages: [String] = []

        if current.wakeAlarmApplied {
            do {
                if try !alarms.hasWakeAlarm(scheduledAt: current.wakeTime) {
                    messages.append("The saved wake alarm doesn’t match this plan. It may have fired, been edited, or been removed.")
                }
            } catch {
                messages.append("Sleep Coach couldn’t verify the saved wake alarm: \(error.localizedDescription)")
            }
        }

        if current.calendarEventApplied {
            do {
                if try !calendar.hasGymEvent(start: current.gymStart, end: current.gymEnd) {
                    messages.append("The saved gym event doesn’t match this plan. It may have been edited or removed.")
                }
            } catch {
                messages.append("Sleep Coach couldn’t verify the saved gym event: \(error.localizedDescription)")
            }
        }

        // A failed verification can also mean the item was edited or has already
        // fired. Preserve the app-owned identifiers and last-known applied state so
        // Undo can still clean up any surviving external item.
        appliedPlanVerificationMessage = messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    private func observeHealthUpdates() async {
        let previousFailure = healthBackgroundDeliveryFailure
        do {
            try await health.configureBackgroundDelivery { [weak self] event in
                await self?.handleHealthBackgroundEvent(event)
            }
            healthBackgroundDeliveryFailure = nil
            if notice == previousFailure { notice = nil }
        } catch {
            let message = error.localizedDescription
            healthBackgroundDeliveryFailure = message
            notice = message
        }
    }
}
