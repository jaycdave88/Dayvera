import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var nutrition: NutritionModel
    @Query(sort: \WorkoutSessionRecord.startedAt, order: .reverse) private var sessions: [WorkoutSessionRecord]
    @State private var showingRecommendationReasons = false
    @State private var showingDebugRecoveryTrends = false
    @State private var dismissedReturnMessage = false
    @State private var trainingMilestoneAcknowledged = false
    let returningExperience: ReturningExperience
    let onOpenTrain: () -> Void
    let onOpenPlan: () -> Void
    let onOpenNutrition: () -> Void
    let onOpenRecoveryTrends: () -> Void
    let onOpenDataSources: () -> Void

    init(
        returningExperience: ReturningExperience = .none,
        onOpenTrain: @escaping () -> Void = {},
        onOpenPlan: @escaping () -> Void = {},
        onOpenNutrition: @escaping () -> Void = {},
        onOpenRecoveryTrends: @escaping () -> Void = {},
        onOpenDataSources: @escaping () -> Void = {}
    ) {
        self.returningExperience = returningExperience
        self.onOpenTrain = onOpenTrain
        self.onOpenPlan = onOpenPlan
        self.onOpenNutrition = onOpenNutrition
        self.onOpenRecoveryTrends = onOpenRecoveryTrends
        self.onOpenDataSources = onOpenDataSources
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                if returningExperience != .none, !dismissedReturnMessage {
                    returningUserCard
                }
                TodayWorkoutRecommendationView(onOpenTrain: onOpenTrain)
                if appModel.snapshot.readinessAvailable, !availableRecoverySignals.isEmpty {
                    recoverySignals
                    recoveryTrendsNavigation
                } else {
                    connectCard
                }
                NutritionTodayCard(onOpenNutrition: onOpenNutrition)
                morningPlanCard
                weeklyRhythmCard
                if weeklyRhythm.trainingPlanMet, !trainingMilestoneAcknowledged {
                    trainingMilestoneCard
                }
                safetyNote
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await appModel.refresh() } } label: {
                    if appModel.isRefreshing { SwiftUI.ProgressView() }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(appModel.isRefreshing)
                .accessibilityLabel("Refresh health data")
            }
        }
        .navigationDestination(isPresented: $showingDebugRecoveryTrends) {
            RecoveryTrendsView()
        }
        .task {
            trainingMilestoneAcknowledged = appModel.hasAcknowledgedMotivationReceipt(trainingWeekMilestoneID)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--show-recovery-progress") {
                showingDebugRecoveryTrends = true
            }
            #endif
        }
        .onChange(of: trainingWeekMilestoneID) { _, identifier in
            trainingMilestoneAcknowledged = appModel.hasAcknowledgedMotivationReceipt(identifier)
        }
    }

    private var morningPlanCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Tomorrow Morning", systemImage: "alarm.fill")
                        .font(.headline)
                    Spacer()
                    Text(appModel.plan.confidence.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 0) {
                    planTime("Wake", date: appModel.plan.wakeTime)
                    Divider().frame(height: 34)
                    planTime("Train", date: appModel.plan.gymStart)
                    Divider().frame(height: 34)
                    planTime("Done", date: appModel.plan.gymEnd)
                }
                Button("Review Morning Plan") { onOpenPlan() }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        }
    }

    private func planTime(_ title: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(date.shortTime).font(.subheadline.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var trainingDecision: some View {
        let adjustment = appModel.plan.workoutAdjustment
        return CoachCard {
            VStack(alignment: .leading, spacing: 13) {
                Text(dynamicTypeSize.isAccessibilitySize ? "TODAY'S TRAINING" : "HOW SHOULD I TRAIN TODAY?")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                Text(adjustment.title)
                    .font(.title2.bold())
                Text(adjustment.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !dynamicTypeSize.isAccessibilitySize {
                    trainButton
                }

                Divider()

                PrescriptionRow(
                    symbol: "chart.bar.fill",
                    label: "Volume",
                    prescription: adjustment.volumePrescription
                )
                PrescriptionRow(
                    symbol: "gauge.with.dots.needle.50percent",
                    label: "Effort",
                    prescription: adjustment.effortPrescription
                )
                PrescriptionRow(
                    symbol: adjustment.allowProgression ? "arrow.up.right.circle.fill" : "pause.circle.fill",
                    label: "Progression",
                    prescription: adjustment.progressionPrescription
                )

                Divider()
                readinessSummary

                if !appModel.snapshot.reasons.isEmpty {
                    Divider()
                    recommendationExplanation
                }
            }
        }
    }

    private var recommendationExplanation: some View {
        DisclosureGroup(isExpanded: $showingRecommendationReasons) {
            VStack(spacing: 10) {
                ForEach(Array(appModel.snapshot.reasons.prefix(2))) { reason in
                    recommendationReasonRow(reason)
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Why this recommendation", systemImage: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .tint(Color.coachIndigo)
    }

    private func recommendationReasonRow(_ reason: RecommendationReason) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: reason.isPositive ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(reason.isPositive ? Color.coachMint : Color.coachAmber)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(reason.title)
                    .font(.subheadline.bold())
                Text(reason.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var readinessSummary: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: appModel.snapshot.readinessAvailable ? appModel.snapshot.readinessBand.symbol : "ellipsis.circle")
                .foregroundStyle(readinessColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(appModel.snapshot.readinessAvailable
                     ? "Readiness \(appModel.snapshot.readinessScore)/100 · \(appModel.snapshot.readinessBand.title)"
                     : "Readiness unavailable")
                    .font(.subheadline.weight(.semibold))
                Text(readinessQualifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var readinessQualifier: String {
        guard appModel.snapshot.readinessAvailable else {
            return "Recommendation confidence: Unavailable · recent overnight sleep required"
        }
        if appModel.snapshot.confidence == .low {
            return "Recommendation confidence: Low · baseline still developing · updated \(appModel.snapshot.generatedAt.shortTime)"
        }
        return "Recommendation confidence: \(appModel.snapshot.confidence.title) · updated \(appModel.snapshot.generatedAt.shortTime)"
    }

    private var connectCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 13) {
                Label {
                    Text(recoveryUnavailableTitle)
                } icon: {
                    Image(systemName: "heart.text.square.fill").foregroundStyle(Color.coachIndigo)
                }
                .font(.headline)
                Text(recoveryUnavailableDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                recoveryPrimaryAction

                Button("Browse saved workouts") {
                    onOpenTrain()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.coachIndigo)
                .frame(minHeight: 44)
            }
        }
    }

    private var trainButton: some View {
        Button {
            onOpenTrain()
        } label: {
            Label(
                dynamicTypeSize.isAccessibilitySize ? "Choose workout" : "Choose today's workout",
                systemImage: "figure.strengthtraining.traditional"
            )
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.coachIndigo)
        .accessibilityLabel("Choose today's workout")
    }

    @ViewBuilder
    private var recoveryPrimaryAction: some View {
        if appModel.healthConnectionState.canRequestAccess {
            Button("Connect Apple Health") { Task { await appModel.connectHealth() } }
                .buttonStyle(.borderedProminent)
                .tint(Color.coachIndigo)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else if !hasEnabledRecommendationSignal {
            Button("Open Data & Sources") { onOpenDataSources() }
                .buttonStyle(.borderedProminent)
                .tint(Color.coachIndigo)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            Button("Review Data & Sources") { onOpenDataSources() }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var recoveryUnavailableTitle: String {
        if !hasEnabledRecommendationSignal { return "Choose recovery signals" }
        if appModel.healthConnectionState == .notRequested { return "Add recovery context" }
        return "Recovery guidance unavailable"
    }

    private var recoveryUnavailableDetail: String {
        if !hasEnabledRecommendationSignal {
            return "No signal is currently allowed to add recovery context. Choose at least one in Data & Sources; workout planning still uses your preferences and training history."
        }
        switch appModel.healthConnectionState {
        case .notRequested:
            return "Connect Apple Health to add supported sleep, HRV, and resting-heart-rate data. Workout planning still works from your preferences and training history."
        case .accessRequested, .noReadableSamples:
            return "Apple Health has not returned readable recovery samples yet. Check source sharing, then refresh; today’s workout still uses your preferences and training history."
        case .refreshFailed:
            return "The latest Apple Health refresh failed, so stale recovery context was removed. Today’s workout still uses your preferences and training history."
        case .partialData(_, _):
            return "Some Apple Health queries failed, and the remaining enabled signals do not yet support recovery guidance. Review the affected signal in Data & Sources."
        case .dataReceived(_), .demoData:
            return "Received data does not yet include enough current history for recovery guidance. Review freshness and baseline depth in Data & Sources."
        }
    }

    private var hasEnabledRecommendationSignal: Bool {
        appModel.preferences.decisionMetricPreferences.contains(where: \.usedInRecommendation)
    }

    private var recoverySignals: some View {
        VStack(spacing: 10) {
            SectionTitle(
                title: "Recovery signals",
                subtitle: "Current value compared with your target or recent baseline"
            )
            ForEach(availableRecoverySignals) { signal in
                RecoverySignalRow(signal: signal)
            }
        }
    }

    private var recoveryTrendsNavigation: some View {
        VStack(spacing: 10) {
            Button(action: onOpenRecoveryTrends) {
                HStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.headline)
                        .foregroundStyle(Color.coachIndigo)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recovery trends")
                            .font(.subheadline.weight(.semibold))
                        Text("See sleep, HRV, and resting heart rate over time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(14)
                .background(Color.coachSurface, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Recovery in the Progress tab")
        }
    }

    /// Today is for decisions, not HealthKit diagnostics. A missing or stale
    /// signal remains configurable in Data & Sources, but only recent readings
    /// with an identified source are shown as recovery cards here.
    private var availableRecoverySignals: [MetricTrendSeries] {
        appModel.snapshot.recoverySignals.filter { signal in
            guard signal.currentValue != nil, signal.sourceName != nil else { return false }
            return signal.freshness == .current || signal.freshness == .recent
        }
    }

    private var readinessColor: Color {
        appModel.snapshot.readinessAvailable ? appModel.snapshot.readinessBand.color : .coachIndigo
    }

    private var safetyNote: some View {
        Text("Directional wellness guidance only. Wearable readings cannot diagnose illness or determine whether exercise is medically safe. If a reading or symptom concerns you, consult a qualified clinician.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
    }

    private var weeklyRhythm: WeeklyRhythm {
        WeeklyRhythmEngine.summary(
            sessionDates: sessions.map(\.endedAt),
            trainingTarget: appModel.trainingProfile.targetSessionsPerWeek,
            completedNutritionDayKeys: Set(nutrition.days.filter(\.isComplete).map(\.dayKey)),
            recoveryDates: appModel.snapshot.sleepSessions.map(\.endDate)
        )
    }

    private var trainingWeekMilestoneID: String {
        "training-week-\(Int(weeklyRhythm.weekStart.timeIntervalSince1970))"
    }

    private var returningUserCard: some View {
        CoachCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.coachIndigo)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Welcome back").font(.headline)
                    Text(returningExperience == .trendsNeedData
                         ? "Today’s guidance is ready. Recent trends may need more data before they become useful again."
                         : "Today’s guidance is ready when you are.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { dismissedReturnMessage = true } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss welcome message")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var weeklyRhythmCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "Weekly rhythm", subtitle: "Progress without requiring a perfect week")
                WeeklyRhythmRow(
                    title: "Training",
                    value: "\(weeklyRhythm.trainingCompleted) of \(weeklyRhythm.trainingTarget) planned sessions",
                    progress: weeklyRhythm.trainingProgress,
                    tint: .coachIndigo
                )
                if nutrition.profile.completedSetup {
                    WeeklyRhythmRow(
                        title: "Nutrition evidence",
                        value: "\(weeklyRhythm.completeNutritionDays) complete days",
                        progress: weeklyRhythm.nutritionProgress,
                        tint: .coachMint
                    )
                }
                WeeklyRhythmRow(
                    title: "Recovery coverage",
                    value: "\(weeklyRhythm.recoveryNightsRecorded) of \(weeklyRhythm.recoveryEligibleNights) eligible nights",
                    progress: weeklyRhythm.recoveryProgress,
                    tint: .coachAmber
                )
                if let momentum = weeklyRhythm.momentumText {
                    Label(momentum, systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var trainingMilestoneCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Weekly plan complete", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(Color.coachMint)
                Text("You completed \(weeklyRhythm.trainingCompleted) planned training sessions this week.")
                    .font(.subheadline)
                Button("Got it") {
                    if appModel.acknowledgeMotivationReceipt(trainingWeekMilestoneID) {
                        trainingMilestoneAcknowledged = true
                    }
                }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        }
    }
}

private struct WeeklyRhythmRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let value: String
    let progress: Double?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) { labels }
                } else {
                    HStack(alignment: .firstTextBaseline) { labels }
                }
            }
            if let progress {
                SwiftUI.ProgressView(value: progress)
                    .tint(tint)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    @ViewBuilder private var labels: some View {
        Text(title).font(.subheadline.weight(.semibold))
        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
        Text(value).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
    }
}

private struct PrescriptionRow: View {
    let symbol: String
    let label: String
    let prescription: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.coachIndigo)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(prescription).font(.subheadline.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RecoverySignalRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let signal: MetricTrendSeries

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    signalCopy
                    sparkline.frame(maxWidth: .infinity, minHeight: 58)
                }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    signalCopy
                    Spacer(minLength: 6)
                    sparkline.frame(width: 104, height: 54)
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.coachSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var signalCopy: some View {
        VStack(alignment: .leading, spacing: 5) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(signal.kind.title).font(.headline)
                        statusLabel
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(signal.kind.title).font(.headline)
                        statusLabel
                    }
                }
            }
            Text("\(formatted(signal.currentValue)) vs \(signal.referenceLabel.lowercased()) \(formatted(signal.referenceValue))")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text("\(signal.sourceName ?? "No source") · \(signal.freshnessText) · \(signal.sevenDaySummary.completenessText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusLabel: some View {
        Label {
            Text(signal.statusText)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: signal.status.symbol)
                .foregroundStyle(statusColor)
        }
        .font(.caption.weight(.semibold))
    }

    @ViewBuilder
    private var sparkline: some View {
        let points = Array(signal.points.suffix(7))
        if points.contains(where: { $0.value != nil }) {
            Chart {
                ForEach(points) { point in
                    if let value = point.value, let segmentID = point.segmentID {
                        LineMark(
                            x: .value("Day", point.date),
                            y: .value("Value", value),
                            series: .value("Recorded run", segmentID)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.coachIndigo)
                        PointMark(
                            x: .value("Day", point.date),
                            y: .value("Value", value)
                        )
                        .symbolSize(14)
                        .foregroundStyle(Color.coachIndigo)
                    }
                }
                if let reference = signal.referenceValue {
                    RuleMark(y: .value(signal.referenceLabel, reference))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(signal.kind.title) seven-day trend")
            .accessibilityValue(chartAccessibilityValue)
        } else {
            Text("No trend yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("\(signal.kind.title) trend unavailable")
        }
    }

    private var chartAccessibilityValue: String {
        let summary = signal.sevenDaySummary
        return "\(summary.completenessText) recorded. Current \(formatted(signal.currentValue)); \(signal.referenceLabel) \(formatted(signal.referenceValue))."
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "—" }
        switch signal.kind {
        case .sleep: return value.hoursMinutes
        case .heartRateVariability: return "\(Int(value.rounded())) ms"
        case .restingHeartRate: return "\(Int(value.rounded())) bpm"
        default: return value.formatted(.number.precision(.fractionLength(0...1)))
        }
    }

    private var statusColor: Color {
        switch signal.status {
        case .onTarget: .coachMint
        case .nearTarget, .buildingBaseline: .coachAmber
        case .needsAttention: .coachRose
        case .unavailable: .secondary
        }
    }
}
