import SwiftData
import SwiftUI

/// Turns the normalized daily state into a concrete, validated workout. Health
/// signals inform the envelope; the deterministic planner owns every prescription.
struct TodayWorkoutRecommendationView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \WorkoutSessionRecord.startedAt, order: .reverse) private var sessions: [WorkoutSessionRecord]
    @ObservedObject private var catalogStore = ExerciseCatalogStore.shared

    @State private var availableMinutes = 45
    @State private var preferredFocus: TrainingFocus?
    @State private var plannedEffort: PlannedEffort = .asPlanned
    @State private var trainingState: DailyTrainingState?
    @State private var candidates: WorkoutPlanCandidates?
    @State private var selectedCandidate: WorkoutPlanCandidate?
    @State private var explanation = ""
    @State private var isPersonalized = false
    @State private var personalizationStatusText: String?
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var selectionRevision = 0
    @State private var showingAdjustments = false
    @State private var showingAlternatives = false
    @State private var showingDetails = false
    @State private var showingActiveWorkoutAlert = false
    @State private var activeWorkout: WorkoutTemplateRecord?
    @State private var appliedDebugRoute = false

    private let stateBuilder = DailyTrainingStateBuilder()
    private let planner = WorkoutPlanningEngine()
    private let draftStore = ActiveWorkoutDraftStore()
    private let onOpenTrain: () -> Void
    private static let personalizer = FoundationModelWorkoutPersonalizer()

    init(onOpenTrain: @escaping () -> Void) {
        self.onOpenTrain = onOpenTrain
    }

    var body: some View {
        Group {
            if let selectedCandidate, let trainingState {
                recommendationCard(selectedCandidate, state: trainingState)
            } else if isGenerating {
                loadingCard
            } else {
                unavailableCard
            }
        }
        .task { await catalogStore.load() }
        .task(id: recommendationInput) { await prepareRecommendation() }
        .sheet(isPresented: $showingAdjustments) {
            WorkoutAdjustmentSheet(
                minutes: availableMinutes,
                equipmentProfileID: appModel.trainingProfile.activeEquipmentProfileID,
                focus: preferredFocus,
                effort: plannedEffort,
                profiles: appModel.trainingProfile.equipmentProfiles
            ) { minutes, profileID, focus, effort in
                availableMinutes = minutes
                appModel.trainingProfile.activeEquipmentProfileID = profileID
                preferredFocus = focus
                plannedEffort = effort
            }
        }
        .sheet(isPresented: $showingAlternatives) {
            if let candidates {
                WorkoutAlternativesSheet(
                    candidates: candidates,
                    selectedID: selectedCandidate?.id
                ) { candidate in selectAlternative(candidate) }
            }
        }
        .sheet(isPresented: $showingDetails) {
            if let selectedCandidate, let trainingState {
                WorkoutPlanDetailView(
                    candidate: selectedCandidate,
                    state: trainingState,
                    explanation: explanation,
                    catalog: catalogStore.exercises,
                    loadUnit: appModel.trainingProfile.loadUnit,
                    onStart: { requestStart(selectedCandidate.plan) }
                )
            }
        }
        .fullScreenCover(item: $activeWorkout) { template in
            ActiveWorkoutView(
                template: template,
                adjustment: neutralAdjustment,
                loadUnit: appModel.trainingProfile.loadUnit
            )
        }
        .alert("Workout in Progress", isPresented: $showingActiveWorkoutAlert) {
            Button("Open Current Workout") { onOpenTrain() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Finish or discard your current workout before starting a new one.")
        }
    }

    private func recommendationCard(
        _ candidate: WorkoutPlanCandidate,
        state: DailyTrainingState
    ) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Label(
                        dynamicTypeSize.isAccessibilitySize ? "Today’s Workout" : "Recommended Today",
                        systemImage: "sparkles"
                    )
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.coachIndigo)
                        .textCase(dynamicTypeSize.isAccessibilitySize ? nil : .uppercase)
                    Spacer()
                    if let personalizationStatusText {
                        Label(personalizationStatusText, systemImage: isPersonalized ? "iphone.gen3" : "checkmark.shield")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(candidate.plan.title)
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(candidate.plan.expectedDurationMinutes) min · \(candidate.plan.exercises.count) exercises · \(candidate.plan.mode.displayTitle)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                insightStrip(state)

                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    requestStart(candidate.plan)
                } label: {
                    Label("Start Workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.coachIndigo)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { recommendationActions }
                    VStack(spacing: 10) { recommendationActions }
                }

                Button {
                    showingDetails = true
                } label: {
                    HStack {
                        Label("Review Workout", systemImage: "list.bullet.rectangle")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.coachIndigo)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var recommendationActions: some View {
        Button { showingAdjustments = true } label: {
            Label("Adjust", systemImage: "slider.horizontal.3")
        }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, minHeight: 44)
        Button { showingAlternatives = true } label: {
            Label("Options", systemImage: "arrow.triangle.branch")
        }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func insightStrip(_ state: DailyTrainingState) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recovery \(state.recovery.readinessScore.map(String.init) ?? "unavailable") · Sleep \(state.recovery.sleepMinutes.map { Double($0).hoursMinutes } ?? "unavailable")")
                    Text("\(state.training.sessionsLast7Days) of \(appModel.trainingProfile.targetSessionsPerWeek) workouts in the last 7 days")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            } else {
                HStack(spacing: 8) { insightItems(state) }
            }
        }
    }

    @ViewBuilder
    private func insightItems(_ state: DailyTrainingState) -> some View {
        InsightPill(
            title: "Recovery",
            value: state.recovery.readinessScore.map(String.init) ?? "—",
            color: state.recovery.readinessBand.color
        )
        InsightPill(
            title: "Sleep",
            value: state.recovery.sleepMinutes.map { Double($0).hoursMinutes } ?? "—",
            color: .coachIndigo
        )
        InsightPill(
            title: "Last 7 Days",
            value: "\(state.training.sessionsLast7Days) / \(appModel.trainingProfile.targetSessionsPerWeek)",
            color: .coachMint
        )
    }

    private var loadingCard: some View {
        CoachCard {
            HStack(spacing: 12) {
                SwiftUI.ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Planning Today’s Workout").font(.headline)
                    Text("Matching recovery, recent training, time, and equipment.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var unavailableCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Workout recommendation unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.coachAmber)
                Text(generationError ?? "The reviewed exercise pool could not match the current preferences.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Review Workout Preferences") { showingAdjustments = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.coachIndigo)
                    .frame(minHeight: 44)
            }
        }
    }

    @MainActor
    private func prepareRecommendation() async {
        let input = recommendationInput
        isGenerating = selectedCandidate == nil
        generationError = nil

        let profile = appModel.trainingProfile
        let constraints = WorkoutConstraints(
            availableMinutes: availableMinutes,
            goal: profile.goal,
            targetSessionsPerWeek: profile.targetSessionsPerWeek,
            equipmentProfile: profile.activeEquipmentProfile,
            preferredFocus: preferredFocus,
            effort: plannedEffort,
            preferredExerciseIDs: profile.preferredExerciseIDs,
            excludedExerciseIDs: profile.excludedExerciseIDs,
            excludedMovementPatterns: profile.excludedMovementPatterns
        )
        let pool = CuratedExerciseCatalog.makePool(from: catalogStore.exercises)
        let state = stateBuilder.makeState(
            snapshot: appModel.snapshot,
            sessions: sessions,
            constraints: constraints,
            curatedPool: pool,
            enabledRecoveryMetrics: enabledRecoveryMetrics,
            loadUnit: profile.loadUnit
        )

        let generated: WorkoutPlanCandidates
        do {
            generated = try planner.generate(
                from: state,
                curatedPool: pool,
                loadUnit: profile.loadUnit
            )
        } catch {
            guard !Task.isCancelled, recommendationInput == input else { return }
            trainingState = state
            candidates = nil
            selectedCandidate = nil
            personalizationStatusText = nil
            generationError = error.localizedDescription
            isGenerating = false
            return
        }

        guard !Task.isCancelled, recommendationInput == input else { return }
        selectionRevision &+= 1
        let revisionBeforePersonalization = selectionRevision
        trainingState = state
        candidates = generated
        selectedCandidate = generated.primary
        explanation = deterministicExplanation(for: generated.primary, state: state)
        isPersonalized = false
        personalizationStatusText = nil
        isGenerating = false
        applyDebugRouteIfNeeded(plan: generated.primary.plan)

        // The deterministic recommendation is complete at this point. Optional
        // personalization must never be able to remove or invalidate it.
        guard profile.onDevicePersonalizationEnabled else { return }
        let request: WorkoutPersonalizationRequest
        do {
            request = try WorkoutPersonalizationRequestBuilder().makeRequest(
                state: state,
                candidates: generated,
                aiConsentGranted: true
            )
        } catch {
            personalizationStatusText = "Validated Planner"
            return
        }

        let decision = await Self.personalizer.personalize(request)
        guard !Task.isCancelled,
              recommendationInput == input,
              selectionRevision == revisionBeforePersonalization,
              trainingState?.stateID == decision.stateID else { return }

        switch decision.status {
        case .personalized:
            guard let selected = generated.all.first(where: {
                $0.id == decision.candidateIdentifier
            }) else { return }
            selectedCandidate = selected
            explanation = decision.explanation
            isPersonalized = true
            personalizationStatusText = "On device"
        case .deterministicFallback(let reason):
            // Keep the richer deterministic explanation and primary candidate.
            // The fallback status explains why optional personalization did not run.
            isPersonalized = false
            personalizationStatusText = reason.shortStatus
        }
    }

    private var recommendationInput: WorkoutRecommendationInput {
        WorkoutRecommendationInput(
            snapshotGeneratedAt: appModel.snapshot.generatedAt,
            profile: appModel.trainingProfile,
            availableMinutes: availableMinutes,
            preferredFocus: preferredFocus,
            effort: plannedEffort,
            enabledRecoveryMetrics: enabledRecoveryMetrics,
            sessionIDs: sessions.map(\.id),
            catalogExerciseCount: catalogStore.exercises.count,
            catalogLoadedAt: catalogStore.loadedAt
        )
    }

    private var enabledRecoveryMetrics: Set<MetricKind> {
        Set(
            appModel.preferences.decisionMetricPreferences
                .filter(\.usedInRecommendation)
                .map(\.metric)
        )
    }

    private func deterministicExplanation(
        for candidate: WorkoutPlanCandidate,
        state: DailyTrainingState
    ) -> String {
        let healthContext: String
        if candidate.plan.reasonCodes.contains(.limitedRecoveryConfidence) {
            healthContext = "Recovery confidence is limited, so intensity stays conservative"
        } else if state.recovery.readinessScore != nil {
            healthContext = "Recovery is \(state.recovery.readinessBand.title.lowercased())"
        } else {
            healthContext = "Recovery data is unavailable, so the plan uses your preferences and training history"
        }
        return "\(healthContext). This \(candidate.plan.focus.title.lowercased()) session fits \(candidate.plan.expectedDurationMinutes) minutes and your \(appModel.trainingProfile.activeEquipmentProfile.name) equipment."
    }

    private func selectAlternative(_ candidate: WorkoutPlanCandidate) {
        selectionRevision &+= 1
        selectedCandidate = candidate
        if let trainingState {
            explanation = deterministicExplanation(for: candidate, state: trainingState)
        }
        isPersonalized = false
        personalizationStatusText = "Validated Planner"
    }

    private func requestStart(_ plan: WorkoutPlan) {
        guard draftStore.load() == nil else {
            showingActiveWorkoutAlert = true
            return
        }
        activeWorkout = WorkoutTemplateRecord(
            name: plan.title,
            exercises: plan.exercises.map {
                $0.workoutExercise(loadUnit: appModel.trainingProfile.loadUnit)
            }
        )
    }

    private func applyDebugRouteIfNeeded(plan: WorkoutPlan) {
        #if DEBUG
        guard !appliedDebugRoute else { return }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--show-workout-adjustment") {
            appliedDebugRoute = true
            showingAdjustments = true
        } else if arguments.contains("--show-workout-options") {
            appliedDebugRoute = true
            showingAlternatives = true
        } else if arguments.contains("--show-workout-detail") {
            appliedDebugRoute = true
            showingDetails = true
        } else if arguments.contains("--show-generated-workout") {
            appliedDebugRoute = true
            requestStart(plan)
        }
        #endif
    }

    private var neutralAdjustment: WorkoutAdjustment {
        WorkoutAdjustment(
            title: "As planned",
            detail: "This workout already reflects today’s training state.",
            volumeMultiplier: 1,
            rpeCap: nil,
            allowProgression: true
        )
    }
}

