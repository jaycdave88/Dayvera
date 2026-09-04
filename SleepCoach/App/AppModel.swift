import EventKit
import Foundation
import HealthKit

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
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: DailyHealthSnapshot = .empty
    @Published private(set) var plan: DailyPlan = .placeholder()
    @Published private(set) var diagnostics: [SourceDiagnostic] = []
    @Published private(set) var healthQueryFailures: [HealthQueryFailure] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var healthConnectionState: HealthConnectionState = .notRequested
    @Published private(set) var calendarStatus = "Not connected"
    @Published private(set) var alarmStatus = "Not connected"
    @Published private(set) var isApplying = false
    @Published private(set) var appliedPlanStatus: AppliedPlanStatus?
    @Published var notice: String?
    @Published var preferences: WellnessPreferences {
        didSet {
            savePreferences()
            snapshot = wellness.snapshot(from: snapshot.samples, preferences: preferences, now: .now)
            plan = wellness.plan(snapshot: snapshot, commitment: latestCommitment, preferences: preferences, now: .now)
        }
    }

    var healthStatus: String { healthConnectionState.label }

    private let health: HealthDataProviding
    private let calendar: CalendarProviding
    private let alarms: AlarmScheduling
    private let wellness: WellnessEvaluating
    private let defaults: UserDefaults
    private let demoMode: Bool
    private var latestCommitment: CalendarCommitment?
    private let appliedPlanStatusKey = "appliedPlanStatus"

    init(
        health: HealthDataProviding = HealthKitService(),
        calendar: CalendarProviding = CalendarService(),
        alarms: AlarmScheduling = AlarmService(),
        wellness: WellnessEvaluating = WellnessEngine(),
        defaults: UserDefaults = .standard,
        demoMode: Bool = false
    ) {
        self.health = health
        self.calendar = calendar
        self.alarms = alarms
        self.wellness = wellness
        self.defaults = defaults
        self.demoMode = demoMode
        if let data = defaults.data(forKey: "wellnessPreferences"),
           let saved = try? JSONDecoder().decode(WellnessPreferences.self, from: data) {
            self.preferences = saved
        } else {
            self.preferences = .default
        }
        self.healthConnectionState = demoMode
            ? .demoData
            : (defaults.bool(forKey: "healthAuthorizationRequested") ? .accessRequested : .notRequested)
        self.calendarStatus = demoMode
            ? "Connected"
            : (EKEventStore.authorizationStatus(for: .event) == .fullAccess ? "Connected" : "Not connected")
        self.alarmStatus = alarms.authorizationLabel
        if let data = defaults.data(forKey: appliedPlanStatusKey) {
            self.appliedPlanStatus = try? JSONDecoder().decode(AppliedPlanStatus.self, from: data)
        }
    }

    func connectHealth() async {
        do {
            try await health.requestAuthorization()
            defaults.set(true, forKey: "healthAuthorizationRequested")
            healthConnectionState = .accessRequested
            await observeHealthUpdates()
            await refresh()
        } catch {
            healthConnectionState = defaults.bool(forKey: "healthAuthorizationRequested")
                ? .accessRequested
                : .notRequested
            notice = error.localizedDescription
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
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if demoMode || defaults.bool(forKey: "healthAuthorizationRequested") {
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
        let commitment = try? await calendar.firstCommitment(on: tomorrow)
        latestCommitment = commitment
        plan = wellness.plan(snapshot: snapshot, commitment: commitment, preferences: preferences, now: .now)
        alarmStatus = alarms.authorizationLabel
    }

    func start() async {
        if demoMode || defaults.bool(forKey: "healthAuthorizationRequested") {
            await observeHealthUpdates()
        }
        await refresh()
    }

    func recomputePlan() {
        plan = wellness.plan(snapshot: snapshot, commitment: latestCommitment, preferences: preferences, now: .now)
    }

    func refreshConnectionStatuses() {
        guard !demoMode else { return }
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess {
            calendarStatus = "Connected"
        } else if status == .denied || status == .restricted {
            calendarStatus = "Denied"
        } else {
            calendarStatus = "Not connected"
        }
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
        guard requestedPlan.wakeTime > .now else {
            notice = "This wake time has passed. Refresh the plan before applying it."
            return
        }
        isApplying = true
        defer { isApplying = false }

        var successes: [String] = []
        var failures: [String] = []

        if requestedPlan.includesCalendarEvent {
            do {
                try await calendar.createGymEvent(
                    start: requestedPlan.gymStart,
                    end: requestedPlan.gymEnd,
                    note: "\(requestedPlan.workoutTitle). Readiness \(requestedPlan.readinessScore)/100 (\(requestedPlan.confidence.title.lowercased()) confidence)."
                )
                successes.append("gym event")
            } catch {
                failures.append("Calendar: \(error.localizedDescription)")
            }
        }

        do {
            try await alarms.scheduleWakeAlarm(at: requestedPlan.wakeTime)
            successes.append("wake alarm")
        } catch {
            failures.append("Alarm: \(error.localizedDescription)")
        }

        alarmStatus = alarms.authorizationLabel
        let status = AppliedPlanStatus(
            wakeTime: requestedPlan.wakeTime,
            gymStart: requestedPlan.gymStart,
            gymEnd: requestedPlan.gymEnd,
            wakeAlarmApplied: successes.contains("wake alarm"),
            calendarEventApplied: successes.contains("gym event")
        )
        if status.wakeAlarmApplied || status.calendarEventApplied {
            appliedPlanStatus = status
            saveAppliedPlanStatus()
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
        guard let status = appliedPlanStatus else { return }
        var failures: [String] = []
        if status.calendarEventApplied {
            do { try calendar.cancelGymEvent() }
            catch { failures.append("Calendar: \(error.localizedDescription)") }
        }
        if status.wakeAlarmApplied {
            do { try alarms.cancelWakeAlarm() }
            catch { failures.append("Alarm: \(error.localizedDescription)") }
        }
        if failures.isEmpty {
            appliedPlanStatus = nil
            defaults.removeObject(forKey: appliedPlanStatusKey)
            alarmStatus = alarms.authorizationLabel
        } else {
            notice = "Couldn’t undo the full plan. \(failures.joined(separator: " "))"
        }
    }

    func recordStrengthWorkout(start: Date, end: Date) async {
        do {
            try await health.saveStrengthWorkout(start: start, end: end)
        } catch {
            notice = "Workout saved locally, but Apple Health export failed: \(error.localizedDescription)"
        }
    }

    private func savePreferences() {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: "wellnessPreferences")
        }
    }

    private func saveAppliedPlanStatus() {
        guard let appliedPlanStatus,
              let data = try? JSONEncoder().encode(appliedPlanStatus) else { return }
        defaults.set(data, forKey: appliedPlanStatusKey)
    }

    private func observeHealthUpdates() async {
        await health.configureBackgroundDelivery { [weak self] in
            await self?.refresh()
        }
    }
}
