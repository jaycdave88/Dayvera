import Foundation

enum MetricKind: String, Codable, CaseIterable, Hashable, Sendable {
    case sleep
    case heartRateVariability
    case restingHeartRate
    case heartRate
    case respiratoryRate
    case oxygenSaturation
    case sleepingWristTemperature
    case bodyTemperature
    case bodyMass
    case bodyFatPercentage
    case leanBodyMass
    case bodyMassIndex
    case activeEnergy
    case steps
    case exerciseMinutes
    case workout

    static let decisionMetrics: [MetricKind] = [
        .sleep,
        .heartRateVariability,
        .restingHeartRate
    ]

    /// These signals can only make a recommendation more conservative. They are
    /// deliberately kept out of the core readiness score.
    static let safetyMetrics: [MetricKind] = [
        .respiratoryRate,
        .oxygenSaturation,
        .sleepingWristTemperature,
        .bodyTemperature,
        .heartRate
    ]

    static let trainingContextMetrics: [MetricKind] = [
        .workout,
        .activeEnergy,
        .exerciseMinutes,
        .steps
    ]

    /// Standard Apple Health body-measurement types that apps such as Hume may
    /// export. These are presented as provenance-aware progress context only;
    /// they do not change readiness, safety gates, or today's workout.
    static let bodyCompositionMetrics: [MetricKind] = [
        .bodyMass,
        .bodyFatPercentage,
        .leanBodyMass,
        .bodyMassIndex
    ]

    static let healthReadMetrics: [MetricKind] =
        decisionMetrics + safetyMetrics + trainingContextMetrics + bodyCompositionMetrics

    var title: String {
        switch self {
        case .sleep: "Sleep"
        case .heartRateVariability: "HRV"
        case .restingHeartRate: "Resting heart rate"
        case .heartRate: "Heart rate"
        case .respiratoryRate: "Respiratory rate"
        case .oxygenSaturation: "Blood oxygen"
        case .sleepingWristTemperature: "Wrist temperature"
        case .bodyTemperature: "Body temperature"
        case .bodyMass: "Body weight"
        case .bodyFatPercentage: "Body fat"
        case .leanBodyMass: "Lean body mass"
        case .bodyMassIndex: "Body mass index"
        case .activeEnergy: "Active energy"
        case .steps: "Steps"
        case .exerciseMinutes: "Exercise minutes"
        case .workout: "Workouts"
        }
    }

    var unit: String {
        switch self {
        case .sleep, .exerciseMinutes, .workout: "min"
        case .heartRateVariability: "ms"
        case .restingHeartRate, .heartRate: "bpm"
        case .respiratoryRate: "br/min"
        case .oxygenSaturation: "%"
        case .sleepingWristTemperature, .bodyTemperature: "°C"
        case .bodyMass, .leanBodyMass: "kg"
        case .bodyFatPercentage: "%"
        case .bodyMassIndex: ""
        case .activeEnergy: "kcal"
        case .steps: "steps"
        }
    }
}

/// HealthKit body-mass values are normalized to kilograms at ingestion. Keep
/// that storage contract stable, and convert only at presentation boundaries.
func bodyCompositionDisplayValue(
    value: Double,
    kind: MetricKind,
    loadUnit: LoadUnit
) -> String {
    let displayedValue: Double
    let suffix: String
    switch kind {
    case .bodyMass, .leanBodyMass:
        displayedValue = LoadUnit.kilograms.convert(value, to: loadUnit)
        suffix = " \(loadUnit.symbol)"
    case .bodyFatPercentage:
        displayedValue = value
        suffix = "%"
    case .bodyMassIndex:
        displayedValue = value
        suffix = ""
    default:
        displayedValue = value
        suffix = kind.unit.isEmpty ? "" : " \(kind.unit)"
    }
    return displayedValue.formatted(
        .number.precision(.fractionLength(0...1))
    ) + suffix
}

