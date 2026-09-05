import Charts
import SwiftData
import SwiftUI

enum ProgressSection: String, CaseIterable, Identifiable {
    case recovery = "Recovery"
    case training = "Training"
    case nutrition = "Nutrition"

    var id: String { rawValue }
}

private struct BodyCompositionProgressObservation: Identifiable {
    var id: MetricKind { kind }
    let kind: MetricKind
    let currentValue: Double
    let delta: Double?
    let currentDate: Date
    let sourceName: String
}

private extension MetricKind {
    var progressSymbol: String {
        switch self {
        case .bodyMass: "scalemass.fill"
        case .bodyFatPercentage: "percent"
        case .leanBodyMass: "figure.strengthtraining.traditional"
        case .bodyMassIndex: "chart.xyaxis.line"
        default: "waveform.path.ecg"
        }
    }
}

struct ProgressView: View {
    @Binding private var section: ProgressSection

    init(section: Binding<ProgressSection>) {
        _section = section
    }

    var body: some View {
        ProgressDetailView(section: section, allowsSectionSelection: true) {
            Picker("Progress section", selection: $section) {
                ForEach(ProgressSection.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
        }
    }
}

struct RecoveryTrendsView: View {
    var body: some View {
        ProgressDetailView(section: .recovery, allowsSectionSelection: false) { EmptyView() }
    }
}

struct TrainingHistoryView: View {
    var body: some View {
        ProgressDetailView(section: .training, allowsSectionSelection: false) { EmptyView() }
    }
}

private struct ProgressDetailView<SectionPicker: View>: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \WorkoutSessionRecord.startedAt, order: .reverse) private var sessions: [WorkoutSessionRecord]
    let section: ProgressSection
    let allowsSectionSelection: Bool
    @ViewBuilder let sectionPicker: SectionPicker
    @State private var window: TrendWindow = .sevenDays
    @State private var selectedExerciseKey = ""

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                if allowsSectionSelection { sectionPicker }
                if section != .nutrition { dateRangeControl }
                switch section {
                case .recovery:
                    recoveryContent
                case .training:
                    trainingContent
                case .nutrition:
                    NutritionProgressView()
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(allowsSectionSelection ? "Progress" : (section == .recovery ? "Recovery Trends" : "Training History"))
        .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
        .onAppear(perform: reconcileExerciseSelection)
        .onChange(of: sessions.count) { _, _ in reconcileExerciseSelection() }
        .onChange(of: window) { _, _ in reconcileExerciseSelection() }
    }

