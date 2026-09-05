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
    let calendarDestinations: CalendarEventDestinations?

    init(
        wakeTime: Date,
        gymStart: Date,
        gymEnd: Date,
        workoutTitle: String,
        readinessScore: Int,
        confidence: DataConfidence,
        includesCalendarEvent: Bool,
        calendarDestinations: CalendarEventDestinations? = nil
    ) {
        self.wakeTime = wakeTime
        self.gymStart = gymStart
        self.gymEnd = gymEnd
        self.workoutTitle = workoutTitle
        self.readinessScore = readinessScore
        self.confidence = confidence
        self.includesCalendarEvent = includesCalendarEvent
        self.calendarDestinations = calendarDestinations
    }
}

struct AppliedPlanStatus: Codable, Equatable, Sendable {
    let wakeTime: Date
    let gymStart: Date
    let gymEnd: Date
    let wakeAlarmApplied: Bool
    let calendarEventApplied: Bool
    let calendarEventRequested: Bool?
    let calendarEventReceipts: [CalendarEventReceipt]
    let calendarEventRequestedCount: Int?
    let calendarEventDestinations: CalendarEventDestinations?
    let calendarEventIssues: [String]

    init(
        wakeTime: Date,
        gymStart: Date,
        gymEnd: Date,
        wakeAlarmApplied: Bool,
        calendarEventApplied: Bool,
        calendarEventRequested: Bool? = nil,
        calendarEventReceipts: [CalendarEventReceipt] = [],
        calendarEventRequestedCount: Int? = nil,
        calendarEventDestinations: CalendarEventDestinations? = nil,
        calendarEventIssues: [String] = []
    ) {
        self.wakeTime = wakeTime
        self.gymStart = gymStart
        self.gymEnd = gymEnd
        self.wakeAlarmApplied = wakeAlarmApplied
        self.calendarEventApplied = calendarEventApplied
        self.calendarEventRequested = calendarEventRequested
        self.calendarEventReceipts = calendarEventReceipts
        self.calendarEventRequestedCount = calendarEventRequestedCount
        self.calendarEventDestinations = calendarEventDestinations
        self.calendarEventIssues = calendarEventIssues
    }

    var expectsCalendarEvent: Bool {
        calendarEventRequested ?? calendarEventApplied
    }

    var appliedCalendarEventCount: Int {
        guard calendarEventDestinations != nil else {
            return calendarEventReceipts.isEmpty
                ? (calendarEventApplied ? 1 : 0)
                : calendarEventReceipts.count
        }
        return expectedCalendarTargets.intersection(receiptCalendarTargets).count
    }

    var requestedCalendarEventCount: Int {
        calendarEventRequestedCount
            ?? calendarEventDestinations?.requestedCount
            ?? (expectsCalendarEvent ? 1 : 0)
    }

    var calendarEventsComplete: Bool {
        !expectsCalendarEvent
            || (calendarEventApplied
                && calendarEventIssues.isEmpty
                && !hasObsoleteCalendarReceipts
                && appliedCalendarEventCount >= requestedCalendarEventCount)
    }

    var hasObsoleteCalendarReceipts: Bool {
        guard calendarEventDestinations != nil else { return false }
        return !receiptCalendarTargets.subtracting(expectedCalendarTargets).isEmpty
    }

    func matches(calendarDestinations destinations: CalendarEventDestinations) -> Bool {
        let desiredTargets = Self.targets(for: destinations)
        let statusTargets = calendarEventDestinations.map { Self.targets(for: $0) }
            ?? receiptCalendarTargets
        return desiredTargets == statusTargets
    }

    private struct CalendarTarget: Hashable {
        let role: CalendarEventRole
        let calendarIdentifier: String
    }

    private var expectedCalendarTargets: Set<CalendarTarget> {
        guard let calendarEventDestinations else { return [] }
        return Self.targets(for: calendarEventDestinations)
    }

    private static func targets(
        for destinations: CalendarEventDestinations
    ) -> Set<CalendarTarget> {
        var targets: Set<CalendarTarget> = []
        if let identifier = destinations.detailedCalendarIdentifier {
            targets.insert(CalendarTarget(role: .detailed, calendarIdentifier: identifier))
        }
        targets.formUnion(destinations.busyCalendarIdentifiers.map {
            CalendarTarget(role: .busy, calendarIdentifier: $0)
        })
        return targets
    }

    private var receiptCalendarTargets: Set<CalendarTarget> {
        Set(calendarEventReceipts.map {
            CalendarTarget(role: $0.role, calendarIdentifier: $0.calendarIdentifier)
        })
    }