func bodyCompositionDeltaDisplayValue(
    value: Double,
    kind: MetricKind,
    loadUnit: LoadUnit
) -> String {
    let displayedValue: Double
    let suffix: String
    switch kind {
    case .bodyMass, .leanBodyMass:
        displayedValue = LoadUnit.kilograms.convert(value, to: loadUnit)
        suffix = " \(loadUnit.symbol)"
    case .bodyFatPercentage:
        displayedValue = value
        suffix = " pp"
    case .bodyMassIndex:
        displayedValue = value
        suffix = ""
    default:
        displayedValue = value
        suffix = kind.unit.isEmpty ? "" : " \(kind.unit)"
    }
    let sign = displayedValue > 0 ? "+" : (displayedValue < 0 ? "−" : "")
    let magnitude = abs(displayedValue).formatted(
        .number.precision(.fractionLength(0...1))
    )
    return sign + magnitude + suffix
}

struct HealthDeviceProvenance: Codable, Hashable, Sendable {
    let manufacturer: String?
    let model: String?

    init(
        manufacturer: String? = nil,
        model: String? = nil
    ) {
        self.manufacturer = manufacturer
        self.model = model
    }

    var displayName: String {
        model ?? manufacturer ?? "Unspecified device"
    }

    var detailText: String? {
        let details = [manufacturer]
            .compactMap { value -> String? in
                guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty,
                      value != model else { return nil }
                return value
            }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }
}

enum SleepStage: String, Codable, Sendable {
    case inBed
    case awake
    case asleep
    case core
    case deep
    case rem
    case unknown

    var countsAsSleep: Bool {
        switch self {
        case .asleep, .core, .deep, .rem: true
        default: false
        }
    }
}

struct MetricSample: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let kind: MetricKind
    let startDate: Date
    let endDate: Date
    let value: Double?
    let sleepStage: SleepStage?
    let sourceName: String
    let sourceBundleIdentifier: String
    /// Non-identifying hardware family supplied by HealthKit's source revision,
    /// for example an Apple Watch product type. Bundle identifier alone can
    /// otherwise collapse samples written by a phone and watch into one source.
    let sourceProductType: String?
    let device: HealthDeviceProvenance?
    /// HealthKit's explicit provenance flag. User-entered values remain visible
    /// in source diagnostics but are not used for automatic health guidance.
    let wasUserEntered: Bool
    let workoutSyncIdentifier: String?
    let workoutSyncVersion: Int?

    init(
        id: UUID = UUID(),
        kind: MetricKind,
        startDate: Date,
        endDate: Date,
        value: Double? = nil,
        sleepStage: SleepStage? = nil,
        sourceName: String,
        sourceBundleIdentifier: String,
        sourceProductType: String? = nil,
        device: HealthDeviceProvenance? = nil,
        wasUserEntered: Bool = false,
        workoutSyncIdentifier: String? = nil,
        workoutSyncVersion: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
        self.sleepStage = sleepStage
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceProductType = sourceProductType
        self.device = device
        self.wasUserEntered = wasUserEntered
        self.workoutSyncIdentifier = workoutSyncIdentifier
        self.workoutSyncVersion = workoutSyncVersion
    }

    /// Stable, non-personal source identity used for same-source baselines.
    var sourceIdentity: String {
        "\(sourceBundleIdentifier)|\(sourceProductType ?? "unspecified-product")"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case startDate
        case endDate
        case value
        case sleepStage
        case sourceName
        case sourceBundleIdentifier
        case sourceProductType
        case device
        case wasUserEntered
        case workoutSyncIdentifier
        case workoutSyncVersion
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(MetricKind.self, forKey: .kind)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        value = try container.decodeIfPresent(Double.self, forKey: .value)
        sleepStage = try container.decodeIfPresent(SleepStage.self, forKey: .sleepStage)
        sourceName = try container.decode(String.self, forKey: .sourceName)
        sourceBundleIdentifier = try container.decode(String.self, forKey: .sourceBundleIdentifier)
        sourceProductType = try container.decodeIfPresent(String.self, forKey: .sourceProductType)
        device = try container.decodeIfPresent(HealthDeviceProvenance.self, forKey: .device)
        wasUserEntered = try container.decodeIfPresent(Bool.self, forKey: .wasUserEntered) ?? false
        workoutSyncIdentifier = try container.decodeIfPresent(String.self, forKey: .workoutSyncIdentifier)
        workoutSyncVersion = try container.decodeIfPresent(Int.self, forKey: .workoutSyncVersion)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(sleepStage, forKey: .sleepStage)
        try container.encode(sourceName, forKey: .sourceName)
        try container.encode(sourceBundleIdentifier, forKey: .sourceBundleIdentifier)
        try container.encodeIfPresent(sourceProductType, forKey: .sourceProductType)
        try container.encodeIfPresent(device, forKey: .device)
        try container.encode(wasUserEntered, forKey: .wasUserEntered)
        try container.encodeIfPresent(workoutSyncIdentifier, forKey: .workoutSyncIdentifier)
        try container.encodeIfPresent(workoutSyncVersion, forKey: .workoutSyncVersion)
    }
}

