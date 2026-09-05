import SwiftUI

struct DataSourcesView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var appModel: AppModel
    @State private var showingDebugSignal = false
    @State private var debugSignal: MetricKind?
    @State private var handledDebugRoute = false

    var body: some View {
        Form {
            healthOverview
            signalControls

            if !appModel.healthQueryFailures.isEmpty {
                queryIssues
            }

            safetyChecks
            trainingContext
            bodyCompositionContext
            providerMatrix
            observedCoverage
            observedSources
            confidenceExplanation
        }
        .navigationTitle("Health Data & Sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .navigationDestination(isPresented: $showingDebugSignal) {
            if let debugSignal {
                SignalSourceSettingsView(metric: debugSignal)
            }
        }
        .task {
            #if DEBUG
            guard !handledDebugRoute,
                  let argument = ProcessInfo.processInfo.arguments.first(where: {
                      $0.hasPrefix("--show-signal-source=")
                  }) else { return }
            handledDebugRoute = true
            let rawValue = String(argument.dropFirst("--show-signal-source=".count))
            debugSignal = MetricKind(rawValue: rawValue)
            await Task.yield()
            showingDebugSignal = debugSignal != nil
            #endif
        }
    }

    private var healthOverview: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: healthStateSymbol)
                    .font(.title3)
                    .foregroundStyle(healthStateColor)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Health")
                        .font(.headline)
                    Text(appModel.healthStatus)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            DataValueRow(
                label: "Guidance confidence",
                value: appModel.snapshot.readinessAvailable
                    ? appModel.snapshot.confidence.title
                    : "Unavailable"
            )
            DataValueRow(label: "Signals up to date", value: selectedInputSummary)

            if usedSignalCount == 0 {
                Label("Choose at least one signal to add recovery context to workout recommendations.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.coachAmber)
            }

            if appModel.healthAccessReviewRecommended {
                Label(
                    "Review Health access to include expanded recovery, activity, and body-measurement categories.",
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(Color.coachAmber)
            }

            healthAction
        } header: {
            Text("Health data")
        } footer: {
            Text("Dayvera can verify received samples, not denied read access or sensor accuracy.")
        }
    }

    @ViewBuilder
    private var healthAction: some View {
        if appModel.healthConnectionState.canRequestAccess {
            Button("Connect Apple Health", systemImage: "heart.fill") {
                Task { await appModel.connectHealth() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.coachIndigo)
            .frame(minHeight: 44)
        } else {
            Button {
                Task { await appModel.refresh() }
            } label: {
                if appModel.isRefreshing {
                    HStack {
                        SwiftUI.ProgressView()
                        Text("Refreshing…")
                    }
                } else {
                    Label("Check for New Data", systemImage: "arrow.clockwise")
                }
            }
            .disabled(appModel.isRefreshing)
            .frame(minHeight: 44)

            Button("Review Health Access", systemImage: "checklist") {
                Task { await appModel.connectHealth() }
            }
            .frame(minHeight: 44)
        }
    }

    private var signalControls: some View {
        Section {
            ForEach(appModel.preferences.signalOrder, id: \.self) { metric in
                NavigationLink {
                    SignalSourceSettingsView(metric: metric)
                } label: {
                    SignalControlRow(
                        preference: appModel.preferences.decisionPreference(for: metric),
                        trend: trend(for: metric)
                    )
                }
            }
            .onMove(perform: moveSignals)
        } header: {
            Text("Recovery Signals")
        } footer: {
            Text("Tap a signal to choose what appears on Today, whether it influences the workout recommendation, and which observed source to use. Tap Edit to reorder Today.")
        }
    }

    private var queryIssues: some View {
        Section("Health data needs attention") {
            ForEach(appModel.healthQueryFailures) { failure in
                VStack(alignment: .leading, spacing: 4) {
                    Label("Couldn’t update \(failure.kind?.title ?? "Apple Health data")", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.coachAmber)
                    Text("This signal could not be updated. Refresh, then review its sharing permission in Apple Health if the problem continues.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DisclosureGroup("Technical details") {
                        Text(failure.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(failure.typeIdentifier)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var observedSources: some View {
        Section {
            if appModel.diagnostics.isEmpty {
                Text("No readable samples yet. In Eight Sleep and Hume, enable Apple Health sharing, then refresh after those apps finish syncing.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appModel.diagnostics) { item in
                    SourceObservationRow(
                        diagnostic: item,
                        usedNow: selectedSourceBundle(for: item.kind) == item.bundleIdentifier
                    )
                }
            }
        } header: {
            Text("Sources found in Apple Health")
        } footer: {
            Text("Overlapping sources are never mixed into a personal baseline. “Using” identifies a selected core source; safety checks also show their same-source selection above.")
        }
    }

    private var safetyChecks: some View {
        Section {
            DataValueRow(label: "Recommendation effect", value: safetyEffectText)

            ForEach(appModel.snapshot.safetyGate.signals) { signal in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Label(signal.kind.title, systemImage: signal.kind.signalSymbol)
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Text(signal.state == .outlier ? "Check" : "Neutral")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(signal.state == .outlier ? Color.coachAmber : .secondary)
                    }
                    Text(signal.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let current = signal.currentValue {
                        Text(safetyValueText(signal, current: current))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let sourceName = signal.sourceName {
                        Text("Source: \(sourceName)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Safety-only checks")
        } footer: {
            Text("A check needs a fresh value and at least 14 nights in a 21-day same-source baseline. One outlier pauses progression; two or more cap readiness at Moderate and reduce the pre-check volume by 10%. Missing, stale, and early-baseline signals are neutral. These signals never raise readiness and are not a medical diagnosis.")
        }
    }

    private var trainingContext: some View {
        let context = appModel.snapshot.trainingContext
        return Section {
            DataValueRow(
                label: "Yesterday’s active energy",
                value: observedValue(context.previousDayActiveEnergy, unit: MetricKind.activeEnergy.unit)
            )
            DataValueRow(
                label: "Yesterday’s exercise",
                value: observedValue(context.previousDayExerciseMinutes, unit: MetricKind.exerciseMinutes.unit)
            )
            DataValueRow(
                label: "Yesterday’s steps",
                value: observedValue(context.previousDaySteps, unit: MetricKind.steps.unit)
            )
            DataValueRow(
                label: "Workouts · last 7 days",
                value: context.workoutsLastSevenDays == 0
                    ? "No samples observed"
                    : "\(context.workoutsLastSevenDays)"
            )
            DataValueRow(
                label: "Workout time · last 7 days",
                value: observedValue(context.workoutMinutesLastSevenDays, unit: MetricKind.workout.unit)
            )
        } header: {
            Text("Training context")
        } footer: {
            Text("These activity records provide context only; they are not folded into a proprietary recovery score.")
        }
    }

    private var bodyCompositionContext: some View {
        Section {
            ForEach(MetricKind.bodyCompositionMetrics, id: \.self) { metric in
                let sample = latestObservedSample(for: metric)
                VStack(alignment: .leading, spacing: 3) {
                    DataValueRow(
                        label: metric.title,
                        value: bodyCompositionValue(sample, kind: metric)
                    )
                    if let sample {
                        Text("Latest observed from \(sample.sourceName)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Body composition context")
        } footer: {
            Text("Shows standard body measurements actually received from Apple Health. These values are progress context only and never change readiness, safety checks, or today’s workout. Proprietary Hume measurements without an Apple Health equivalent remain in Hume.")
        }
    }

    private var observedCoverage: some View {
        Section {
            ForEach(HealthKitService.observedCoverage(from: appModel.snapshot.samples)) { coverage in
                MetricCoverageRow(coverage: coverage)
            }
        } header: {
            Text("Observed coverage")
        } footer: {
            Text("Coverage reports only readable samples received in the fetched window. “No samples observed” does not mean access was denied; Apple Health intentionally does not disclose read denial.")
        }
    }

    private var providerMatrix: some View {
        Section {
            ForEach(providerSummaries) { summary in
                ProviderObservationRow(summary: summary)
            }
        } header: {
            Text("Provider observations")
        } footer: {
            Text("These rows report only samples actually observed in Apple Health. “Not received” is not a claim about device support, sensor availability, or denied access.")
        }
    }

    private var providerSummaries: [ProviderObservationSummary] {
        let definitions: [(name: String, terms: [String])] = [
            ("Eight Sleep", ["eight"]),
            ("Hume", ["hume", "fittrack"]),
            ("Apple Watch", ["apple watch", "watch"])
        ]
        return definitions.map { definition in
            let matches = appModel.diagnostics.filter { diagnostic in
                let deviceText = diagnostic.devices.flatMap {
                    [$0.manufacturer, $0.model].compactMap { $0 }
                }.joined(separator: " ")
                let searchable = [
                    diagnostic.sourceName,
                    diagnostic.bundleIdentifier,
                    diagnostic.sourceProductType,
                    deviceText
                ].compactMap { $0 }.joined(separator: " ").lowercased()
                return definition.terms.contains { searchable.contains($0) }
            }
            return ProviderObservationSummary(
                name: definition.name,
                sampleCount: matches.reduce(0) { $0 + $1.sampleCount },
                metrics: MetricKind.healthReadMetrics.filter(Set(matches.map(\.kind)).contains),
                latestSample: matches.compactMap(\.latestSample).max(),
                referenceDate: appModel.snapshot.generatedAt
            )
        }
    }

    private var confidenceExplanation: some View {
        Section("What the labels mean") {
            Label("Current Source", systemImage: "point.3.connected.trianglepath.dotted")
            Text("Whether the selected source is available, fresh, or using your permitted fallback.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label("Data coverage", systemImage: "calendar.badge.clock")
            Text("How many days contain a usable value and how much same-source history supports the baseline.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label("Guidance Confidence", systemImage: "checkmark.seal")
            Text("How complete the enabled inputs and their history are. It is not a clinical rating or a claim about wearable accuracy.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var safetyEffectText: String {
        let gate = appModel.snapshot.safetyGate
        if gate.capsReadinessAtModerate {
            return "Readiness capped · volume × 90% · progression paused"
        }
        if gate.blocksProgression {
            return "Core readiness unchanged · progression paused"
        }
        return "No safety-only restriction"
    }

    private func safetyValueText(
        _ signal: SafetySignalEvaluation,
        current: Double
    ) -> String {
        let value = current.formatted(.number.precision(.fractionLength(0...2)))
        guard let baseline = signal.baselineMedian else {
            return "Latest \(value) \(signal.kind.unit) · no established baseline"
        }
        let baselineText = baseline.formatted(.number.precision(.fractionLength(0...2)))
        return "Latest \(value) \(signal.kind.unit) · baseline \(baselineText) · \(signal.baselineNightCount) nights"
    }

    private func observedValue(_ value: Double?, unit: String) -> String {
        guard let value else { return "No samples observed" }
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }

    private func latestObservedSample(for kind: MetricKind) -> MetricSample? {
        appModel.snapshot.samples
            .filter { $0.kind == kind && !$0.wasUserEntered && $0.value != nil }
            .max { $0.endDate < $1.endDate }
    }

    private func bodyCompositionValue(_ sample: MetricSample?, kind: MetricKind) -> String {
        guard let value = sample?.value else { return "No samples observed" }
        return bodyCompositionDisplayValue(
            value: value,
            kind: kind,
            loadUnit: appModel.trainingProfile.loadUnit
        )
    }

    private var usedSignalCount: Int {
        appModel.preferences.decisionMetricPreferences.filter(\.usedInRecommendation).count
    }

    private var selectedInputSummary: String {
        let enabled = appModel.preferences.decisionMetricPreferences.filter(\.usedInRecommendation)
        guard !enabled.isEmpty else { return "None enabled" }
        let current = enabled.filter { preference in
            let signal = trend(for: preference.metric)
            return signal.currentValue != nil && signal.freshness != .stale
        }.count
        return "\(current) of \(enabled.count) up to date"
    }

    private var healthStateSymbol: String {
        if appModel.healthBackgroundDeliveryFailure != nil {
            return "exclamationmark.triangle.fill"
        }
        return switch appModel.healthConnectionState {
        case .dataReceived(_), .demoData:
            "checkmark.circle.fill"
        case .partialData(_, _), .noReadableSamples, .refreshFailed:
            "exclamationmark.triangle.fill"
        case .accessRequested:
            "clock.fill"
        case .notRequested:
            "heart.circle"
        }
    }

    private var healthStateColor: Color {
        if appModel.healthBackgroundDeliveryFailure != nil {
            return .primary
        }
        return switch appModel.healthConnectionState {
        case .dataReceived(_), .demoData:
            .coachMint
        case .partialData(_, _), .noReadableSamples, .refreshFailed:
            .coachAmber
        case .accessRequested, .notRequested:
            .coachIndigo
        }
    }

    private func trend(for metric: MetricKind) -> MetricTrendSeries {
        switch metric {
        case .sleep: appModel.snapshot.sleepTrend
        case .heartRateVariability: appModel.snapshot.hrvTrend
        case .restingHeartRate: appModel.snapshot.restingHeartRateTrend
        default: .empty(kind: metric, referenceLabel: "Reference")
        }
    }

    private func selectedSourceBundle(for metric: MetricKind) -> String? {
        if let safety = appModel.snapshot.safetyGate.signals.first(where: { $0.kind == metric }) {
            return safety.sourceBundleIdentifier
        }
        return trend(for: metric).sourceBundleIdentifier
    }

    private func moveSignals(from offsets: IndexSet, to destination: Int) {
        var updated = appModel.preferences
        updated.signalOrder.move(fromOffsets: offsets, toOffset: destination)
        appModel.preferences = updated
    }
}

private struct SignalControlRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let preference: DecisionMetricPreference
    let trend: MetricTrendSeries

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        layout {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: preference.metric.signalSymbol)
                    .foregroundStyle(Color.coachIndigo)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preference.metric.title)
                        .font(.headline)
                    Text(trend.sourceName ?? "No source selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(trend.freshnessText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                StateTag(text: preference.shownOnToday ? "Shown on Today" : "Hidden from Today")
                StateTag(text: preference.usedInRecommendation ? "Used for guidance" : "Not used for guidance")
            }
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(preference.shownOnToday ? "Shown on Today" : "Hidden from Today"), \(preference.usedInRecommendation ? "used in recommendation" : "not used in recommendation"), \(trend.freshnessText)")
    }
}

private struct SignalSourceSettingsView: View {
    private static let automaticSourceID = "__automatic__"

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var appModel: AppModel
    let metric: MetricKind

    var body: some View {
        Form {
            displayAndRecommendation
            sourceSelection
            sourceHealth
            dataCoverage

            if !sources.isEmpty {
                sourceOptions
            }

            metricExplanation
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var displayAndRecommendation: some View {
        Section {
            Toggle("Show on Today", isOn: preferenceBinding(\.shownOnToday))
            Toggle("Use for workout guidance", isOn: preferenceBinding(\.usedInRecommendation))
        } header: {
            Text("Visibility & Guidance")
        } footer: {
            Text("A signal can stay visible without affecting your workout recommendation, or influence the recommendation while hidden from Today.")
        }
    }

    private var sourceSelection: some View {
        Section {
            Picker("Source", selection: sourceSelectionBinding) {
                Text("Automatic (recommended)")
                    .tag(Self.automaticSourceID)
                ForEach(sources) { source in
                    Text(sourceOptionTitle(source))
                        .tag(source.bundleIdentifier)
                }
                if let requested = preference.requestedBundleIdentifier,
                   !sources.contains(where: { $0.bundleIdentifier == requested }) {
                    Text("Unavailable selection")
                        .tag(requested)
                }
            }
            .pickerStyle(.navigationLink)

            if preference.sourceMode == .manual {
                Toggle("Fallback if unavailable", isOn: preferenceBinding(\.allowAutomaticFallback))
            }
        } header: {
            Text("Source preference")
        } footer: {
            Text(sourcePreferenceExplanation)
        }
    }

    private var sourceHealth: some View {
        Section("Current Source") {
            DataValueRow(label: "Using", value: trend.sourceName ?? "No readable source")
            DataValueRow(label: "Source Choice", value: sourceHealthLabel)
            if let failure = queryFailure {
                Label("Apple Health query unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.primary)
                Text("Refresh after checking this signal’s Apple Health access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DisclosureGroup("Technical details") {
                    Text(failure.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .font(.caption)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: sourceHealthSymbol)
                        .foregroundStyle(sourceHealthColor)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    Text(trend.sourceHealth.reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var dataCoverage: some View {
        Section("Data coverage") {
            DataValueRow(label: "Freshness", value: trend.freshnessText)
            DataValueRow(label: "Last sample", value: latestSampleText)
            DataValueRow(label: "Last 7 days", value: trend.sevenDaySummary.completenessText)
            DataValueRow(label: "Last 28 days", value: trend.twentyEightDaySummary.completenessText)
            DataValueRow(label: baselineLabel, value: "\(trend.baselineDayCount) days")
        }
    }

    private var sourceOptions: some View {
        Section("Observed for \(metric.title)") {
            ForEach(sources) { source in
                SourceObservationRow(
                    diagnostic: source,
                    usedNow: trend.sourceBundleIdentifier == source.bundleIdentifier
                )
            }
        }
    }

    private var metricExplanation: some View {
        Section("How it is used") {
            Text(metricUseExplanation)
                .font(.subheadline)
            Text("The source identifies the app or device that wrote a sample to Apple Health. It is provenance, not a measurement-accuracy score.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var preference: DecisionMetricPreference {
        appModel.preferences.decisionPreference(for: metric)
    }

    private var trend: MetricTrendSeries {
        switch metric {
        case .sleep: appModel.snapshot.sleepTrend
        case .heartRateVariability: appModel.snapshot.hrvTrend
        case .restingHeartRate: appModel.snapshot.restingHeartRateTrend
        default: .empty(kind: metric, referenceLabel: "Reference")
        }
    }

    private var sources: [SourceDiagnostic] {
        appModel.diagnostics
            .filter { $0.kind == metric }
            .sorted {
                if $0.vendorLabel == $1.vendorLabel {
                    return $0.bundleIdentifier < $1.bundleIdentifier
                }
                return $0.vendorLabel < $1.vendorLabel
            }
    }

    private var queryFailure: HealthQueryFailure? {
        appModel.healthQueryFailures.first { $0.kind == metric }
    }

    private var selectedDiagnostic: SourceDiagnostic? {
        sources.first { $0.bundleIdentifier == trend.sourceBundleIdentifier }
    }

    private var latestSampleText: String {
        guard let date = selectedDiagnostic?.latestSample ?? trend.currentDate else { return "No sample" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var baselineLabel: String {
        metric == .sleep ? "Recorded sleep history" : "Same-source baseline"
    }

    private var sourceHealthLabel: String {
        if queryFailure != nil { return "Couldn’t update" }
        if trend.sourceHealth.state == .unavailable || trend.freshness == .missing { return "Unavailable" }
        if trend.freshness == .stale { return "Stale" }
        switch trend.sourceHealth.state {
        case .automatic: return "Automatic"
        case .manual: return "Manual"
        case .fallback: return "Fallback"
        case .unavailable: return "Unavailable"
        }
    }

    private var sourceHealthSymbol: String {
        if queryFailure != nil || trend.freshness == .stale {
            return "exclamationmark.triangle.fill"
        }
        switch trend.sourceHealth.state {
        case .automatic, .manual: return "checkmark.circle.fill"
        case .fallback: return "arrow.triangle.branch"
        case .unavailable: return "questionmark.circle"
        }
    }

    private var sourceHealthColor: Color {
        if queryFailure != nil || trend.freshness == .stale {
            return .coachAmber
        }
        switch trend.sourceHealth.state {
        case .automatic, .manual: return .coachMint
        case .fallback: return .coachAmber
        case .unavailable: return .secondary
        }
    }

    private var metricUseExplanation: String {
        switch metric {
        case .sleep:
            "Sleep duration is compared with your personal sleep target and can constrain training volume after a short night. Sleep timing also helps plan bedtime and wake time."
        case .heartRateVariability:
            "HRV is compared with your recent 21-day same-source median. The baseline needs repeated days before the comparison becomes stable."
        case .restingHeartRate:
            "Resting heart rate is compared with your recent 21-day same-source median. A higher-than-usual value can reduce the recommendation."
        default:
            "This signal is shown for context."
        }
    }

    private var sourcePreferenceExplanation: String {
        "Automatic ranks usable freshness first, then observed-day coverage, then the latest sample; vendor name is only a tie-breaker. This changes Dayvera’s calculation, not Apple Health permissions."
    }

    private var sourceSelectionBinding: Binding<String> {
        Binding(
            get: {
                preference.sourceMode == .automatic
                    ? Self.automaticSourceID
                    : (preference.requestedBundleIdentifier ?? Self.automaticSourceID)
            },
            set: { newValue in
                mutatePreference { preference in
                    if newValue == Self.automaticSourceID {
                        preference.sourceMode = .automatic
                        preference.manualSourceBundleIdentifier = nil
                    } else {
                        preference.sourceMode = .manual
                        preference.manualSourceBundleIdentifier = newValue
                    }
                }
            }
        )
    }

    private func preferenceBinding<Value>(
        _ keyPath: WritableKeyPath<DecisionMetricPreference, Value>
    ) -> Binding<Value> {
        Binding(
            get: { preference[keyPath: keyPath] },
            set: { value in
                mutatePreference { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func mutatePreference(
        _ mutation: (inout DecisionMetricPreference) -> Void
    ) {
        var updated = appModel.preferences
        guard let index = updated.decisionMetricPreferences.firstIndex(where: { $0.metric == metric }) else {
            return
        }
        mutation(&updated.decisionMetricPreferences[index])
        appModel.preferences = updated
    }

    private func sourceOptionTitle(_ source: SourceDiagnostic) -> String {
        let duplicateLabels = sources.filter { $0.vendorLabel == source.vendorLabel }.count > 1
        return duplicateLabels
            ? "\(source.vendorLabel) · \(source.sourceName)"
            : source.vendorLabel
    }
}

private struct MetricCoverageRow: View {
    let coverage: MetricObservedCoverage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: coverage.kind.signalSymbol)
                .foregroundStyle(coverage.hasObservedSamples ? Color.coachMint : .secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(coverage.kind.title)
                    .font(.subheadline.weight(.semibold))
                if coverage.hasObservedSamples {
                    Text("\(coverage.sampleCount) samples · \(coverage.observedDayCount) observed days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(coverage.sourceCount) sources · \(coverage.deviceCount) identified devices")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("No readable samples observed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let latest = coverage.latestSample {
                Text(latest, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct SourceObservationRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let diagnostic: SourceDiagnostic
    let usedNow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    sourceTitle
                    if usedNow { StateTag(text: "Using", emphasized: true) }
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    sourceTitle
                    Spacer()
                    if usedNow { StateTag(text: "Using", emphasized: true) }
                }
            }
            Text("\(diagnostic.kind.title) · \(diagnostic.sampleCount) samples across \(diagnostic.observedDayCount) days")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Latest \(diagnostic.latestSample?.formatted(date: .abbreviated, time: .shortened) ?? "unknown")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(diagnostic.bundleIdentifier)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            if let productType = diagnostic.sourceProductType {
                Text("Product type: \(productType)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            if diagnostic.userEnteredSampleCount > 0 {
                Text("\(diagnostic.userEnteredSampleCount) user-entered samples · excluded from automatic health guidance")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if diagnostic.devices.isEmpty {
                Text("Device details not supplied with these samples")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(diagnostic.devices, id: \.self) { device in
                    Text(device.detailText.map { "Device: \(device.displayName) · \($0)" }
                        ?? "Device: \(device.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var sourceTitle: some View {
        Text(diagnostic.vendorLabel)
            .font(.headline)
    }
}

private struct ProviderObservationSummary: Identifiable {
    enum Status: String {
        case receivedRecently = "Received recently"
        case previouslyReceived = "Previously received"
        case notReceived = "Not received"
    }

    var id: String { name }
    let name: String
    let sampleCount: Int
    let metrics: [MetricKind]
    let latestSample: Date?
    let status: Status

    init(
        name: String,
        sampleCount: Int,
        metrics: [MetricKind],
        latestSample: Date?,
        referenceDate: Date
    ) {
        self.name = name
        self.sampleCount = sampleCount
        self.metrics = metrics
        self.latestSample = latestSample
        if let latestSample {
            status = latestSample >= referenceDate.addingTimeInterval(-72 * 3600)
                ? .receivedRecently
                : .previouslyReceived
        } else {
            status = .notReceived
        }
    }
}

private struct ProviderObservationRow: View {
    let summary: ProviderObservationSummary

    @ViewBuilder
    var body: some View {
        if summary.metrics.isEmpty {
            providerLabel
                .accessibilityElement(children: .combine)
        } else {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(summary.metrics, id: \.self) { metric in
                        Label(metric.title, systemImage: "checkmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            } label: {
                providerLabel
            }
            .accessibilityHint("Shows the metric types actually received from this provider")
        }
    }

    private var providerLabel: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: summary.status == .receivedRecently
                ? "checkmark.circle.fill"
                : "clock.badge.questionmark")
                .foregroundStyle(summary.status == .receivedRecently ? Color.coachMint : .secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.name)
                    .font(.subheadline.weight(.semibold))
                Text(summary.status.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(summary.sampleCount == 0
                    ? "0 observed samples"
                    : "\(summary.sampleCount) samples · \(summary.metrics.count) metric types")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if let latestSample = summary.latestSample {
                Text(latestSample, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DataValueRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let label: String
    let value: String

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.subheadline)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            LabeledContent(label, value: value)
        }
    }
}

private struct StateTag: View {
    let text: String
    var emphasized = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(emphasized ? Color.coachIndigo : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                (emphasized ? Color.coachIndigo : Color.secondary)
                    .opacity(0.12),
                in: Capsule()
            )
    }
}

private extension MetricKind {
    var signalSymbol: String {
        switch self {
        case .sleep: "bed.double.fill"
        case .heartRateVariability: "waveform.path.ecg"
        case .restingHeartRate: "heart.fill"
        case .heartRate: "heart.text.square.fill"
        case .respiratoryRate: "lungs.fill"
        case .oxygenSaturation: "drop.fill"
        case .sleepingWristTemperature, .bodyTemperature: "thermometer.medium"
        case .bodyMass: "scalemass.fill"
        case .bodyFatPercentage: "percent"
        case .leanBodyMass: "figure.strengthtraining.traditional"
        case .bodyMassIndex: "chart.xyaxis.line"
        case .activeEnergy: "flame.fill"
        case .steps: "figure.walk"
        case .exerciseMinutes: "timer"
        case .workout: "dumbbell.fill"
        }
    }
}
