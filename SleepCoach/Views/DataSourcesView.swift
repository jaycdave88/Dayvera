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

            observedSources
            confidenceExplanation
        }
        .navigationTitle("Data & Sources")
        .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
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
                label: "Recommendation confidence",
                value: appModel.snapshot.readinessAvailable
                    ? appModel.snapshot.confidence.title
                    : "Unavailable"
            )
            DataValueRow(label: "Current selected inputs", value: selectedInputSummary)

            if usedSignalCount == 0 {
                Label("Choose at least one signal to create a workout recommendation.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.coachAmber)
            }

            healthAction
        } header: {
            Text("Health data")
        } footer: {
            Text("Sleep Coach can verify received samples, not denied read access or sensor accuracy.")
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
                        ProgressView()
                        Text("Refreshing…")
                    }
                } else {
                    Label("Refresh Apple Health", systemImage: "arrow.clockwise")
                }
            }
            .disabled(appModel.isRefreshing)
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
            Text("Signals")
        } footer: {
            Text("Tap a signal to choose what appears on Today, whether it influences the workout recommendation, and which observed source to use. Tap Edit to reorder Today.")
        }
    }

    private var queryIssues: some View {
        Section("Health data needs attention") {
            ForEach(appModel.healthQueryFailures) { failure in
                VStack(alignment: .leading, spacing: 4) {
                    Label(failure.kind?.title ?? "Apple Health query", systemImage: "exclamationmark.triangle.fill")
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
                ForEach(appModel.diagnostics.filter { MetricKind.decisionMetrics.contains($0.kind) }) { item in
                    SourceObservationRow(
                        diagnostic: item,
                        usedNow: trend(for: item.kind).sourceBundleIdentifier == item.bundleIdentifier
                    )
                }
            }
        } header: {
            Text("Sources found in Apple Health")
        } footer: {
            Text("Overlapping sources are never averaged. “Used now” means that source currently supplies the displayed trend and any enabled recommendation input.")
        }
    }

    private var confidenceExplanation: some View {
        Section("What the labels mean") {
            Label("Source status", systemImage: "point.3.connected.trianglepath.dotted")
            Text("Whether the selected source is available, fresh, or using your permitted fallback.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label("Data coverage", systemImage: "calendar.badge.clock")
            Text("How many days contain a usable value and how much same-source history supports the baseline.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label("Recommendation confidence", systemImage: "checkmark.seal")
            Text("How complete the enabled inputs and their history are. It is not a clinical rating or a claim about wearable accuracy.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
        return "\(current) of \(enabled.count) current"
    }

    private var healthStateSymbol: String {
        switch appModel.healthConnectionState {
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
        switch appModel.healthConnectionState {
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
                StateTag(text: preference.shownOnToday ? "On Today" : "Off Today")
                StateTag(text: preference.usedInRecommendation ? "In recommendation" : "Not in recommendation")
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
            Toggle("Use in workout recommendation", isOn: preferenceBinding(\.usedInRecommendation))
        } header: {
            Text("Display & recommendation")
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
        Section("Source status") {
            DataValueRow(label: "Used now", value: trend.sourceName ?? "No readable source")
            DataValueRow(label: "Selection", value: sourceHealthLabel)
            if let failure = queryFailure {
                Label("Query failed: \(failure.message)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.coachAmber)
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
        if queryFailure != nil { return "Query failed" }
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
        let preferred = metric == .sleep ? "Eight Sleep" : "Hume"
        return "Automatic prefers fresh \(preferred) data, then uses the freshest observed source. This changes Sleep Coach’s calculation, not Apple Health permissions."
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

private struct SourceObservationRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let diagnostic: SourceDiagnostic
    let usedNow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    sourceTitle
                    if usedNow { StateTag(text: "Used now", emphasized: true) }
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    sourceTitle
                    Spacer()
                    if usedNow { StateTag(text: "Used now", emphasized: true) }
                }
            }
            Text("\(diagnostic.kind.title) · \(diagnostic.sampleCount) samples")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Latest \(diagnostic.latestSample?.formatted(date: .abbreviated, time: .shortened) ?? "unknown")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(diagnostic.bundleIdentifier)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var sourceTitle: some View {
        Text(diagnostic.vendorLabel)
            .font(.headline)
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
        default: "chart.xyaxis.line"
        }
    }
}