private struct WorkoutRecommendationInput: Hashable {
    let snapshotGeneratedAt: Date
    let profile: TrainingProfile
    let availableMinutes: Int
    let preferredFocus: TrainingFocus?
    let effort: PlannedEffort
    let enabledRecoveryMetrics: Set<MetricKind>
    let sessionIDs: [UUID]
    let catalogExerciseCount: Int
    let catalogLoadedAt: Date?
}

private struct InsightPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).monospacedDigit()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private extension WorkoutPlanningMode {
    var displayTitle: String {
        switch self {
        case .performance: "Performance"
        case .balanced: "Balanced"
        case .reduced: "Reduced"
        }
    }
}

private extension WorkoutPersonalizationFallbackReason {
    var shortStatus: String {
        switch self {
        case .lowPowerMode: "Planner · Low Power"
        case .thermalPressure: "Planner · Device Warm"
        case .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady,
             .unsupportedLanguageOrLocale, .temporarilyUnavailable:
            "Private Planner"
        case .consentNotGranted, .refused, .safetyGuardrail, .generationFailed,
             .invalidResponse, .cancelled:
            "Validated Planner"
        }
    }
}

private struct WorkoutAdjustmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int
    @State private var equipmentProfileID: EquipmentProfileID
    @State private var focus: TrainingFocus?
    @State private var effort: PlannedEffort

    let profiles: [EquipmentProfile]
    let onApply: (Int, EquipmentProfileID, TrainingFocus?, PlannedEffort) -> Void

    init(
        minutes: Int,
        equipmentProfileID: EquipmentProfileID,
        focus: TrainingFocus?,
        effort: PlannedEffort,
        profiles: [EquipmentProfile],
        onApply: @escaping (Int, EquipmentProfileID, TrainingFocus?, PlannedEffort) -> Void
    ) {
        _minutes = State(initialValue: minutes)
        _equipmentProfileID = State(initialValue: equipmentProfileID)
        _focus = State(initialValue: focus)
        _effort = State(initialValue: effort)
        self.profiles = profiles
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Available Time") {
                    Picker("Workout length", selection: $minutes) {
                        ForEach([30, 45, 60], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Equipment") {
                    Picker("Training location", selection: $equipmentProfileID) {
                        ForEach(profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                }

                Section("Focus") {
                    Picker("Muscle-group focus", selection: $focus) {
                        Text("Recommended").tag(Optional<TrainingFocus>.none)
                        ForEach(TrainingFocus.allCases, id: \.self) { item in
                            Text(item.title).tag(Optional(item))
                        }
                    }
                }

                Section {
                    Picker("Training effort", selection: $effort) {
                        Text("As planned").tag(PlannedEffort.asPlanned)
                        Text("Lower intensity").tag(PlannedEffort.easier)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Effort")
                } footer: {
                    Text("The planner will rebuild all three options and revalidate the result.")
                }
            }
            .navigationTitle("Adjust Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(minutes, equipmentProfileID, focus, effort)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct WorkoutAlternativesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let candidates: WorkoutPlanCandidates
    let selectedID: String?
    let onSelect: (WorkoutPlanCandidate) -> Void

    var body: some View {
        NavigationStack {
            List(candidates.all) { candidate in
                Button {
                    onSelect(candidate)
                    dismiss()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: candidate.id == selectedID ? "checkmark.circle.fill" : candidate.role.symbol)
                            .font(.title3)
                            .foregroundStyle(candidate.id == selectedID ? Color.coachMint : Color.coachIndigo)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.role.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(candidate.plan.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("\(candidate.plan.expectedDurationMinutes) min · \(candidate.plan.exercises.count) exercises · \(candidate.plan.focus.title)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Uses this validated workout on Today")
            }
            .navigationTitle("Other Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private extension WorkoutCandidateRole {
    var title: String {
        switch self {
        case .primary: "Recommended"
        case .shorter: "Shorter"
        case .alternateFocus: "Different Focus"
        }
    }

    var symbol: String {
        switch self {
        case .primary: "sparkles"
        case .shorter: "timer"
        case .alternateFocus: "arrow.triangle.branch"
        }
    }
}

private struct WorkoutPlanDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let candidate: WorkoutPlanCandidate
    let state: DailyTrainingState
    let explanation: String
    let catalog: [ExerciseDefinition]
    let loadUnit: LoadUnit
    let onStart: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    CoachCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(candidate.plan.title).font(.title2.bold())
                            Text("\(candidate.plan.expectedDurationMinutes) min · \(candidate.plan.focus.title) · \(candidate.plan.mode.displayTitle)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(explanation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "Workout", subtitle: "Every exercise comes from the reviewed catalog.")
                        ForEach(Array(candidate.plan.exercises.enumerated()), id: \.element.id) { index, exercise in
                            exerciseRow(exercise, index: index)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "Why This Fits", subtitle: "Measured, calculated, and selected inputs are labeled separately.")
                        ForEach(Array(state.evidence.prefix(5))) { item in
                            evidenceRow(item)
                        }
                    }

                    Text("Wellness and training guidance only. This recommendation is not a diagnosis or a determination that exercise is medically safe.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
                .padding()
            }
            .background(Color.coachBackground)
            .navigationTitle("Workout Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                    Task { @MainActor in
                        await Task.yield()
                        onStart()
                    }
                } label: {
                    Label("Start Workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.coachIndigo)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
    }

    @ViewBuilder
    private func exerciseRow(_ exercise: ExercisePrescription, index: Int) -> some View {
        let definition = catalog.first(where: { $0.id == exercise.catalogID })
        Group {
            if let definition {
                NavigationLink {
                    ExerciseDetailView(
                        exercise: definition,
                        allowsSelection: false,
                        isAlreadyInTemplate: false,
                        selectedIDs: .constant([])
                    )
                } label: {
                    exerciseRowContent(exercise, index: index, hasDetail: true)
                }
                .buttonStyle(.plain)
            } else {
                exerciseRowContent(exercise, index: index, hasDetail: false)
            }
        }
    }

    private func exerciseRowContent(
        _ exercise: ExercisePrescription,
        index: Int,
        hasDetail: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.caption.bold())
                .foregroundStyle(Color.coachIndigo)
                .frame(width: 28, height: 28)
                .background(Color.coachIndigo.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name).font(.headline)
                Text(prescription(exercise))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let progression = exercise.progressionSuggestion {
                    Label(progressionText(progression), systemImage: "arrow.up.right.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.coachIndigo)
                }
            }
            Spacer(minLength: 0)
            if hasDetail {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color.coachSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func prescription(_ exercise: ExercisePrescription) -> String {
        var parts = ["\(exercise.workingSets) × \(exercise.repetitions.lowerBound)–\(exercise.repetitions.upperBound)"]
        if let load = exercise.workingLoad, load > 0 {
            parts.append("\(load.formatted(.number.precision(.fractionLength(0...1)))) \(loadUnit.symbol)")
        }
        parts.append("RPE \(exercise.targetRPE.formatted(.number.precision(.fractionLength(0...1))))")
        return parts.joined(separator: " · ")
    }

    private func progressionText(_ progression: ProgressionSuggestion) -> String {
        if let proposed = progression.suggestedLoad {
            return "Optional: try \(proposed.formatted(.number.precision(.fractionLength(0...1)))) \(loadUnit.symbol); confirm first"
        }
        if let reps = progression.suggestedRepetitions {
            return "Optional: try \(reps) reps; confirm first"
        }
        return "Optional progression; confirm first"
    }

    private func evidenceRow(_ item: EvidenceItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.provenance.symbol)
                .foregroundStyle(item.provenance.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.title).font(.subheadline.bold())
                    Spacer()
                    Text(item.provenance.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                Text(item.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .background(Color.coachSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private extension EvidenceProvenance {
    var title: String {
        switch self {
        case .measured: "Measured"
        case .calculated: "Calculated"
        case .inferred: "Inferred"
        case .userEntered: "Selected"
        }
    }

    var symbol: String {
        switch self {
        case .measured: "waveform.path.ecg"
        case .calculated: "function"
        case .inferred: "sparkles"
        case .userEntered: "person.crop.circle"
        }
    }

    var color: Color {
        switch self {
        case .measured: .coachMint
        case .calculated: .coachIndigo
        case .inferred: .coachAmber
        case .userEntered: .secondary
        }
    }
}