struct SourceDiagnostic: Identifiable, Hashable, Sendable {
    var id: String {
        "\(bundleIdentifier)|\(sourceProductType ?? "unspecified-product")|\(kind.rawValue)"
    }
    let sourceName: String
    let bundleIdentifier: String
    let sourceProductType: String?
    let kind: MetricKind
    let sampleCount: Int
    let userEnteredSampleCount: Int
    let latestSample: Date?
    let firstSample: Date?
    let observedDayCount: Int
    let devices: [HealthDeviceProvenance]

    init(
        sourceName: String,
        bundleIdentifier: String,
        sourceProductType: String? = nil,
        kind: MetricKind,
        sampleCount: Int,
        userEnteredSampleCount: Int = 0,
        latestSample: Date?,
        firstSample: Date? = nil,
        observedDayCount: Int = 0,
        devices: [HealthDeviceProvenance] = []
    ) {
        self.sourceName = sourceName
        self.bundleIdentifier = bundleIdentifier
        self.sourceProductType = sourceProductType
        self.kind = kind
        self.sampleCount = sampleCount
        self.userEnteredSampleCount = userEnteredSampleCount
        self.latestSample = latestSample
        self.firstSample = firstSample
        self.observedDayCount = observedDayCount
        self.devices = devices
    }

    var vendorLabel: String {
        let searchable = "\(sourceName) \(bundleIdentifier) \(sourceProductType ?? "")".lowercased()
        if searchable.contains("eight") { return "Eight Sleep" }
        if searchable.contains("hume") || searchable.contains("fittrack") { return "Hume" }
        if searchable.contains("watch") { return "Apple Watch" }
        if searchable.contains("health") { return "Apple Health" }
        return sourceName
    }
}

/// Sample-based coverage only. A zero count means no readable sample was
/// observed in the fetched window; HealthKit does not reveal whether that is
/// because a sensor has no data or the person declined read access.
struct MetricObservedCoverage: Identifiable, Hashable, Sendable {
    var id: MetricKind { kind }
    let kind: MetricKind
    let sampleCount: Int
    let observedDayCount: Int
    let firstSample: Date?
    let latestSample: Date?
    let sourceCount: Int
    let deviceCount: Int

    var hasObservedSamples: Bool { sampleCount > 0 }
}

struct SleepSession: Identifiable, Hashable, Sendable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let asleepMinutes: Double
    let inBedMinutes: Double
    let deepMinutes: Double
    let remMinutes: Double
    let sourceName: String
    let sourceBundleIdentifier: String

    var efficiency: Double {
        guard inBedMinutes > 0 else { return 1 }
        return min(max(asleepMinutes / inBedMinutes, 0), 1)
    }

    var restorativeMinutes: Double { deepMinutes + remMinutes }
}

enum DataConfidence: String, Codable, Sendable {
    case low
    case medium
    case high

    var title: String { rawValue.capitalized }
}

enum MetricSourceMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case manual
}

struct DecisionMetricPreference: Identifiable, Codable, Equatable, Sendable {
    var id: MetricKind { metric }

    let metric: MetricKind
    var shownOnToday: Bool
    var usedInRecommendation: Bool
    var sourceMode: MetricSourceMode
    var manualSourceBundleIdentifier: String?
    var allowAutomaticFallback: Bool

    init(
        metric: MetricKind,
        shownOnToday: Bool = true,
        usedInRecommendation: Bool = true,
        sourceMode: MetricSourceMode = .automatic,
        manualSourceBundleIdentifier: String? = nil,
        allowAutomaticFallback: Bool = true
    ) {
        self.metric = metric
        self.shownOnToday = shownOnToday
        self.usedInRecommendation = usedInRecommendation
        self.sourceMode = sourceMode
        self.manualSourceBundleIdentifier = manualSourceBundleIdentifier
        self.allowAutomaticFallback = allowAutomaticFallback
    }