    private enum CodingKeys: String, CodingKey {
        case wakeTime
        case gymStart
        case gymEnd
        case wakeAlarmApplied
        case calendarEventApplied
        case calendarEventRequested
        case calendarEventReceipts
        case calendarEventRequestedCount
        case calendarEventDestinations
        case calendarEventIssues
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        wakeTime = try values.decode(Date.self, forKey: .wakeTime)
        gymStart = try values.decode(Date.self, forKey: .gymStart)
        gymEnd = try values.decode(Date.self, forKey: .gymEnd)
        wakeAlarmApplied = try values.decode(Bool.self, forKey: .wakeAlarmApplied)
        calendarEventApplied = try values.decode(Bool.self, forKey: .calendarEventApplied)
        calendarEventRequested = try values.decodeIfPresent(Bool.self, forKey: .calendarEventRequested)
        calendarEventReceipts = try values.decodeIfPresent(
            [CalendarEventReceipt].self,
            forKey: .calendarEventReceipts
        ) ?? []
        calendarEventRequestedCount = try values.decodeIfPresent(
            Int.self,
            forKey: .calendarEventRequestedCount
        )
        calendarEventDestinations = try values.decodeIfPresent(
            CalendarEventDestinations.self,
            forKey: .calendarEventDestinations
        )
        calendarEventIssues = try values.decodeIfPresent(
            [String].self,
            forKey: .calendarEventIssues
        ) ?? []
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: DailyHealthSnapshot = .empty
    @Published private(set) var plan: DailyPlan = .placeholder()
    @Published private(set) var diagnostics: [SourceDiagnostic] = []
    @Published private(set) var healthQueryFailures: [HealthQueryFailure] = []
    @Published private(set) var healthBackgroundDeliveryFailure: String?
    @Published private(set) var healthAccessReviewRecommended = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var healthConnectionState: HealthConnectionState = .notRequested
    @Published private(set) var calendarStatus = "Not connected"
    @Published private(set) var calendarReadFailure: String?
    @Published private(set) var calendarConfigurationFailure: String?
    @Published private(set) var calendarSources: [CalendarSourceDescriptor] = []
    @Published private(set) var alarmStatus = "Not connected"
    @Published private(set) var isApplying = false
    @Published private(set) var appliedPlanStatus: AppliedPlanStatus?
    @Published private(set) var appliedPlanVerificationMessage: String?
    @Published private(set) var exportingWorkoutIDs: Set<UUID> = []
    @Published var notice: String?
    @Published var workoutBuildIntent: WorkoutBuildIntent?
    @Published var preferences: WellnessPreferences {
        didSet {
            savePreferences()
            snapshot = wellness.snapshot(from: snapshot.samples, preferences: preferences, now: .now)
            plan = wellness.plan(snapshot: snapshot, commitment: latestCommitment, preferences: preferences, now: .now)
        }
    }
    @Published var trainingProfile: TrainingProfile = .default {
        didSet { saveTrainingProfile() }
    }
    @Published var calendarPreferences: CalendarSelectionPreferences = .default {
        didSet { saveCalendarPreferences() }
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
    private var healthAuthorizationSchemaVersion = 0
    private var latestCommitment: CalendarCommitment?
    private var refreshQueued = false
    private var refreshQueuedBackgroundDeliveryRetry = false
    private var refreshQueuedHealthFailureNotice = false
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    private static let healthAuthorizationRequestedKey = "healthAuthorizationRequested"
    private static let healthAuthorizationSchemaVersionKey = "healthAuthorizationSchemaVersion"
    private static let wellnessPreferencesKey = "wellnessPreferences"
    private static let trainingProfileKey = "trainingProfile"
    private static let appliedPlanStatusKey = "appliedPlanStatus"
    private static let calendarPreferencesKey = "calendarPreferences"
    private static let lastMeaningfulUseKey = "lastMeaningfulUse"
    private static let motivationAcknowledgementsKey = "motivationAcknowledgements"

    init(
        health: HealthDataProviding = HealthKitService(),
        calendar: CalendarProviding? = nil,
        alarms: AlarmScheduling = AlarmService(),
        wellness: WellnessEvaluating = WellnessEngine(),
        defaults: UserDefaults = .standard,
        privateStateStore: PrivateAppStatePersisting? = nil,
        demoMode: Bool = false
    ) {
        self.health = health
        self.calendar = calendar ?? CalendarService()
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

        if let data = resolvedPrivateStateStore.data(forKey: Self.calendarPreferencesKey),
           let saved = try? JSONDecoder().decode(CalendarSelectionPreferences.self, from: data) {
            var normalized = saved
            let removedOverlap = normalized.normalizeDestinationOverlap()
            self.calendarPreferences = normalized
            if removedOverlap, let normalizedData = try? JSONEncoder().encode(normalized) {
                _ = resolvedPrivateStateStore.set(
                    normalizedData,
                    forKey: Self.calendarPreferencesKey
                )
            }
        } else if let legacyData = defaults.data(forKey: Self.calendarPreferencesKey),
                  let saved = try? JSONDecoder().decode(
                    CalendarSelectionPreferences.self,
                    from: legacyData
                  ) {
            var normalized = saved
            _ = normalized.normalizeDestinationOverlap()
            self.calendarPreferences = normalized
            let normalizedData = (try? JSONEncoder().encode(normalized)) ?? legacyData
            if resolvedPrivateStateStore.set(normalizedData, forKey: Self.calendarPreferencesKey),
               resolvedPrivateStateStore.removesLegacyDefaultsAfterSave {
                defaults.removeObject(forKey: Self.calendarPreferencesKey)
            }
        }

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

        if !resolvedPrivateStateStore.removesLegacyDefaultsAfterSave {
            self.healthAuthorizationSchemaVersion = defaults.integer(
                forKey: Self.healthAuthorizationSchemaVersionKey
            )
        } else if let data = resolvedPrivateStateStore.data(
            forKey: Self.healthAuthorizationSchemaVersionKey
        ), let version = try? JSONDecoder().decode(Int.self, from: data) {
            self.healthAuthorizationSchemaVersion = max(version, 0)
        } else if let version = defaults.object(
            forKey: Self.healthAuthorizationSchemaVersionKey
        ) as? Int {
            self.healthAuthorizationSchemaVersion = max(version, 0)
            if let data = try? JSONEncoder().encode(max(version, 0)),
               resolvedPrivateStateStore.set(
                   data,
                   forKey: Self.healthAuthorizationSchemaVersionKey
               ) {
                defaults.removeObject(forKey: Self.healthAuthorizationSchemaVersionKey)
            }
        } else if self.healthAuthorizationRequested {
            // The original Health request contained only sleep, HRV, and resting
            // heart rate. Mark it as schema 1 so an existing install is offered
            // the expanded iOS 26 request exactly once through Review Health Access.
            self.healthAuthorizationSchemaVersion = 1
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
        if let data = resolvedPrivateStateStore.data(forKey: Self.trainingProfileKey),
           let saved = try? JSONDecoder().decode(TrainingProfile.self, from: data) {
            self.trainingProfile = saved
        } else if let legacyData = defaults.data(forKey: Self.trainingProfileKey),
                  let saved = try? JSONDecoder().decode(TrainingProfile.self, from: legacyData) {
            self.trainingProfile = saved
            if resolvedPrivateStateStore.set(legacyData, forKey: Self.trainingProfileKey),
               resolvedPrivateStateStore.removesLegacyDefaultsAfterSave {
                defaults.removeObject(forKey: Self.trainingProfileKey)
            }
        }
        self.healthConnectionState = demoMode
            ? .demoData
            : (healthAuthorizationRequested ? .accessRequested : .notRequested)
        self.calendarStatus = self.calendar.authorizationLabel
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

        self.calendar.setEventStoreChangeHandler { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleCalendarStoreChange()
            }
        }
        refreshCalendarConfiguration()
    }

    func returningExperience(now: Date = .now, calendar: Calendar = .current) -> ReturningExperience {
        let previousUse = privateStateStore.data(forKey: Self.lastMeaningfulUseKey)
            .flatMap { try? JSONDecoder().decode(Date.self, from: $0) }
        return ReturningExperience.classify(previousUse: previousUse, now: now, calendar: calendar)
    }

    @discardableResult
    func recordMeaningfulUse(at date: Date = .now) -> Bool {
        guard let data = try? JSONEncoder().encode(date) else { return false }
        return privateStateStore.set(data, forKey: Self.lastMeaningfulUseKey)
    }

    func hasAcknowledgedMotivationReceipt(_ identifier: String) -> Bool {
        motivationAcknowledgements().contains(identifier)
    }

    @discardableResult
    func acknowledgeMotivationReceipt(_ identifier: String) -> Bool {
        guard !identifier.isEmpty else { return false }
        var acknowledgements = motivationAcknowledgements()
        acknowledgements.insert(identifier)
        guard let data = try? JSONEncoder().encode(acknowledgements) else { return false }
        return privateStateStore.set(data, forKey: Self.motivationAcknowledgementsKey)
    }

    private func motivationAcknowledgements() -> Set<String> {
        privateStateStore.data(forKey: Self.motivationAcknowledgementsKey)
            .flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) }
            ?? []
    }