    private var dateRangeControl: some View {
        Picker("Date range", selection: $window) {
            ForEach(TrendWindow.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .frame(minHeight: 44)
        .accessibilityLabel("Date range")
    }

    @ViewBuilder
    private var recoveryContent: some View {
        takeawayCard
        sleepDurationCard
        biometricCharts
        bodyMeasurementsCard
    }

    private var takeawayCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Recovery Summary", systemImage: "waveform.path.ecg")
                    .font(.headline)
                    .foregroundStyle(Color.coachIndigo)
                Text(appModel.snapshot.recoveryTakeaway)
                    .font(.title3.weight(.semibold))
                Text("Each trend uses one consistent source.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sleepDurationCard: some View {
        let signal = appModel.snapshot.sleepTrend
        let points = rangedPoints(signal)
        let summary = signal.summary(for: window)
        return CoachCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(
                    title: "Sleep duration",
                    subtitle: "\(signal.sourceName ?? "No source selected") · missing calendar nights remain gaps"
                )

                if points.contains(where: { $0.value != nil }) {
                    Chart {
                        ForEach(points) { point in
                            if let value = point.value {
                                BarMark(
                                    x: .value("Night", point.date, unit: .day),
                                    y: .value("Sleep minutes", value)
                                )
                                .foregroundStyle(Color.coachIndigo.gradient)
                                .cornerRadius(3)
                                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue(value.hoursMinutes)
                            } else {
                                RuleMark(x: .value("Missing night", point.date))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                                    .foregroundStyle(Color.secondary.opacity(0.18))
                                    .accessibilityLabel("No sleep record for \(point.date.formatted(date: .abbreviated, time: .omitted))")
                            }
                        }
                        if let target = signal.referenceValue {
                            RuleMark(y: .value("Sleep target", target))
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                                .foregroundStyle(Color.secondary)
                                .annotation(position: .top, alignment: .trailing) {
                                    Text("Target \(target.hoursMinutes)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(height: 230)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let minutes = value.as(Double.self) {
                                    Text("\(Int(minutes / 60))h")
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: window == .sevenDays ? 7 : 5)) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Sleep duration over \(window.rawValue) calendar days")
                    .accessibilityValue(sleepChartAccessibility(summary))
                } else {
                    EmptyState(
                        symbol: "moon.zzz",
                        title: "No sleep trend yet",
                        detail: "Recorded nights will appear against your sleep target; missing nights will stay visible as gaps."
                    )
                }

                Divider()
                sleepSummary(summary)
            }
        }
    }

    @ViewBuilder
    private func sleepSummary(_ summary: MetricTrendSummary) -> some View {
        let rows = [
            ("Average", summary.average?.hoursMinutes ?? "—", "Across recorded nights"),
            ("Delta", sleepDelta(summary.deltaFromReference), "Compared with your sleep target"),
            ("Completeness", summary.completenessText, "Calendar days with a record")
        ]
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(rows, id: \.0) { row in summaryItem(title: row.0, value: row.1, detail: row.2) }
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                ForEach(rows, id: \.0) { row in
                    summaryItem(title: row.0, value: row.1, detail: row.2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        let variability = appModel.snapshot.sleepTimingVariability
        Text(timingVariabilityText(variability))
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Sleep timing. \(timingVariabilityText(variability))")
    }

    private func summaryItem(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var biometricCharts: some View {
        VStack(spacing: 12) {
            BiometricDeviationCard(signal: appModel.snapshot.hrvTrend, window: window)
            BiometricDeviationCard(signal: appModel.snapshot.restingHeartRateTrend, window: window)
        }
    }

    private var bodyMeasurementsCard: some View {
        let observations = MetricKind.bodyCompositionMetrics.compactMap {
            bodyCompositionObservation(for: $0)
        }
        return CoachCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(
                    title: "Body Measurements",
                    subtitle: "Apple Health context · not used for readiness or workout selection"
                )

                if observations.isEmpty {
                    EmptyState(
                        symbol: "scalemass",
                        title: "No body measurements yet",
                        detail: "Standard weight and body-composition values shared with Apple Health will appear here."
                    )
                } else {
                    ForEach(observations) { observation in
                        bodyMeasurementRow(observation)
                        if observation.id != observations.last?.id {
                            Divider()
                        }
                    }
                }

                DisclosureGroup("How this context is used") {
                    Text("Dayvera shows non-user-entered body measurements for progress context only. Changes are same-source differences within the selected date range; they never raise or lower readiness, trigger a safety check, or alter a workout.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    private func bodyMeasurementRow(
        _ observation: BodyCompositionProgressObservation
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                bodyMeasurementIdentity(observation)
                bodyMeasurementValue(observation, alignment: .leading)
                    .padding(.leading, 36)
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .top, spacing: 12) {
                bodyMeasurementIdentity(observation)
                Spacer(minLength: 8)
                bodyMeasurementValue(observation, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func bodyMeasurementIdentity(
        _ observation: BodyCompositionProgressObservation
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: observation.kind.progressSymbol)
                .foregroundStyle(Color.coachIndigo)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(observation.kind.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(observation.sourceName) · \(observation.currentDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bodyMeasurementValue(
        _ observation: BodyCompositionProgressObservation,
        alignment: HorizontalAlignment
    ) -> some View {
        let loadUnit = appModel.trainingProfile.loadUnit
        return VStack(alignment: alignment, spacing: 3) {
            Text(bodyCompositionDisplayValue(
                value: observation.currentValue,
                kind: observation.kind,
                loadUnit: loadUnit
            ))
                .font(.headline.monospacedDigit())
            if let delta = observation.delta {
                Text("\(bodyCompositionDeltaDisplayValue(value: delta, kind: observation.kind, loadUnit: loadUnit)) in \(window.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("One reading in \(window.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bodyCompositionObservation(
        for kind: MetricKind
    ) -> BodyCompositionProgressObservation? {
        let today = Calendar.current.startOfDay(for: appModel.snapshot.generatedAt)
        let start = Calendar.current.date(
            byAdding: .day,
            value: -(window.rawValue - 1),
            to: today
        ) ?? today
        let matching = appModel.snapshot.samples.filter {
            $0.kind == kind
                && !$0.wasUserEntered
                && $0.value != nil
                && $0.endDate >= start
                && $0.endDate <= appModel.snapshot.generatedAt
        }
        let groups = Dictionary(grouping: matching, by: \.sourceIdentity)
        guard let selected = groups.values.max(by: { lhs, rhs in
            let lhsLatest = lhs.map(\.endDate).max() ?? .distantPast
            let rhsLatest = rhs.map(\.endDate).max() ?? .distantPast
            if lhsLatest == rhsLatest { return lhs.count < rhs.count }
            return lhsLatest < rhsLatest
        }) else { return nil }
        let ordered = selected.sorted { $0.endDate < $1.endDate }
        guard let current = ordered.last, let currentValue = current.value else { return nil }
        let earlier = ordered.dropLast().first?.value
        return BodyCompositionProgressObservation(
            kind: kind,
            currentValue: currentValue,
            delta: earlier.map { currentValue - $0 },
            currentDate: current.endDate,
            sourceName: current.sourceName
        )
    }

    @ViewBuilder
    private var trainingContent: some View {
        if sessions.isEmpty {
            EmptyState(
                symbol: "chart.xyaxis.line",
                title: "No training history yet",
                detail: "Complete a workout to see per-exercise strength trends."
            )
        } else {
            trainingTakeawayCard
            trainingSummary
            exerciseTrendCard
            exerciseHistory
            workoutHistory
        }
    }

    private var trainingTakeawayCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Training Summary", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                    .foregroundStyle(Color.coachIndigo)
                Text(trainingTakeaway)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Strength values are estimates from completed working sets, not tested one-rep maxes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trainingSummary: some View {
        let period = periodSessions
        let workingSets = period.flatMap(\.sets).filter { !$0.isWarmup }
        let trainingDays = Set(period.map { Calendar.current.startOfDay(for: $0.startedAt) }).count
        return VStack(spacing: 10) {
            SectionTitle(title: "Training in this period", subtitle: "Sessions and working sets; compare strength by exercise")
            LazyVGrid(columns: summaryColumns, spacing: 10) {
                MetricTile(label: "Sessions", value: "\(period.count)", detail: "Across \(trainingDays) training days", tint: .coachIndigo)
                MetricTile(label: "Working sets", value: "\(workingSets.count)", detail: "Warm-ups excluded", tint: .coachIndigo)
                MetricTile(label: "Training days", value: "\(trainingDays)", detail: "In this date range", tint: .coachIndigo)
            }
        }
    }

    private var trainingTakeaway: String {
        guard !periodSessions.isEmpty else {
            return "No completed workouts are recorded in this date range."
        }
        let points = selectedExercisePoints
        guard points.count >= 2,
              let first = points.first?.estimatedOneRepMax,
              let last = points.last?.estimatedOneRepMax,
              first > 0 else {
            let days = Set(periodSessions.map { Calendar.current.startOfDay(for: $0.startedAt) }).count
            return "You completed \(periodSessions.count) workout\(periodSessions.count == 1 ? "" : "s") across \(days) training day\(days == 1 ? "" : "s")."
        }
        let change = ((last - first) / first) * 100
        if abs(change) < 1 {
            return "Estimated strength for \(selectedExerciseName) is steady across this range."
        }
        return "Estimated strength for \(selectedExerciseName) is \(change > 0 ? "up" : "down") \(abs(change).formatted(.number.precision(.fractionLength(0...1))))% across this range."
    }

    private var exerciseTrendCard: some View {
        let points = selectedExercisePoints
        return CoachCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(
                    title: "Estimated Strength Trend",
                    subtitle: "Estimated 1RM from the best working set in each session"
                )

                Picker("Exercise", selection: $selectedExerciseKey) {
                    ForEach(exerciseOptions) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                if points.count < 3 {
                    EmptyState(
                        symbol: "dumbbell",
                        title: points.isEmpty ? "No sets in this range" : "Keep building this trend",
                        detail: points.isEmpty
                            ? "Choose a longer range or complete another working set for this exercise."
                            : "Complete one more session before Dayvera draws a meaningful trend line."
                    )
                } else {
                    Chart(points) { point in
                        LineMark(
                            x: .value("Session", point.date),
                            y: .value("Estimated one-rep max", point.estimatedOneRepMax)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(Color.coachIndigo)
                        PointMark(
                            x: .value("Session", point.date),
                            y: .value("Estimated one-rep max", point.estimatedOneRepMax)
                        )
                        .foregroundStyle(Color.coachIndigo)
                        .symbolSize(point.isPersonalBest ? 80 : 34)
                        .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue(
                            "Estimated one rep max \(formattedWeight(point.estimatedOneRepMax)); top set \(formattedWeight(point.weight)) for \(point.reps) reps"
                                + (point.rpe.map { " at RPE \(formattedRPE($0))" } ?? "")
                                + (point.isPersonalBest ? ", estimated best" : "")
                        )
                        if point.isPersonalBest {
                            PointMark(
                                x: .value("Personal best session", point.date),
                                y: .value("Personal best estimated one-rep max", point.estimatedOneRepMax)
                            )
                            .foregroundStyle(Color.coachMint)
                            .symbolSize(90)
                            .annotation(position: .top) {
                                Label("Estimated Best", systemImage: "star.fill")
                                    .font(.caption2.bold())
                                    .foregroundStyle(Color.primary)
                            }
                        }
                    }
                    .frame(height: 230)
                    .chartYAxis { AxisMarks(position: .leading) }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Estimated one-rep max trend for \(selectedExerciseName)")
                    .accessibilityValue("\(points.count) sessions in the selected \(window.rawValue)-day range. Estimated best \(formattedWeight(points.map(\.estimatedOneRepMax).max() ?? 0)).")

                    Text("Estimate uses Epley: weight × (1 + reps ÷ 30). Compare this trend only within the selected exercise; it is not a tested one-rep max.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var exerciseHistory: some View {
        VStack(spacing: 10) {
            SectionTitle(title: "Exercise history", subtitle: "Top working set per session")
            if selectedExercisePoints.isEmpty {
                Text("No history in this range.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(selectedExercisePoints.reversed()) { point in
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 10) {
                                exerciseHistoryIdentity(point)
                                exerciseEstimate(point, alignment: .leading)
                                    .padding(.leading, 36)
                            }
                        } else {
                            HStack(alignment: .top, spacing: 12) {
                                exerciseHistoryIdentity(point)
                                Spacer()
                                exerciseEstimate(point, alignment: .trailing)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.coachSurface, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var workoutHistory: some View {
        VStack(spacing: 10) {
            SectionTitle(title: "Workout history", subtitle: "Completed sessions in this period")
            if periodSessions.isEmpty {
                Text("No completed workouts in this range.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(periodSessions) { session in
                    VStack(alignment: .leading, spacing: 10) {
                        Group {
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 10) {
                                    workoutHistoryIdentity(session)
                                    Text(workoutReadinessText(session))
                                        .font(.caption.weight(.semibold))
                                        .padding(.leading, 48)
                                }
                            } else {
                                HStack(alignment: .top, spacing: 12) {
                                    workoutHistoryIdentity(session)
                                    Spacer(minLength: 8)
                                    Text(workoutReadinessText(session))
                                        .font(.caption.weight(.semibold))
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)

                        Divider()
                        workoutExportStatus(session)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.coachSurface, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    @ViewBuilder
    private func workoutExportStatus(_ session: WorkoutSessionRecord) -> some View {
        let isExporting = appModel.isExportingWorkout(session.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(
                    workoutExportLabel(session.healthExportState, isExporting: isExporting),
                    systemImage: workoutExportSymbol(session.healthExportState)
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if isExporting {
                    SwiftUI.ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }

            if session.healthExportState == .failed,
               let message = session.healthExportErrorMessage,
               !message.isEmpty {
                Text("Saved in Dayvera, but it couldn’t be added to Apple Health.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                DisclosureGroup("Technical details") {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .font(.caption2)
            } else if session.healthExportState == .pending, !isExporting {
                Text("Saved in Dayvera but not yet added to Apple Health. Try again.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if session.healthExportState == .unknown {
                Text("This workout was saved before export tracking was available, so its Apple Health status can’t be verified.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if (session.healthExportState == .pending || session.healthExportState == .failed), !isExporting {
                Button {
                    Task {
                        await appModel.retryStrengthWorkoutExport(session, in: modelContext)
                    }
                } label: {
                    Label("Retry export", systemImage: "arrow.clockwise")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Retries this saved workout with Apple Health")
            }
        }
    }

    private func workoutExportLabel(
        _ state: WorkoutHealthExportState,
        isExporting: Bool
    ) -> String {
        if isExporting { return "Exporting to Apple Health" }
        return switch state {
        case .unknown: "Apple Health status unavailable"
        case .pending: "Apple Health export pending"
        case .exported: "Exported to Apple Health"
        case .failed: "Apple Health export failed"
        }
    }

    private func workoutExportSymbol(_ state: WorkoutHealthExportState) -> String {
        switch state {
        case .unknown: "questionmark.circle"
        case .pending: "clock.arrow.circlepath"
        case .exported: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func exerciseHistoryIdentity(_ point: ExercisePerformancePoint) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: point.isPersonalBest ? "star.fill" : "circle.fill")
                .font(point.isPersonalBest ? .body : .system(size: 7))
                .foregroundStyle(point.isPersonalBest ? Color.coachMint : Color.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(point.date.shortDay).font(.subheadline.bold())
                    if point.isPersonalBest { Text("Estimated Best").font(.caption.bold()) }
                }
                Text(
                    "\(formattedWeight(point.weight)) × \(point.reps)"
                        + (point.rpe.map { " · RPE \(formattedRPE($0))" } ?? "")
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func exerciseEstimate(
        _ point: ExercisePerformancePoint,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(formattedWeight(point.estimatedOneRepMax))
                .font(.subheadline.bold().monospacedDigit())
            Text("estimated 1RM")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func workoutHistoryIdentity(_ session: WorkoutSessionRecord) -> some View {
        let hasReadiness = session.recordedReadinessScore != nil
        let readinessTint = hasReadiness ? session.readiness.color : Color.secondary
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: hasReadiness ? session.readiness.symbol : "questionmark.circle")
                .foregroundStyle(readinessTint)
                .frame(width: 36, height: 36)
                .background(readinessTint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.templateName).font(.headline)
                Text(session.modality == .strengthResistance
                     ? "\(session.startedAt.shortDay) · \(Int(session.durationMinutes)) min · \(session.sets.filter { !$0.isWarmup }.count) working sets"
                     : "\(session.startedAt.shortDay) · \(Int(session.durationMinutes)) min · \(session.modality.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func workoutReadinessText(_ session: WorkoutSessionRecord) -> String {
        guard let score = session.recordedReadinessScore else {
            return "Readiness not recorded"
        }
        return "Readiness \(score)"
    }

    private var summaryColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 145), spacing: 10)]
    }

    private var periodSessions: [WorkoutSessionRecord] {
        let today = Calendar.current.startOfDay(for: .now)
        let start = Calendar.current.date(byAdding: .day, value: -(window.rawValue - 1), to: today)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        return sessions.filter { $0.startedAt >= start && $0.startedAt < tomorrow }
    }

    private var exerciseOptions: [ExerciseProgressOption] {
        exerciseProgressOptions(from: sessions)
    }

    private var selectedExercisePoints: [ExercisePerformancePoint] {
        exercisePerformanceHistory(
            from: periodSessions,
            exerciseKey: selectedExerciseKey,
            displayedIn: appModel.trainingProfile.loadUnit
        )
    }

    private var selectedExerciseName: String {
        exerciseOptions.first(where: { $0.id == selectedExerciseKey })?.name ?? "selected exercise"
    }

    private func reconcileExerciseSelection() {
        guard !exerciseOptions.contains(where: { $0.id == selectedExerciseKey }) else { return }
        selectedExerciseKey = exerciseOptions.first?.id ?? ""
    }

    private func rangedPoints(_ signal: MetricTrendSeries) -> [MetricTrendPoint] {
        Array(signal.points.suffix(window.rawValue))
    }

    private func sleepChartAccessibility(_ summary: MetricTrendSummary) -> String {
        "Average \(summary.average?.hoursMinutes ?? "unavailable"), \(summary.completenessText) recorded, \(sleepDelta(summary.deltaFromReference)) relative to target."
    }

    private func sleepDelta(_ delta: Double?) -> String {
        guard let delta else { return "—" }
        let prefix = delta > 0 ? "+" : (delta < 0 ? "−" : "")
        return "\(prefix)\(abs(delta).hoursMinutes)"
    }

    private func timingVariabilityText(_ variability: SleepTimingVariability) -> String {
        guard let bedtime = variability.bedtimeMinutes, let wake = variability.wakeTimeMinutes else {
            return "Sleep timing variability needs at least two same-source nights."
        }
        return "Timing variability across \(variability.recordedNights) same-source nights: bedtime ±\(Int(bedtime.rounded())) min · wake ±\(Int(wake.rounded())) min."
    }

    private func formattedWeight(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(appModel.trainingProfile.loadUnit.symbol)"
    }

    private func formattedRPE(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

private struct BiometricDeviationCard: View {
    let signal: MetricTrendSeries
    let window: TrendWindow

    var body: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(signal.kind.title).font(.headline)
                Label(signal.statusText, systemImage: signal.status.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                Text("Deviation from 21-day same-source median")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if chartPoints.isEmpty {
                    Text("Baseline still developing")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
                } else {
                    Chart {
                        ForEach(chartPoints) { point in
                            if let deviation = point.deviationPercentage, let segmentID = point.segmentID {
                                LineMark(
                                    x: .value("Day", point.date),
                                    y: .value("Deviation percent", deviation),
                                    series: .value("Recorded run", segmentID)
                                )
                                .interpolationMethod(.linear)
                                .foregroundStyle(Color.coachIndigo)
                                PointMark(
                                    x: .value("Day", point.date),
                                    y: .value("Deviation percent", deviation)
                                )
                                .foregroundStyle(Color.coachIndigo)
                                .symbolSize(22)
                                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue("\(deviation.formatted(.number.precision(.fractionLength(0...1)).sign(strategy: .always()))) percent from median")
                            }
                        }
                        RuleMark(y: .value("Same-source median", 0))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Color.secondary)
                    }
                    .frame(height: 160)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let percent = value.as(Double.self) { Text("\(Int(percent))%") }
                            }
                        }
                    }
                    .chartXAxis(.hidden)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(signal.kind.title) deviation over \(window.rawValue) days")
                    .accessibilityValue(accessibilitySummary)
                }
                Text("\(signal.sourceName ?? "No source") · \(signal.freshnessText) · \(signal.summary(for: window).completenessText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chartPoints: [MetricTrendPoint] {
        Array(signal.points.suffix(window.rawValue)).filter { $0.deviationPercentage != nil }
    }

    private var accessibilitySummary: String {
        guard let current = signal.currentValue, let reference = signal.referenceValue else {
            return "No comparable values available."
        }
        return "Current \(Int(current.rounded())) \(signal.kind.unit), median \(Int(reference.rounded())) \(signal.kind.unit), \(signal.summary(for: window).completenessText) recorded."
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