    static func defaultValue(for metric: MetricKind) -> DecisionMetricPreference {
        DecisionMetricPreference(metric: metric)
    }

    var requestedBundleIdentifier: String? {
        guard sourceMode == .manual else { return nil }
        let trimmed = manualSourceBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct MetricSourceHealth: Hashable, Sendable {
    enum State: String, Hashable, Sendable {
        case automatic
        case manual
        case fallback
        case unavailable
    }

    let state: State
    let requestedBundleIdentifier: String?
    let selectedBundleIdentifier: String?
    let reason: String

    var usedAutomaticFallback: Bool { state == .fallback }

    static func unavailable(
        requestedBundleIdentifier: String? = nil,
        reason: String = "No source has provided readable data yet."
    ) -> MetricSourceHealth {
        MetricSourceHealth(
            state: .unavailable,
            requestedBundleIdentifier: requestedBundleIdentifier,
            selectedBundleIdentifier: nil,
            reason: reason
        )
    }
}

enum ReadinessBand: String, Codable, CaseIterable, Sendable {
    case high
    case moderate
    case low

    var title: String {
        switch self {
        case .high: "Ready to perform"
        case .moderate: "Train with restraint"
        case .low: "Recovery first"
        }
    }
}

enum TrendWindow: Int, CaseIterable, Identifiable, Sendable {
    case sevenDays = 7
    case twentyEightDays = 28

    var id: Int { rawValue }
    var title: String { self == .sevenDays ? "7D" : "28D" }
}

enum MetricFreshness: String, Hashable, Sendable {
    case current
    case recent
    case stale
    case missing

    var symbol: String {
        switch self {
        case .current: "checkmark.circle.fill"
        case .recent: "clock.fill"
        case .stale: "exclamationmark.triangle.fill"
        case .missing: "questionmark.circle"
        }
    }
}

enum MetricSignalStatus: String, Hashable, Sendable {
    case onTarget
    case nearTarget
    case needsAttention
    case buildingBaseline
    case unavailable

    var symbol: String {
        switch self {
        case .onTarget: "checkmark.circle.fill"
        case .nearTarget: "minus.circle.fill"
        case .needsAttention: "exclamationmark.circle.fill"
        case .buildingBaseline: "clock.badge.questionmark.fill"
        case .unavailable: "questionmark.circle"
        }
    }
}

struct MetricTrendPoint: Identifiable, Hashable, Sendable {
    var id: Date { date }
    let date: Date
    let value: Double?
    /// Percent change from the comparison value. This is precomputed so views never
    /// need to reinterpret raw samples or independently choose a baseline.
    let deviationPercentage: Double?
    /// Consecutive recorded points share a segment. Missing calendar days are nil.
    let segmentID: Int?
}

struct MetricTrendSummary: Hashable, Sendable {
    let average: Double?
    let referenceValue: Double?
    let deltaFromReference: Double?
    let recordedDays: Int
    let expectedDays: Int

    var completeness: Double {
        guard expectedDays > 0 else { return 0 }
        return Double(recordedDays) / Double(expectedDays)
    }

    var completenessText: String { "\(recordedDays)/\(expectedDays) days" }

    static func empty(expectedDays: Int) -> MetricTrendSummary {
        .init(
            average: nil,
            referenceValue: nil,
            deltaFromReference: nil,
            recordedDays: 0,
            expectedDays: expectedDays
        )
    }
}

struct MetricTrendSeries: Identifiable, Hashable, Sendable {
    var id: MetricKind { kind }
    let kind: MetricKind
    let sourceName: String?
    let sourceBundleIdentifier: String?
    let currentValue: Double?
    let currentDate: Date?
    let referenceValue: Double?
    let referenceLabel: String
    let baselineDayCount: Int
    let freshness: MetricFreshness
    let ageInDays: Int?
    let status: MetricSignalStatus
    let statusText: String
    let sourceHealth: MetricSourceHealth
    let points: [MetricTrendPoint]
    let sevenDaySummary: MetricTrendSummary
    let twentyEightDaySummary: MetricTrendSummary

    func summary(for window: TrendWindow) -> MetricTrendSummary {
        switch window {
        case .sevenDays: sevenDaySummary
        case .twentyEightDays: twentyEightDaySummary
        }
    }

    var freshnessText: String {
        guard let ageInDays else { return "No recent data" }
        switch freshness {
        case .current:
            return "Updated today"
        case .recent:
            return ageInDays == 1 ? "Updated yesterday" : "Updated \(ageInDays)d ago"
        case .stale:
            return "Stale · \(ageInDays)d old"
        case .missing:
            return "No recent data"
        }
    }

    static func empty(kind: MetricKind, referenceLabel: String) -> MetricTrendSeries {
        .init(
            kind: kind,
            sourceName: nil,
            sourceBundleIdentifier: nil,
            currentValue: nil,
            currentDate: nil,
            referenceValue: nil,
            referenceLabel: referenceLabel,
            baselineDayCount: 0,
            freshness: .missing,
            ageInDays: nil,
            status: .unavailable,
            statusText: "Unavailable",
            sourceHealth: .unavailable(),
            points: [],
            sevenDaySummary: .empty(expectedDays: TrendWindow.sevenDays.rawValue),
            twentyEightDaySummary: .empty(expectedDays: TrendWindow.twentyEightDays.rawValue)
        )
    }
}

struct SleepTimingVariability: Hashable, Sendable {
    let sourceName: String?
    let sourceBundleIdentifier: String?
    let recordedNights: Int
    let bedtimeMinutes: Double?
    let wakeTimeMinutes: Double?

    static let empty = SleepTimingVariability(
        sourceName: nil,
        sourceBundleIdentifier: nil,
        recordedNights: 0,
        bedtimeMinutes: nil,
        wakeTimeMinutes: nil
    )
}

struct RecommendationReason: Identifiable, Hashable, Sendable {
    let id = UUID()
    let title: String
    let detail: String
    let isPositive: Bool
}

struct EnergyWindow: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case grogginess
        case peak
        case dip
        case windDown
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let startDate: Date
    let endDate: Date
}

struct CalendarCommitment: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
}