    @discardableResult
    func connectHealth() async -> Bool {
        do {
            try await health.requestAuthorization()
            healthAuthorizationRequested = true
            healthAuthorizationSchemaVersion = max(
                health.authorizationRequestSchema.version,
                healthAuthorizationSchemaVersion
            )
            healthAccessReviewRecommended = false
            let savedAuthorizationState = saveHealthAuthorizationRequested()
                && saveHealthAuthorizationSchemaVersion()
            healthConnectionState = .accessRequested
            await observeHealthUpdates(surfacingFailureAsNotice: true)
            await refresh(
                retryingBackgroundDeliveryIfNeeded: false,
                surfacingHealthFailureAsNotice: true
            )
            if !savedAuthorizationState, notice == nil {
                notice = "Health access was requested, but Dayvera couldn’t securely save that setup state. You may need to connect again after relaunching."
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
            refreshCalendarConfiguration()
            await refresh(
                retryingBackgroundDeliveryIfNeeded: true,
                surfacingHealthFailureAsNotice: false
            )
        } catch {
            calendarStatus = "Denied"
            calendarSources = []
            notice = error.localizedDescription
        }
    }

    var calendarDescriptors: [CalendarDescriptor] {
        calendarSources.flatMap(\.calendars)
    }

    var calendarEventDestinations: CalendarEventDestinations {
        CalendarEventDestinations(
            detailedCalendarIdentifier: calendarPreferences.detailedCalendarIdentifier,
            busyCalendarIdentifiers: calendarPreferences.busyCalendarIdentifiers
        )
    }

    var writableCalendarEventDestinations: CalendarEventDestinations {
        let writableIdentifiers = Set(
            calendarDescriptors.filter(\.allowsContentModifications).map(\.id)
        )
        let detailedIdentifier = calendarPreferences.detailedCalendarIdentifier.flatMap {
            writableIdentifiers.contains($0) ? $0 : nil
        }
        let busyIdentifiers = calendarPreferences.busyCalendarIdentifiers
            .intersection(writableIdentifiers)
            .subtracting(detailedIdentifier.map { [$0] } ?? [])
        return CalendarEventDestinations(
            detailedCalendarIdentifier: detailedIdentifier,
            busyCalendarIdentifiers: busyIdentifiers
        )
    }

    var selectedDetailedCalendar: CalendarDescriptor? {
        guard let identifier = calendarPreferences.detailedCalendarIdentifier else { return nil }
        return calendarDescriptors.first { $0.id == identifier }
    }

    var selectedDetailedCalendarIsUnavailable: Bool {
        guard calendarPreferences.hasInitializedDetailedCalendar,
              calendarPreferences.detailedCalendarIdentifier != nil else { return true }
        guard let selectedDetailedCalendar else { return true }
        return !selectedDetailedCalendar.allowsContentModifications
    }

    var planningCalendarSelectionSummary: String {
        guard let selected = calendarPreferences.planningCalendarIdentifiers else {
            return "All visible calendars"
        }
        let titles = calendarDescriptors
            .filter { selected.contains($0.id) }
            .map(displayCalendarTitle)
        return Self.calendarSelectionSummary(
            titles: titles,
            unavailableCount: unavailablePlanningCalendarIdentifiers.count,
            empty: "No calendars selected"
        )
    }

    var detailedCalendarSelectionSummary: String {
        guard let identifier = calendarPreferences.detailedCalendarIdentifier else {
            return "Not configured"
        }
        guard let descriptor = calendarDescriptors.first(where: { $0.id == identifier }),
              descriptor.allowsContentModifications else {
            return "Selected calendar unavailable"
        }
        return displayCalendarTitle(descriptor)
    }

    var busyCalendarSelectionSummary: String {
        let titles = calendarDescriptors
            .filter { calendarPreferences.busyCalendarIdentifiers.contains($0.id) }
            .map(displayCalendarTitle)
        return Self.calendarSelectionSummary(
            titles: titles,
            unavailableCount: unavailableBusyCalendarIdentifiers.count,
            empty: "No Busy calendars"
        )
    }

    func calendarApplicationSummary(
        for destinations: CalendarEventDestinations
    ) -> String? {
        var actions: [String] = []
        if let identifier = destinations.detailedCalendarIdentifier {
            let title = calendarDescriptors.first(where: { $0.id == identifier })
                .map(displayCalendarTitle)
                ?? "the unavailable selected calendar"
            actions.append("add Workout with readiness and confidence details to \(title)")
        }
        if !destinations.busyCalendarIdentifiers.isEmpty {
            let titles = destinations.busyCalendarIdentifiers.map { identifier in
                calendarDescriptors.first(where: { $0.id == identifier })
                    .map(displayCalendarTitle)
                    ?? "an unavailable calendar"
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            actions.append("block \(Self.joinedCalendarTitles(titles)) as Busy")
        }
        guard !actions.isEmpty else { return nil }
        return actions.joined(separator: " and ")
    }

    var unavailableBusyCalendarIdentifiers: Set<String> {
        let availableIdentifiers = Set(calendarDescriptors.filter(\.allowsContentModifications).map(\.id))
        return calendarPreferences.busyCalendarIdentifiers.subtracting(availableIdentifiers)
    }

    var unavailablePlanningCalendarIdentifiers: Set<String> {
        guard let selected = calendarPreferences.planningCalendarIdentifiers else { return [] }
        return selected.subtracting(calendarDescriptors.map(\.id))
    }

    var calendarDestinationConfigurationWarning: String? {
        var problems: [String] = []
        if selectedDetailedCalendarIsUnavailable {
            problems.append("the Workout details destination")
        }
        if !unavailableBusyCalendarIdentifiers.isEmpty {
            problems.append(
                unavailableBusyCalendarIdentifiers.count == 1
                    ? "one Busy destination"
                    : "\(unavailableBusyCalendarIdentifiers.count) Busy destinations"
            )
        }
        guard !problems.isEmpty else { return nil }
        return "Calendar Setup needs attention for \(Self.joinedCalendarTitles(problems)). Unavailable or read-only destinations won’t receive events."
    }

    var calendarReapplyBlockingReason: String? {
        reapplyBlockingReason(
            for: planApplicationRequest(),
            previouslyAppliedPlan: appliedPlanStatus
        )
    }

    private func reapplyBlockingReason(
        for request: PlanApplicationRequest,
        previouslyAppliedPlan: AppliedPlanStatus?
    ) -> String? {
        guard let previouslyAppliedPlan,
              previouslyAppliedPlan.calendarEventApplied else { return nil }
        let destinations = request.calendarDestinations
            ?? CalendarEventDestinations(
                detailedCalendarIdentifier: nil,
                busyCalendarIdentifiers: []
            )
        let hasTrackedDetailedEvent = previouslyAppliedPlan.calendarEventReceipts
            .contains { $0.role == .detailed }
            || previouslyAppliedPlan.calendarEventReceipts.isEmpty
        let writableIdentifiers = Set(
            calendarDescriptors.filter(\.allowsContentModifications).map(\.id)
        )
        let hasWritableDetailedReplacement = destinations.detailedCalendarIdentifier
            .map(writableIdentifiers.contains) == true
        if hasTrackedDetailedEvent && !hasWritableDetailedReplacement {
            return "Undo the applied plan before removing its Workout details event, or restore a writable Workout details destination."
        }
        if !request.includesCalendarEvent {
            return "Undo the applied plan before switching to an alarm-only plan, or restore a writable Calendar destination."
        }
        return nil
    }

    func isCalendarIncludedInPlanning(_ identifier: String) -> Bool {
        calendarPreferences.includesInPlanning(identifier)
    }

    func setCalendar(_ identifier: String, includedInPlanning isIncluded: Bool) {
        var updated = calendarPreferences
        var selected = updated.planningCalendarIdentifiers ?? Set(calendarDescriptors.map(\.id))
        if isIncluded { selected.insert(identifier) }
        else { selected.remove(identifier) }
        let allVisibleIdentifiers = Set(calendarDescriptors.map(\.id))
        updated.planningCalendarIdentifiers = selected == allVisibleIdentifiers ? nil : selected
        calendarPreferences = updated
    }

    func useAllCalendarsForPlanning() {
        var updated = calendarPreferences
        updated.planningCalendarIdentifiers = nil
        calendarPreferences = updated
    }

    func selectDetailedCalendar(_ identifier: String) {
        guard let descriptor = calendarDescriptors.first(where: { $0.id == identifier }),
              descriptor.allowsContentModifications else { return }
        var updated = calendarPreferences
        updated.detailedCalendarIdentifier = identifier
        updated.hasInitializedDetailedCalendar = true
        updated.busyCalendarIdentifiers.remove(identifier)
        calendarPreferences = updated
    }

    func isBusyCalendar(_ identifier: String) -> Bool {
        calendarPreferences.busyCalendarIdentifiers.contains(identifier)
    }

    func setCalendar(_ identifier: String, sharesBusy isSelected: Bool) {
        var updated = calendarPreferences
        if isSelected {
            guard identifier != updated.detailedCalendarIdentifier,
                  let descriptor = calendarDescriptors.first(where: { $0.id == identifier }),
                  descriptor.allowsContentModifications else { return }
            updated.busyCalendarIdentifiers.insert(identifier)
        } else {
            updated.busyCalendarIdentifiers.remove(identifier)
        }
        calendarPreferences = updated
    }

    private func refreshCalendarConfiguration() {
        guard calendarStatus == "Connected" else {
            calendarSources = []
            calendarConfigurationFailure = nil
            return
        }
        do {
            let sources = try calendar.availableCalendarSources()
            calendarSources = sources
            calendarConfigurationFailure = nil
            var updated = calendarPreferences
            let initializedDestination = updated.initializeDetailedDestinationIfNeeded(from: sources)
            let removedOverlap = updated.normalizeDestinationOverlap()
            if initializedDestination || removedOverlap {
                calendarPreferences = updated
            }
        } catch {
            calendarSources = []
            calendarConfigurationFailure = error.localizedDescription
        }
    }

    private func handleCalendarStoreChange() async {
        calendarStatus = calendar.authorizationLabel
        refreshCalendarConfiguration()
        await refresh(
            retryingBackgroundDeliveryIfNeeded: true,
            surfacingHealthFailureAsNotice: false
        )
    }

    private static func joinedCalendarTitles(_ titles: [String]) -> String {
        guard let last = titles.last else { return "" }
        if titles.count == 1 { return last }
        if titles.count == 2 { return "\(titles[0]) and \(last)" }
        return "\(titles.dropLast().joined(separator: ", ")), and \(last)"
    }

    private func displayCalendarTitle(_ descriptor: CalendarDescriptor) -> String {
        let hasDuplicateTitle = calendarDescriptors.contains {
            $0.id != descriptor.id
                && $0.title.localizedCaseInsensitiveCompare(descriptor.title) == .orderedSame
        }
        guard hasDuplicateTitle else { return descriptor.title }
        return "\(descriptor.title) (\(descriptor.sourceTitle))"
    }

    private static func calendarSelectionSummary(
        titles: [String],
        unavailableCount: Int,
        empty: String
    ) -> String {
        let sortedTitles = titles.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        var parts: [String] = []
        if sortedTitles.count <= 2 {
            parts.append(contentsOf: sortedTitles)
        } else {
            parts.append("\(sortedTitles.count) calendars selected")
        }
        if unavailableCount > 0 {
            parts.append(
                unavailableCount == 1
                    ? "1 unavailable selection"
                    : "\(unavailableCount) unavailable selections"
            )
        }
        return parts.isEmpty ? empty : joinedCalendarTitles(parts)
    }

    func refresh() async {
        await refresh(
            retryingBackgroundDeliveryIfNeeded: true,
            surfacingHealthFailureAsNotice: true
        )
    }

    private func refresh(
        retryingBackgroundDeliveryIfNeeded: Bool,
        surfacingHealthFailureAsNotice: Bool
    ) async {
        if isRefreshing {
            refreshQueued = true
            refreshQueuedBackgroundDeliveryRetry = refreshQueuedBackgroundDeliveryRetry
                || retryingBackgroundDeliveryIfNeeded
            refreshQueuedHealthFailureNotice = refreshQueuedHealthFailureNotice
                || surfacingHealthFailureAsNotice
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
        var shouldSurfaceHealthFailure = surfacingHealthFailureAsNotice
        repeat {
            refreshQueued = false
            shouldRetryBackgroundDelivery = shouldRetryBackgroundDelivery
                || refreshQueuedBackgroundDeliveryRetry
            shouldSurfaceHealthFailure = shouldSurfaceHealthFailure
                || refreshQueuedHealthFailureNotice
            refreshQueuedBackgroundDeliveryRetry = false
            refreshQueuedHealthFailureNotice = false

            if shouldRetryBackgroundDelivery,
               healthBackgroundDeliveryFailure != nil,
               (demoMode || healthAuthorizationRequested) {
                await observeHealthUpdates()
            }

            shouldRetryBackgroundDelivery = false
            await performRefresh(
                surfacingHealthFailureAsNotice: shouldSurfaceHealthFailure
            )
            shouldSurfaceHealthFailure = false
        } while refreshQueued
    }

    private func performRefresh(
        surfacingHealthFailureAsNotice: Bool
    ) async {
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
                if surfacingHealthFailureAsNotice {
                    notice = error.localizedDescription
                }
            }
        } else {
            diagnostics = []
            snapshot = wellness.snapshot(from: [], preferences: preferences, now: .now)
            healthQueryFailures = []
            healthConnectionState = .notRequested
        }

        refreshCalendarConfiguration()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let commitment: CalendarCommitment?
        do {
            commitment = try await calendar.firstCommitment(
                on: tomorrow,
                calendarIdentifiers: calendarPreferences.planningCalendarIdentifiers
            )
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
        await refreshHealthAccessReviewStatus()
        if demoMode || healthAuthorizationRequested {
            await observeHealthUpdates()
        }
        await refresh(
            retryingBackgroundDeliveryIfNeeded: false,
            surfacingHealthFailureAsNotice: false
        )
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
            await refresh(
                retryingBackgroundDeliveryIfNeeded: false,
                surfacingHealthFailureAsNotice: false
            )

        case .observerFailed(_, let typeIdentifier, let message):
            let failure = HealthDataError.backgroundDeliveryConfigurationFailed(
                typeIdentifier: typeIdentifier,
                message: message
            ).localizedDescription
            healthBackgroundDeliveryFailure = failure
            // Do not recursively re-register from inside an observer callback.
            // A persistent HealthKit error could otherwise create a launch/retry
            // storm. Foreground and explicit refresh paths make one bounded retry.
            // Observer failures are passive status, not modal errors: a background
            // wake must never interrupt the user with RootView's generic alert.
        }
    }

    func recomputePlan() {
        plan = wellness.plan(snapshot: snapshot, commitment: latestCommitment, preferences: preferences, now: .now)
    }

    func refreshConnectionStatuses() {
        guard !demoMode else { return }
        calendarStatus = calendar.authorizationLabel
        refreshCalendarConfiguration()
        alarmStatus = alarms.authorizationLabel
    }

    func refreshForForeground() async {
        refreshConnectionStatuses()
        await refreshHealthAccessReviewStatus()
        await refresh(
            retryingBackgroundDeliveryIfNeeded: true,
            surfacingHealthFailureAsNotice: false
        )
    }

    func planApplicationRequest() -> PlanApplicationRequest {
        let destinations = writableCalendarEventDestinations
        return PlanApplicationRequest(
            wakeTime: plan.wakeTime,
            gymStart: plan.gymStart,
            gymEnd: plan.gymEnd,
            workoutTitle: plan.workoutAdjustment.title,
            readinessScore: snapshot.readinessScore,
            confidence: snapshot.confidence,
            includesCalendarEvent: calendarStatus == "Connected"
                && destinations.requestedCount > 0,
            calendarDestinations: destinations
        )
    }

    func applyPlan(_ requestedPlan: PlanApplicationRequest? = nil) async {
        guard !isApplying else { return }
        let requestedPlan = requestedPlan ?? planApplicationRequest()
        let requestedCalendarDestinations = requestedPlan.calendarDestinations
            ?? (requestedPlan.includesCalendarEvent
                ? calendarEventDestinations
                : CalendarEventDestinations(
                    detailedCalendarIdentifier: nil,
                    busyCalendarIdentifiers: []
                ))
        let requestedCalendarEventCount = requestedPlan.includesCalendarEvent
            ? max(requestedCalendarDestinations.requestedCount, 1)
            : 0
        let previouslyAppliedPlan = appliedPlanStatus
        let previousVerificationMessage = appliedPlanVerificationMessage
        if let blockingReason = reapplyBlockingReason(
            for: PlanApplicationRequest(
                wakeTime: requestedPlan.wakeTime,
                gymStart: requestedPlan.gymStart,
                gymEnd: requestedPlan.gymEnd,
                workoutTitle: requestedPlan.workoutTitle,
                readinessScore: requestedPlan.readinessScore,
                confidence: requestedPlan.confidence,
                includesCalendarEvent: requestedPlan.includesCalendarEvent,
                calendarDestinations: requestedCalendarDestinations
            ),
            previouslyAppliedPlan: previouslyAppliedPlan
        ) {
            notice = blockingReason
            return
        }
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
                || previouslyAppliedPlan?.calendarEventApplied == true,
            calendarEventReceipts: previouslyAppliedPlan?.calendarEventReceipts ?? [],
            calendarEventRequestedCount: max(
                requestedCalendarEventCount,
                previouslyAppliedPlan?.requestedCalendarEventCount ?? 0
            ),
            calendarEventDestinations: requestedPlan.includesCalendarEvent
                ? requestedCalendarDestinations
                : previouslyAppliedPlan?.calendarEventDestinations,
            calendarEventIssues: (requestedPlan.includesCalendarEvent
                || previouslyAppliedPlan?.calendarEventApplied == true)
                ? ["Calendar application may have been interrupted. Use Undo before applying again."]
                : []
        )
        appliedPlanStatus = journal
        appliedPlanVerificationMessage = "Plan application is in progress. If it was interrupted, use Undo before applying again."
        guard saveAppliedPlanStatus() else {
            appliedPlanStatus = previouslyAppliedPlan
            appliedPlanVerificationMessage = previousVerificationMessage
            notice = "Dayvera couldn’t securely save the plan before applying it. No system changes were requested."
            return
        }

        var successes: [String] = []
        var failures: [String] = []
        var replacementWarnings: [String] = []
        var wakeAlarmMayNeedCleanup = previouslyAppliedPlan?.wakeAlarmApplied == true
        var alarmFailureMayHaveTrackedAlarm = false
        var calendarReceipts = previouslyAppliedPlan?.calendarEventReceipts ?? []
        var calendarWriteSucceeded = false
        var calendarRequestedCountForStatus = max(
            requestedCalendarEventCount,
            previouslyAppliedPlan?.requestedCalendarEventCount ?? 0
        )
        var calendarDestinationsForStatus = requestedPlan.includesCalendarEvent
            ? requestedCalendarDestinations
            : previouslyAppliedPlan?.calendarEventDestinations
        var calendarIssuesForStatus = previouslyAppliedPlan?.calendarEventIssues ?? []

        if requestedPlan.includesCalendarEvent {
            do {
                let result = try await calendar.createGymEvents(CalendarEventWriteRequest(
                    start: requestedPlan.gymStart,
                    end: requestedPlan.gymEnd,
                    detailedTitle: "Gym · \(requestedPlan.workoutTitle)",
                    detailedNotes: [
                        "Workout: \(requestedPlan.workoutTitle)",
                        "Readiness: \(requestedPlan.readinessScore)/100",
                        "Data confidence: \(requestedPlan.confidence.title)",
                        "Created by Dayvera."
                    ].joined(separator: "\n"),
                    destinations: requestedCalendarDestinations
                ))
                calendarReceipts = result.activeReceipts
                calendarWriteSucceeded = !result.writtenReceipts.isEmpty
                calendarRequestedCountForStatus = requestedCalendarEventCount
                calendarDestinationsForStatus = requestedCalendarDestinations
                calendarIssuesForStatus = result.failures.map {
                    "Calendar: \($0.localizedSummary)"
                }
                if calendarWriteSucceeded {
                    let writtenCount = result.writtenReceipts.count
                    successes.append(
                        requestedCalendarEventCount > 1
                            ? "\(writtenCount) of \(requestedCalendarEventCount) calendar events"
                            : (result.writtenReceipts.first?.role == .busy
                                ? "Busy event"
                                : "gym event")
                    )
                }
                failures.append(contentsOf: result.failures.map {
                    "Calendar: \($0.localizedSummary)"
                })
                if !result.failures.isEmpty,
                   previouslyAppliedPlan?.calendarEventApplied == true {
                    replacementWarnings.append(
                        "One or more previously applied calendar events may still be active because their replacement failed. Undo removes each event independently."
                    )
                }
                let selectedReceiptCount = result.activeReceipts.filter { receipt in
                    if receipt.role == .detailed {
                        return receipt.calendarIdentifier
                            == requestedCalendarDestinations.detailedCalendarIdentifier
                    }
                    return requestedCalendarDestinations.busyCalendarIdentifiers
                        .contains(receipt.calendarIdentifier)
                }.count
                if selectedReceiptCount < result.activeReceipts.count {
                    let warning = "A calendar event from the previous destination is still active. Use Undo to retry removing it."
                    replacementWarnings.append(warning)
                    calendarIssuesForStatus.append(warning)
                }
            } catch {
                failures.append("Calendar: \(error.localizedDescription)")
                calendarIssuesForStatus.append(
                    "Calendar replacement failed: \(error.localizedDescription)"
                )
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
                    "Dayvera could not verify every app-owned wake alarm. Use Undo before applying again."
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
                        || previouslyAppliedPlan.expectsCalendarEvent,
                    calendarEventReceipts: previouslyAppliedPlan.calendarEventReceipts,
                    calendarEventRequestedCount: max(
                        requestedCalendarEventCount,
                        previouslyAppliedPlan.requestedCalendarEventCount
                    ),
                    calendarEventDestinations: previouslyAppliedPlan.calendarEventDestinations,
                    calendarEventIssues: previouslyAppliedPlan.calendarEventIssues
                )
            } else {
                status = previouslyAppliedPlan
            }
        } else if successes.isEmpty {
            status = journal
            replacementWarnings.append(
                "Dayvera could not confirm whether a system item was created. Use Undo before applying again."
            )
        } else {
            status = AppliedPlanStatus(
                wakeTime: requestedPlan.wakeTime,
                gymStart: requestedPlan.gymStart,
                gymEnd: requestedPlan.gymEnd,
                wakeAlarmApplied: successes.contains("wake alarm")
                    || wakeAlarmMayNeedCleanup,
                calendarEventApplied: calendarWriteSucceeded
                    || previouslyAppliedPlan?.calendarEventApplied == true,
                calendarEventRequested: requestedPlan.includesCalendarEvent
                    || previouslyAppliedPlan?.calendarEventApplied == true,
                calendarEventReceipts: calendarReceipts,
                calendarEventRequestedCount: calendarRequestedCountForStatus,
                calendarEventDestinations: calendarDestinationsForStatus,
                calendarEventIssues: calendarIssuesForStatus
            )
        }
        if status.wakeAlarmApplied || status.calendarEventApplied {
            appliedPlanStatus = status
            let reviewMessages = Array(Set(replacementWarnings + status.calendarEventIssues))
                .sorted()
            appliedPlanVerificationMessage = reviewMessages.isEmpty
                ? nil
                : reviewMessages.joined(separator: " ")
            if !saveAppliedPlanStatus() {
                appliedPlanVerificationMessage = "The system items may be active, but Dayvera couldn’t securely update their local status. Use Undo before applying again."
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
        var remainingCalendarReceipts = status.calendarEventReceipts
        // Both services scope cancellation to their persisted app-owned identifier,
        // so attempting both also cleans up an item whose external state drifted.
        do {
            let result = try calendar.cancelGymEvents(
                receipts: status.calendarEventReceipts,
                start: status.gymStart,
                end: status.gymEnd
            )
            remainingCalendarReceipts = result.remainingReceipts
            calendarEventRemaining = !result.remainingReceipts.isEmpty
            failures.append(contentsOf: result.failures.map {
                "Calendar: \($0.localizedSummary)"
            })
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
                notice = nil
            } else {
                appliedPlanVerificationMessage = "The system items were removed, but Dayvera couldn’t clear their local status. Try Undo again."
                notice = "The plan was removed from Calendar and Clock, but its local status could not be cleared."
            }
        } else {
            appliedPlanStatus = AppliedPlanStatus(
                wakeTime: status.wakeTime,
                gymStart: status.gymStart,
                gymEnd: status.gymEnd,
                wakeAlarmApplied: wakeAlarmRemaining,
                calendarEventApplied: calendarEventRemaining,
                calendarEventRequested: status.calendarEventRequested,
                calendarEventReceipts: remainingCalendarReceipts,
                calendarEventRequestedCount: status.calendarEventRequestedCount,
                calendarEventDestinations: status.calendarEventDestinations,
                calendarEventIssues: failures.isEmpty
                    ? status.calendarEventIssues
                    : failures
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
                notice = "Workout saved in Dayvera, but it couldn’t be added to Apple Health. Retry from Training History when you’re ready."
            } catch {
                restoreWorkoutExportSnapshot(previous, to: session)
                notice = "Workout saved in Dayvera, but it couldn’t be added to Apple Health or update its export status. Retry from Training History."
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
                notice = "Dayvera couldn’t securely save your preferences. Keep the app open and try again after unlocking your iPhone."
            }
        }
    }