enum SafetySignalState: String, Hashable, Sendable {
    case noCurrentValue
    case stale
    case buildingBaseline
    case withinRange
    case outlier
}

struct SafetySignalEvaluation: Identifiable, Hashable, Sendable {
    var id: MetricKind { kind }
    let kind: MetricKind
    let state: SafetySignalState
    let currentValue: Double?
    let currentDate: Date?
    let baselineMedian: Double?
    let baselineNightCount: Int
    let deviation: Double?
    let outlierThreshold: Double?
    let sourceName: String?
    let sourceBundleIdentifier: String?

    var isFreshOutlier: Bool { state == .outlier }

    var statusText: String {
        switch state {
        case .noCurrentValue:
            "No readable sample observed"
        case .stale:
            "Latest sample is stale — neutral"
        case .buildingBaseline:
            "Building baseline · \(baselineNightCount)/\(SafetyGateEvaluation.minimumBaselineNights) nights"
        case .withinRange:
            "Within your same-source range"
        case .outlier:
            "Outside your same-source range"
        }
    }
}

struct SafetyGateEvaluation: Hashable, Sendable {
    static let baselineWindowDays = 21
    static let minimumBaselineNights = 14

    let signals: [SafetySignalEvaluation]

    var freshOutliers: [SafetySignalEvaluation] {
        signals.filter(\.isFreshOutlier)
    }

    var freshOutlierCount: Int { freshOutliers.count }
    var blocksProgression: Bool { freshOutlierCount >= 1 }
    var capsReadinessAtModerate: Bool { freshOutlierCount >= 2 }

    static let neutral = SafetyGateEvaluation(signals: [])
}

struct TrainingContextSnapshot: Hashable, Sendable {
    let previousDayActiveEnergy: Double?
    let previousDayExerciseMinutes: Double?
    let previousDaySteps: Double?
    let workoutsLastSevenDays: Int
    let workoutMinutesLastSevenDays: Double?
    let latestWorkoutDate: Date?