    private func saveTrainingProfile() {
        guard let data = try? JSONEncoder().encode(trainingProfile) else { return }
        if privateStateStore.set(data, forKey: Self.trainingProfileKey) {
            if privateStateStore.removesLegacyDefaultsAfterSave {
                defaults.removeObject(forKey: Self.trainingProfileKey)
            }
        } else {
            notice = "Dayvera couldn’t securely save your training preferences. Keep the app open and try again after unlocking your iPhone."
        }
    }

    private func saveCalendarPreferences() {
        guard let data = try? JSONEncoder().encode(calendarPreferences) else { return }
        if privateStateStore.set(data, forKey: Self.calendarPreferencesKey) {
            if privateStateStore.removesLegacyDefaultsAfterSave {
                defaults.removeObject(forKey: Self.calendarPreferencesKey)
            }
        } else {
            notice = "Dayvera couldn’t securely save your calendar choices. Keep the app open and try again after unlocking your iPhone."
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
    private func saveHealthAuthorizationSchemaVersion() -> Bool {
        if !privateStateStore.removesLegacyDefaultsAfterSave {
            defaults.set(
                healthAuthorizationSchemaVersion,
                forKey: Self.healthAuthorizationSchemaVersionKey
            )
            return true
        }
        guard let data = try? JSONEncoder().encode(healthAuthorizationSchemaVersion) else {
            return false
        }
        let saved = privateStateStore.set(
            data,
            forKey: Self.healthAuthorizationSchemaVersionKey
        )
        if saved { defaults.removeObject(forKey: Self.healthAuthorizationSchemaVersionKey) }
        return saved
    }

    private func refreshHealthAccessReviewStatus() async {
        guard !demoMode, healthAuthorizationRequested else {
            healthAccessReviewRecommended = false
            return
        }
        let schemaNeedsReview = healthAuthorizationSchemaVersion
            < health.authorizationRequestSchema.version
        do {
            let status = try await health.authorizationRequestStatus()
            healthAccessReviewRecommended = schemaNeedsReview || status == .shouldRequest
        } catch {
            // Request-status failure cannot reveal read access. Preserve only
            // the locally provable schema comparison and keep normal refreshes working.
            healthAccessReviewRecommended = schemaNeedsReview
        }
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
        var messages: [String] = current.calendarEventIssues
        var reconciledStatus = current

        if current.wakeAlarmApplied {
            do {
                if try !alarms.hasWakeAlarm(scheduledAt: current.wakeTime) {
                    messages.append("The saved wake alarm doesn’t match this plan. It may have fired, been edited, or been removed.")
                }
            } catch {
                messages.append("Dayvera couldn’t verify the saved wake alarm: \(error.localizedDescription)")
            }
        }

        if current.calendarEventApplied {
            do {
                let result = try calendar.verifyGymEvents(
                    receipts: current.calendarEventReceipts,
                    start: current.gymStart,
                    end: current.gymEnd
                )
                let returnedReceipts = result.verifiedReceipts + result.missingReceipts
                let returnedReceiptIDs = Set(returnedReceipts.map(\.id))
                let unresolvedReceipts = current.calendarEventReceipts.filter { receipt in
                    guard !returnedReceiptIDs.contains(receipt.id) else { return false }
                    return result.failures.contains { failure in
                        failure.calendarIdentifier.isEmpty
                            || (failure.calendarIdentifier == receipt.calendarIdentifier
                                && failure.role == receipt.role)
                    }
                }
                let recoveredReceipts = Array(Set(
                    returnedReceipts + unresolvedReceipts
                )).sorted { $0.id < $1.id }
                let recoveredDestinations = current.calendarEventDestinations
                    ?? Self.destinations(from: recoveredReceipts)
                if !recoveredReceipts.isEmpty,
                   recoveredReceipts != current.calendarEventReceipts
                    || recoveredDestinations != current.calendarEventDestinations {
                    reconciledStatus = AppliedPlanStatus(
                        wakeTime: current.wakeTime,
                        gymStart: current.gymStart,
                        gymEnd: current.gymEnd,
                        wakeAlarmApplied: current.wakeAlarmApplied,
                        calendarEventApplied: current.calendarEventApplied,
                        calendarEventRequested: current.calendarEventRequested,
                        calendarEventReceipts: recoveredReceipts,
                        calendarEventRequestedCount: current.calendarEventRequestedCount,
                        calendarEventDestinations: recoveredDestinations,
                        calendarEventIssues: current.calendarEventIssues
                    )
                    appliedPlanStatus = reconciledStatus
                    _ = saveAppliedPlanStatus()
                }
                messages.append(contentsOf: result.missingReceipts.map {
                    let itemTitle = $0.role == .detailed ? "gym event" : "Busy event"
                    return "The saved \(itemTitle) doesn’t match this plan in \($0.calendarTitle). It may have been edited or removed."
                })
                messages.append(contentsOf: result.failures.map {
                    "Dayvera couldn’t verify \($0.role.displayTitle.lowercased()) in \($0.calendarTitle): \($0.message)"
                })
            } catch {
                messages.append("Dayvera couldn’t verify the saved gym event: \(error.localizedDescription)")
            }
        }

        if reconciledStatus.hasObsoleteCalendarReceipts {
            messages.append(
                "A calendar event remains in a previous destination. Use Undo to retry removing it before applying again."
            )
        }

        // A failed verification can also mean the item was edited or has already
        // fired. Preserve the app-owned identifiers and last-known applied state so
        // Undo can still clean up any surviving external item.
        appliedPlanVerificationMessage = messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    private static func destinations(
        from receipts: [CalendarEventReceipt]
    ) -> CalendarEventDestinations? {
        guard !receipts.isEmpty else { return nil }
        return CalendarEventDestinations(
            detailedCalendarIdentifier: receipts.first(where: { $0.role == .detailed })?
                .calendarIdentifier,
            busyCalendarIdentifiers: Set(
                receipts.filter { $0.role == .busy }.map(\.calendarIdentifier)
            )
        )
    }

    private func observeHealthUpdates(
        surfacingFailureAsNotice: Bool = false
    ) async {
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
            if surfacingFailureAsNotice {
                notice = message
            }
        }
    }
}