    init(
        previousDayActiveEnergy: Double? = nil,
        previousDayExerciseMinutes: Double? = nil,
        previousDaySteps: Double? = nil,
        workoutsLastSevenDays: Int = 0,
        workoutMinutesLastSevenDays: Double? = nil,
        latestWorkoutDate: Date? = nil
    ) {
        self.previousDayActiveEnergy = previousDayActiveEnergy
        self.previousDayExerciseMinutes = previousDayExerciseMinutes
        self.previousDaySteps = previousDaySteps
        self.workoutsLastSevenDays = workoutsLastSevenDays
        self.workoutMinutesLastSevenDays = workoutMinutesLastSevenDays
        self.latestWorkoutDate = latestWorkoutDate
    }

    static let empty = TrainingContextSnapshot()
}

struct DailyHealthSnapshot: Sendable {
    let generatedAt: Date
    let samples: [MetricSample]
    let sleepSessions: [SleepSession]
    let latestSleep: SleepSession?
    let readinessAvailable: Bool
    let sleepDebtMinutes: Double
    let readinessScore: Int
    let readinessBand: ReadinessBand
    /// The core calculation before safety-only gates are applied. Safety metrics
    /// never add points or promote a readiness band.
    let coreReadinessScore: Int
    let coreReadinessBand: ReadinessBand
    let confidence: DataConfidence
    let reasons: [RecommendationReason]
    let latestHRV: Double?
    let baselineHRV: Double?
    let latestRestingHeartRate: Double?
    let baselineRestingHeartRate: Double?
    let previousDayActiveEnergy: Double?
    let sleepTrend: MetricTrendSeries
    let hrvTrend: MetricTrendSeries
    let restingHeartRateTrend: MetricTrendSeries
    let todaySignalOrder: [MetricKind]
    let sleepTimingVariability: SleepTimingVariability
    let recoveryTakeaway: String
    let safetyGate: SafetyGateEvaluation
    let trainingContext: TrainingContextSnapshot

    init(
        generatedAt: Date,
        samples: [MetricSample],
        sleepSessions: [SleepSession],
        latestSleep: SleepSession?,
        readinessAvailable: Bool,
        sleepDebtMinutes: Double,
        readinessScore: Int,
        readinessBand: ReadinessBand,
        confidence: DataConfidence,
        reasons: [RecommendationReason],
        latestHRV: Double?,
        baselineHRV: Double?,
        latestRestingHeartRate: Double?,
        baselineRestingHeartRate: Double?,
        previousDayActiveEnergy: Double?,
        sleepTrend: MetricTrendSeries,
        hrvTrend: MetricTrendSeries,
        restingHeartRateTrend: MetricTrendSeries,
        todaySignalOrder: [MetricKind],
        sleepTimingVariability: SleepTimingVariability,
        recoveryTakeaway: String,
        coreReadinessScore: Int? = nil,
        coreReadinessBand: ReadinessBand? = nil,
        safetyGate: SafetyGateEvaluation = .neutral,
        trainingContext: TrainingContextSnapshot = .empty
    ) {
        self.generatedAt = generatedAt
        self.samples = samples
        self.sleepSessions = sleepSessions
        self.latestSleep = latestSleep
        self.readinessAvailable = readinessAvailable
        self.sleepDebtMinutes = sleepDebtMinutes
        self.readinessScore = readinessScore
        self.readinessBand = readinessBand
        self.coreReadinessScore = coreReadinessScore ?? readinessScore
        self.coreReadinessBand = coreReadinessBand ?? readinessBand
        self.confidence = confidence
        self.reasons = reasons
        self.latestHRV = latestHRV
        self.baselineHRV = baselineHRV
        self.latestRestingHeartRate = latestRestingHeartRate
        self.baselineRestingHeartRate = baselineRestingHeartRate
        self.previousDayActiveEnergy = previousDayActiveEnergy
        self.sleepTrend = sleepTrend
        self.hrvTrend = hrvTrend
        self.restingHeartRateTrend = restingHeartRateTrend
        self.todaySignalOrder = todaySignalOrder
        self.sleepTimingVariability = sleepTimingVariability
        self.recoveryTakeaway = recoveryTakeaway
        self.safetyGate = safetyGate
        self.trainingContext = trainingContext
    }

    var signalTrends: [MetricTrendSeries] {
        todaySignalOrder.compactMap { metric in
            switch metric {
            case .sleep: sleepTrend
            case .heartRateVariability: hrvTrend
            case .restingHeartRate: restingHeartRateTrend
            default: nil
            }
        }
    }

    /// Compatibility alias for the existing Today view.
    var recoverySignals: [MetricTrendSeries] { signalTrends }

    static let empty = DailyHealthSnapshot(
        generatedAt: .now,
        samples: [],
        sleepSessions: [],
        latestSleep: nil,
        readinessAvailable: false,
        sleepDebtMinutes: 0,
        readinessScore: 0,
        readinessBand: .moderate,
        confidence: .low,
        reasons: [],
        latestHRV: nil,
        baselineHRV: nil,
        latestRestingHeartRate: nil,
        baselineRestingHeartRate: nil,
        previousDayActiveEnergy: nil,
        sleepTrend: .empty(kind: .sleep, referenceLabel: "Sleep target"),
        hrvTrend: .empty(kind: .heartRateVariability, referenceLabel: "Your 21-day baseline"),
        restingHeartRateTrend: .empty(kind: .restingHeartRate, referenceLabel: "Your 21-day baseline"),
        todaySignalOrder: MetricKind.decisionMetrics,
        sleepTimingVariability: .empty,
        recoveryTakeaway: "Connect Apple Health to start building recovery trends.",
        safetyGate: .neutral,
        trainingContext: .empty
    )
}

struct WorkoutAdjustment: Hashable, Sendable {
    let title: String
    let detail: String
    let volumeMultiplier: Double
    let rpeCap: Double?
    let allowProgression: Bool

    var volumePrescription: String {
        "\(Int((volumeMultiplier * 100).rounded()))% of planned working sets"
    }

    var effortPrescription: String {
        guard let rpeCap else { return "Use your planned effort targets" }
        let repsLeft = max(Int((10 - rpeCap).rounded()), 0)
        let plainLanguage = repsLeft == 1
            ? "Stop with about 1 rep left"
            : "Stop with about \(repsLeft) reps left"
        return "\(plainLanguage) · RPE ≤ \(rpeCap.formatted(.number.precision(.fractionLength(0...1))))"
    }

    var progressionPrescription: String {
        allowProgression
            ? "Manual · recovery supports an increase"
            : "Keep planned loads today"
    }
}

struct DailyPlan: Sendable {
    let generatedAt: Date
    let bedtime: Date
    let wakeTime: Date
    let gymStart: Date
    let gymEnd: Date
    let firstCommitment: CalendarCommitment?
    let readiness: ReadinessBand
    let confidence: DataConfidence
    let workoutAdjustment: WorkoutAdjustment
    let energyWindows: [EnergyWindow]
    let warnings: [String]

    static func placeholder(referenceDate: Date = .now) -> DailyPlan {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate))!
        let wake = calendar.date(bySettingHour: 6, minute: 30, second: 0, of: tomorrow)!
        return DailyPlan(
            generatedAt: referenceDate,
            bedtime: calendar.date(byAdding: .minute, value: -510, to: wake)!,
            wakeTime: wake,
            gymStart: calendar.date(byAdding: .minute, value: 20, to: wake)!,
            gymEnd: calendar.date(byAdding: .minute, value: 80, to: wake)!,
            firstCommitment: nil,
            readiness: .moderate,
            confidence: .low,
            workoutAdjustment: .init(
                title: "Calibrating",
                detail: "Connect Health to personalize tomorrow's training.",
                volumeMultiplier: 1,
                rpeCap: nil,
                allowProgression: false
            ),
            energyWindows: [],
            warnings: ["Connect Apple Health and Calendar to replace this example plan."]
        )
    }
}

struct WellnessPreferences: Codable, Equatable, Sendable {
    var sleepNeedMinutes: Double
    var gymDurationMinutes: Int
    var travelToGymMinutes: Int
    var postWorkoutMinutes: Int
    var commitmentBufferMinutes: Int
    var fallbackCommitmentHour: Int
    var decisionMetricPreferences: [DecisionMetricPreference]
    var signalOrder: [MetricKind]

    init(
        sleepNeedMinutes: Double = 480,
        gymDurationMinutes: Int = 60,
        travelToGymMinutes: Int = 15,
        postWorkoutMinutes: Int = 30,
        commitmentBufferMinutes: Int = 10,
        fallbackCommitmentHour: Int = 9,
        decisionMetricPreferences: [DecisionMetricPreference] = MetricKind.decisionMetrics.map(DecisionMetricPreference.defaultValue),
        signalOrder: [MetricKind] = MetricKind.decisionMetrics
    ) {
        self.sleepNeedMinutes = sleepNeedMinutes
        self.gymDurationMinutes = gymDurationMinutes
        self.travelToGymMinutes = travelToGymMinutes
        self.postWorkoutMinutes = postWorkoutMinutes
        self.commitmentBufferMinutes = commitmentBufferMinutes
        self.fallbackCommitmentHour = fallbackCommitmentHour
        self.decisionMetricPreferences = Self.normalizedPreferences(decisionMetricPreferences)
        self.signalOrder = Self.normalizedSignalOrder(signalOrder)
    }

    func decisionPreference(for metric: MetricKind) -> DecisionMetricPreference {
        decisionMetricPreferences.first(where: { $0.metric == metric })
            ?? .defaultValue(for: metric)
    }

    var orderedTodayMetrics: [MetricKind] {
        signalOrder.filter { decisionPreference(for: $0).shownOnToday }
    }

    private enum CodingKeys: String, CodingKey {
        case sleepNeedMinutes
        case gymDurationMinutes
        case travelToGymMinutes
        case postWorkoutMinutes
        case commitmentBufferMinutes
        case fallbackCommitmentHour
        case decisionMetricPreferences
        case signalOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sleepNeedMinutes = try container.decodeIfPresent(Double.self, forKey: .sleepNeedMinutes) ?? 480
        gymDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .gymDurationMinutes) ?? 60
        travelToGymMinutes = try container.decodeIfPresent(Int.self, forKey: .travelToGymMinutes) ?? 15
        postWorkoutMinutes = try container.decodeIfPresent(Int.self, forKey: .postWorkoutMinutes) ?? 30
        commitmentBufferMinutes = try container.decodeIfPresent(Int.self, forKey: .commitmentBufferMinutes) ?? 10
        fallbackCommitmentHour = try container.decodeIfPresent(Int.self, forKey: .fallbackCommitmentHour) ?? 9
        decisionMetricPreferences = Self.normalizedPreferences(
            try container.decodeIfPresent([DecisionMetricPreference].self, forKey: .decisionMetricPreferences) ?? []
        )
        signalOrder = Self.normalizedSignalOrder(
            try container.decodeIfPresent([MetricKind].self, forKey: .signalOrder) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sleepNeedMinutes, forKey: .sleepNeedMinutes)
        try container.encode(gymDurationMinutes, forKey: .gymDurationMinutes)
        try container.encode(travelToGymMinutes, forKey: .travelToGymMinutes)
        try container.encode(postWorkoutMinutes, forKey: .postWorkoutMinutes)
        try container.encode(commitmentBufferMinutes, forKey: .commitmentBufferMinutes)
        try container.encode(fallbackCommitmentHour, forKey: .fallbackCommitmentHour)
        try container.encode(decisionMetricPreferences, forKey: .decisionMetricPreferences)
        try container.encode(signalOrder, forKey: .signalOrder)
    }

    private static func normalizedPreferences(
        _ preferences: [DecisionMetricPreference]
    ) -> [DecisionMetricPreference] {
        var seen = Set<MetricKind>()
        var result = preferences.filter {
            MetricKind.decisionMetrics.contains($0.metric) && seen.insert($0.metric).inserted
        }
        for metric in MetricKind.decisionMetrics where !seen.contains(metric) {
            result.append(.defaultValue(for: metric))
        }
        return result
    }

    private static func normalizedSignalOrder(_ order: [MetricKind]) -> [MetricKind] {
        var seen = Set<MetricKind>()
        var result = order.filter {
            MetricKind.decisionMetrics.contains($0) && seen.insert($0).inserted
        }
        for metric in MetricKind.decisionMetrics where !seen.contains(metric) {
            result.append(metric)
        }
        return result
    }

    static let `default` = WellnessPreferences()
}
