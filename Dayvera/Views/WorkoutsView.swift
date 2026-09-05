import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit

struct WorkoutsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var appModel: AppModel
    @Query(sort: \WorkoutTemplateRecord.createdAt) private var templates: [WorkoutTemplateRecord]
    @Query(sort: \WorkoutSessionRecord.startedAt, order: .reverse) private var sessions: [WorkoutSessionRecord]
    @State private var showingNewTemplate = false
    @State private var showingWorkoutBuilder = false
    @State private var templateToEdit: WorkoutTemplateRecord?
    @State private var activeTemplate: WorkoutTemplateRecord?
    @State private var generatedDraftTemplate: WorkoutTemplateRecord?
    @State private var activeDraft: ActiveWorkoutDraft?
    @State private var templateToDelete: WorkoutTemplateRecord?
    @State private var showingDiscardDraft = false
    @State private var showingDebugProgress = false
    @State private var appliedDebugRoute = false
    private let draftStore = ActiveWorkoutDraftStore()
    let onOpenToday: () -> Void

    init(onOpenToday: @escaping () -> Void = {}) {
        self.onOpenToday = onOpenToday
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let draft = activeDraft,
                   let template = templateForDraft(draft) {
                    draftCard(draft, template: template)
                }

                if activeDraft == nil, let quickStartTemplate {
                    quickStartCard(quickStartTemplate)
                }
                if activeDraft == nil {
                    workoutBuilderCard
                }
                templateSectionHeader

                if templates.isEmpty {
                    emptyTemplatesCard
                } else {
                    ForEach(templates) { template in
                        templateRow(template)
                    }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Train")
        .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    ExerciseLibraryView()
                } label: {
                    Image(systemName: "books.vertical")
                }
                .accessibilityLabel("Exercise Library")

                Button {
                    showingNewTemplate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Template")
            }
        }
        .sheet(isPresented: $showingNewTemplate) { TemplateEditorView() }
        .sheet(isPresented: $showingWorkoutBuilder) {
            WorkoutBuildSheet(onBuild: onOpenToday)
        }
        .sheet(item: $templateToEdit) { template in
            TemplateEditorView(template: template)
        }
        .fullScreenCover(item: $activeTemplate, onDismiss: loadDraftState) { template in
            ActiveWorkoutView(
                template: template,
                adjustment: appModel.plan.workoutAdjustment,
                loadUnit: appModel.trainingProfile.loadUnit
            )
        }
        .navigationDestination(isPresented: $showingDebugProgress) {
            TrainingHistoryView()
        }
        .confirmationDialog(
            "Delete \(templateToDelete?.name ?? "this template")?",
            isPresented: Binding(
                get: { templateToDelete != nil },
                set: { if !$0 { templateToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete template", role: .destructive) {
                guard let templateToDelete else { return }
                guard activeDraft?.templateID != templateToDelete.id else { return }
                modelContext.delete(templateToDelete)
                do { try modelContext.save() }
                catch {
                    modelContext.rollback()
                    appModel.notice = "The template could not be deleted: \(error.localizedDescription)"
                }
                self.templateToDelete = nil
            }
            Button("Cancel", role: .cancel) { templateToDelete = nil }
        } message: {
            Text("Your completed workout history will remain available.")
        }
        .confirmationDialog("Discard the saved workout?", isPresented: $showingDiscardDraft, titleVisibility: .visible) {
            Button("Discard draft", role: .destructive) {
                draftStore.clear()
                activeDraft = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Recorded set progress in this unfinished workout will be removed.")
        }
        .onAppear {
            loadDraftState()
            applyDebugRouteIfNeeded()
        }
        .onChange(of: templates.count) { _, _ in
            loadDraftState()
            applyDebugRouteIfNeeded()
        }
    }

    private var workoutBuilderCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Build today’s workout", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Color.coachIndigo)
                Text("Answer a few questions and Dayvera will build a recovery-aware workout from your goal, equipment, training history, and hard movement exclusions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showingWorkoutBuilder = true
                } label: {
                    Label("Build Workout", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.coachIndigo)
            }
        }
    }

    private func quickStartCard(_ template: WorkoutTemplateRecord) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Quick Start", systemImage: "bolt.fill")
                    .font(.headline)
                    .foregroundStyle(Color.coachIndigo)
                Text(template.name)
                    .font(.title3.bold())
                Text("Repeat your most recent saved workout with today’s recovery limits applied.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    activeTemplate = template
                } label: {
                    Label("Start \(template.name)", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.coachIndigo)
            }
        }
    }

    private var templateSectionHeader: some View {
        let title = "Saved Workouts"
        let subtitle = activeDraft == nil
            ? "Choose a template or build one from the exercise library."
            : "Finish or discard the workout in progress before starting another."
        return SectionTitle(title: title, subtitle: subtitle)
    }

    private var emptyTemplatesCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Build your first template", systemImage: "square.stack.3d.up.fill")
                    .font(.headline)
                Text("Choose exercises from the library, review each prescription, and arrange them in the order you train.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showingNewTemplate = true
                } label: {
                    Label("Create Template", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.coachIndigo)
            }
        }
    }

    private var quickStartTemplate: WorkoutTemplateRecord? {
        if let latestTemplateID = sessions.first?.templateID,
           let recent = templates.first(where: { $0.id == latestTemplateID }) {
            return recent
        }
        return templates.first
    }

    private func templateRow(_ template: WorkoutTemplateRecord) -> some View {
        HStack(spacing: 10) {
            NavigationLink {
                WorkoutPreviewView(
                    template: template,
                    adjustment: appModel.plan.workoutAdjustment,
                    loadUnit: appModel.trainingProfile.loadUnit,
                    canStart: activeDraft == nil,
                    onStart: { activeTemplate = template }
                )
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(template.exercises.count) exercises · \(adaptedSetCount(template)) working sets")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(lastCompletedDate(for: template).map { "Last completed \($0.shortDay)" } ?? "Not completed yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens workout preview")

            Button {
                activeTemplate = template
            } label: {
                Image(systemName: activeDraft == nil ? "play.fill" : "lock.fill")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .tint(Color.coachIndigo)
            .disabled(activeDraft != nil)
            .accessibilityLabel("Start \(template.name)")
            .accessibilityHint(activeDraft == nil ? "Starts this workout immediately" : "Finish or discard the active workout first")
        }
        .padding(14)
        .background(Color.coachSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            if activeDraft?.templateID == template.id {
                Button("Finish workout to edit", systemImage: "lock.fill") {}
                    .disabled(true)
                Button("Finish workout to delete", systemImage: "lock.fill") {}
                    .disabled(true)
            } else {
                Button("Edit template", systemImage: "pencil") { templateToEdit = template }
                Button("Delete…", role: .destructive) { templateToDelete = template }
            }
        }
    }

    private func draftCard(_ draft: ActiveWorkoutDraft, template: WorkoutTemplateRecord) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Workout in progress", systemImage: "figure.strengthtraining.traditional")
                    .font(.headline)
                    .foregroundStyle(Color.coachIndigo)
                Text(template.name)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(draft.sets.filter(\.isComplete).count) of \(draft.sets.count) sets complete")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) {
                        draftResumeButton(template)
                        draftDiscardButton
                    }
                } else {
                    HStack {
                        draftResumeButton(template)
                        draftDiscardButton
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func templateExercisePreview(_ exercise: WorkoutExercise) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(exercise.workingSets) sets × \(exercise.targetReps) reps")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Text(exercise.name)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(exercise.workingSets) × \(exercise.targetReps)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func draftResumeButton(_ template: WorkoutTemplateRecord) -> some View {
        Button("Resume") { activeTemplate = template }
            .buttonStyle(.borderedProminent)
            .tint(Color.coachIndigo)
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44)
    }

    private var draftDiscardButton: some View {
        Button("Discard", role: .destructive) { showingDiscardDraft = true }
            .buttonStyle(.bordered)
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44)
    }

    private func adaptedSetCount(_ template: WorkoutTemplateRecord) -> Int {
        adaptedWorkingSetCounts(
            for: template.exercises,
            volumeMultiplier: appModel.plan.workoutAdjustment.volumeMultiplier
        ).values.reduce(0, +)
    }

    private func lastCompletedDate(for template: WorkoutTemplateRecord) -> Date? {
        sessions.first(where: { $0.templateID == template.id })?.startedAt
    }

    private func applyDebugRouteIfNeeded() {
        #if DEBUG
        guard !appliedDebugRoute else { return }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--show-template-editor") || arguments.contains("--show-template-library") {
            appliedDebugRoute = true
            showingNewTemplate = true
        } else if arguments.contains("--show-active-workout"), let template = templates.first {
            appliedDebugRoute = true
            activeTemplate = template
        } else if arguments.contains("--show-progress") {
            appliedDebugRoute = true
            showingDebugProgress = true
        }
        #endif
    }

    private func loadDraftState() {
        guard let draft = draftStore.load() else {
            activeDraft = nil
            return
        }
        if templates.contains(where: { $0.id == draft.templateID }) {
            generatedDraftTemplate = nil
        } else if let exercises = draft.exercises, !exercises.isEmpty {
            generatedDraftTemplate = WorkoutTemplateRecord(
                id: draft.templateID,
                name: draft.templateName ?? "Generated Workout",
                exercises: exercises
            )
        } else {
            draftStore.clear()
            generatedDraftTemplate = nil
            activeDraft = nil
            return
        }
        activeDraft = draft
    }

    private func templateForDraft(_ draft: ActiveWorkoutDraft) -> WorkoutTemplateRecord? {
        templates.first(where: { $0.id == draft.templateID })
            ?? (generatedDraftTemplate?.id == draft.templateID ? generatedDraftTemplate : nil)
    }
}

private struct WorkoutBuildSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var minutes = 45
    @State private var focus: TrainingFocus?
    @State private var effort: PlannedEffort = .asPlanned

    let onBuild: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Goal", selection: $appModel.trainingProfile.goal) {
                        ForEach(TrainingGoal.allCases, id: \.self) { goal in
                            Text(goal.title).tag(goal)
                        }
                    }
                    Stepper(
                        "\(appModel.trainingProfile.targetSessionsPerWeek) workouts per week",
                        value: $appModel.trainingProfile.targetSessionsPerWeek,
                        in: 2...6
                    )
                } header: {
                    Text("Your training")
                } footer: {
                    Text("Your goal and weekly target are saved for future recommendations.")
                }

                Section {
                    Picker("Time available", selection: $minutes) {
                        ForEach([30, 45, 60], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Focus", selection: $focus) {
                        Text("Recommended").tag(Optional<TrainingFocus>.none)
                        ForEach(TrainingFocus.allCases, id: \.self) { focus in
                            Text(focus.title).tag(Optional(focus))
                        }
                    }
                    Picker("Effort", selection: $effort) {
                        Text("As planned").tag(PlannedEffort.asPlanned)
                        Text("Easier today").tag(PlannedEffort.easier)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Today")
                }

                Section {
                    Picker("Training location", selection: $appModel.trainingProfile.activeEquipmentProfileID) {
                        ForEach(appModel.trainingProfile.equipmentProfiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    LabeledContent("Movement exclusions") {
                        Text("\(appModel.trainingProfile.excludedMovementPatterns.count + appModel.trainingProfile.excludedExerciseIDs.count) set")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Equipment")
                } footer: {
                    Text("Set exclusions in Settings › Workout Preferences. They remain hard rules; Dayvera never asks on-device AI to override them.")
                }

                Section {
                    Toggle("Personalize valid options", isOn: $appModel.trainingProfile.onDevicePersonalizationEnabled)
                    Text("When available, Apple Intelligence can rank already-safe options and explain the choice. The validated planner creates every exercise and prescription.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Optional on-device AI")
                }
            }
            .navigationTitle("Build Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Build") {
                        appModel.workoutBuildIntent = WorkoutBuildIntent(
                            availableMinutes: minutes,
                            focus: focus,
                            effort: effort
                        )
                        dismiss()
                        onBuild()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct WorkoutPreviewView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let template: WorkoutTemplateRecord
    let adjustment: WorkoutAdjustment
    let loadUnit: LoadUnit
    let canStart: Bool
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                CoachCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TODAY'S ADJUSTMENT")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(adjustment.title)
                            .font(.title2.bold())
                        Label("About \(estimatedMinutes) min · \(setCount) working sets", systemImage: "clock")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(adjustment.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SectionTitle(title: "Exercises", subtitle: "Today’s recovery-adjusted working sets")
                VStack(spacing: 0) {
                    ForEach(Array(template.exercises.enumerated()), id: \.element.id) { index, exercise in
                        if index > 0 { Divider().padding(.leading, 14) }
                        exerciseRow(exercise)
                    }
                }
                .background(Color.coachSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if !canStart {
                    Label("Finish or discard the workout in progress before starting another.", systemImage: "lock.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    onStart()
                } label: {
                    Label("Start Workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.coachIndigo)
                .disabled(!canStart)

                NavigationLink {
                    TemplateEditorView(template: template)
                } label: {
                    Text("Edit Template")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!canStart)
            }
            .padding()
        }
        .background(Color.coachBackground)
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func exerciseRow(_ exercise: WorkoutExercise) -> some View {
        let count = adaptedWorkingSetCounts(
            for: template.exercises,
            volumeMultiplier: adjustment.volumeMultiplier
        )[exercise.id, default: exercise.workingSets]
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name).font(.headline)
                    exercisePrescription(exercise, setCount: count)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(exercise.name).font(.headline)
                    Spacer(minLength: 8)
                    exercisePrescription(exercise, setCount: count)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    private func exercisePrescription(_ exercise: WorkoutExercise, setCount: Int) -> some View {
        let displayedLoad = workoutPreviewLoad(exercise, displayedIn: loadUnit)
        return Text("\(setCount) × \(exercise.targetReps) · \(displayedLoad.formatted(.number.precision(.fractionLength(0...1)))) \(loadUnit.symbol)")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private var setCount: Int {
        adaptedWorkingSetCounts(
            for: template.exercises,
            volumeMultiplier: adjustment.volumeMultiplier
        ).values.reduce(0, +)
    }

    private var estimatedMinutes: Int {
        let activeSeconds = setCount * 45
        let restSeconds = template.exercises.reduce(0) { partial, exercise in
            let count = adaptedWorkingSetCounts(
                for: template.exercises,
                volumeMultiplier: adjustment.volumeMultiplier
            )[exercise.id, default: exercise.workingSets]
            return partial + max(count - 1, 0) * exercise.restSeconds
        }
        return max(Int(ceil(Double(activeSeconds + restSeconds) / 300.0)) * 5, 10)
    }
}

func workoutPreviewLoad(_ exercise: WorkoutExercise, displayedIn unit: LoadUnit) -> Double {
    exercise.resolvedLoadUnit.convert(exercise.targetWeight, to: unit)
}

struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appModel: AppModel

    private let template: WorkoutTemplateRecord?
    @State private var name: String
    @State private var exercises: [WorkoutExercise]
    @State private var showingLibrary = false
    @State private var showingCustomExercise = false
    @State private var saveError: String?
    @State private var appliedDebugLibraryRoute = false

    init(template: WorkoutTemplateRecord? = nil) {
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _exercises = State(initialValue: template?.exercises ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Template") {
                    TextField("e.g. Lower body strength", text: $name)
                }

                Section {
                    if exercises.isEmpty {
                        Text("Add exercises in the order you perform them. Library prescriptions are starting points you can review and edit.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(exercises) { exercise in
                        NavigationLink {
                            ExercisePrescriptionEditorView(exercise: exerciseBinding(for: exercise))
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(exercise.name)
                                        .font(.headline)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if exercise.catalogID != nil {
                                        Image(systemName: "books.vertical.fill")
                                            .font(.caption)
                                            .foregroundStyle(Color.coachIndigo)
                                            .accessibilityLabel("From exercise library")
                                    }
                                }
                                Text(prescriptionSummary(for: exercise))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .onDelete { exercises.remove(atOffsets: $0) }
                    .onMove { exercises.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    HStack {
                        Text("Exercises")
                        Spacer()
                        if exercises.count > 1 {
                            EditButton()
                                .textCase(nil)
                                .frame(minHeight: 44)
                        }
                    }
                } footer: {
                    if !exercises.isEmpty {
                        Text("Tap an exercise to edit sets, reps, load, RPE, and rest. Use Edit to reorder or delete.")
                    }
                }

                Section("Add exercises") {
                    Button {
                        showingLibrary = true
                    } label: {
                        Label("Add from library", systemImage: "books.vertical.fill")
                            .frame(minHeight: 44)
                    }
                    Button {
                        showingCustomExercise = true
                    } label: {
                        Label("Create custom exercise", systemImage: "square.and.pencil")
                            .frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle(template == nil ? "New template" : "Edit template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTemplate() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || exercises.isEmpty)
                }
            }
            .sheet(isPresented: $showingLibrary) {
                ExerciseLibraryView(existingCatalogIDs: existingCatalogIDs) { definitions in
                    appendCatalogExercises(definitions)
                }
            }
            .sheet(isPresented: $showingCustomExercise) {
                ExerciseEditorView { exercises.append($0) }
            }
            .alert("Couldn’t save template", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "Unknown storage error")
            }
            .task {
                #if DEBUG
                if !appliedDebugLibraryRoute,
                   ProcessInfo.processInfo.arguments.contains("--show-template-library") {
                    appliedDebugLibraryRoute = true
                    await Task.yield()
                    showingLibrary = true
                }
                #endif
            }
        }
    }

    private var existingCatalogIDs: Set<String> {
        Set(exercises.compactMap(\.catalogID))
    }

    private func exerciseBinding(for exercise: WorkoutExercise) -> Binding<WorkoutExercise> {
        Binding {
            exercises.first(where: { $0.id == exercise.id }) ?? exercise
        } set: { updated in
            guard let index = exercises.firstIndex(where: { $0.id == updated.id }) else { return }
            exercises[index] = updated
        }
    }

    private func appendCatalogExercises(_ definitions: [ExerciseDefinition]) {
        var seen = existingCatalogIDs
        for definition in definitions where seen.insert(definition.id).inserted {
            exercises.append(definition.workoutExercise(loadUnit: appModel.trainingProfile.loadUnit))
        }
    }

    private func prescriptionSummary(for exercise: WorkoutExercise) -> String {
        "\(exercise.workingSets) sets × \(exercise.targetReps) reps · \(exercise.targetWeight.formatted(.number.precision(.fractionLength(0...1)))) \(exercise.resolvedLoadUnit.symbol) · RPE \(exercise.targetRPE.formatted(.number.precision(.fractionLength(0...1)))) · \(exercise.restSeconds)s rest"
    }

    private func saveTemplate() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let template {
            template.name = trimmedName
            template.exercises = exercises
        } else {
            modelContext.insert(WorkoutTemplateRecord(name: trimmedName, exercises: exercises))
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
        }
    }
}

private struct ExercisePrescriptionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @Binding var exercise: WorkoutExercise

    var body: some View {
        Form {
            Section("Exercise") {
                LabeledContent("Name", value: exercise.name)
                LabeledContent("Muscle", value: exercise.muscleGroup.title)
                if exercise.catalogID != nil {
                    Label("Library exercise", systemImage: "books.vertical.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Stepper("Working sets: \(exercise.workingSets)", value: $exercise.workingSets, in: 1...10)
                Stepper("Target reps: \(exercise.targetReps)", value: $exercise.targetReps, in: 1...30)
                Stepper(
                    "Load: \(exercise.targetWeight.formatted(.number.precision(.fractionLength(0...1)))) \(exercise.resolvedLoadUnit.symbol)",
                    value: $exercise.targetWeight,
                    in: 0...exercise.resolvedLoadUnit.maximumWorkoutLoad,
                    step: exercise.resolvedLoadUnit.inputStep
                )
                Stepper(
                    "Target RPE: \(exercise.targetRPE.formatted(.number.precision(.fractionLength(1))))",
                    value: $exercise.targetRPE,
                    in: 5...10,
                    step: 0.5
                )
                Stepper("Rest: \(exercise.restSeconds) sec", value: $exercise.restSeconds, in: 30...600, step: 15)
            } header: {
                Text("Prescription")
            } footer: {
                Text("Review these values for your current ability and equipment before saving the template.")
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            exercise = exercise.converted(to: appModel.trainingProfile.loadUnit)
        }
    }
}

private struct ExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    let showsTargetRPE: Bool
    let onSave: (WorkoutExercise) -> Void
    @State private var name = ""
    @State private var muscle: MuscleGroup = .fullBody
    @State private var sets = 3
    @State private var reps = 8
    @State private var weight = 45.0
    @State private var rpe = 8.0
    @State private var rest = 120

    init(
        showsTargetRPE: Bool = true,
        onSave: @escaping (WorkoutExercise) -> Void
    ) {
        self.showsTargetRPE = showsTargetRPE
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise name", text: $name)
                Picker("Muscle group", selection: $muscle) {
                    ForEach(MuscleGroup.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Working sets: \(sets)", value: $sets, in: 1...10)
                Stepper("Target reps: \(reps)", value: $reps, in: 1...30)
                Stepper(
                    "Load: \(weight, specifier: "%.1f") \(appModel.trainingProfile.loadUnit.symbol)",
                    value: $weight,
                    in: 0...appModel.trainingProfile.loadUnit.maximumWorkoutLoad,
                    step: appModel.trainingProfile.loadUnit.inputStep
                )
                if showsTargetRPE {
                    Stepper("Target RPE: \(rpe, specifier: "%.1f")", value: $rpe, in: 5...10, step: 0.5)
                }
                Stepper("Rest: \(rest) sec", value: $rest, in: 30...600, step: 15)
            }
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(.init(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            muscleGroup: muscle,
                            workingSets: sets,
                            targetReps: reps,
                            targetWeight: weight,
                            loadUnit: appModel.trainingProfile.loadUnit,
                            targetRPE: rpe,
                            restSeconds: rest
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct ActiveSet: Identifiable, Codable, Hashable {
    var id = UUID()
    let exerciseID: UUID
    var catalogID: String? = nil
    let exerciseName: String
    let setNumber: Int
    var weight: Double
    var loadUnit: LoadUnit? = nil
    var reps: Int
    let restSeconds: Int
    var isComplete = false
}

struct ActiveSetProgressionSnapshot: Hashable {
    let id: UUID
    let weight: Double
    let repetitions: Int
}

func applyingProgressionRecommendation(
    _ recommendation: WorkoutProgressionRecommendation,
    to activeSets: [ActiveSet],
    exerciseID: UUID,
    loadUnit: LoadUnit
) -> [ActiveSet] {
    var updated = activeSets
    for index in updated.indices
    where updated[index].exerciseID == exerciseID && !updated[index].isComplete {
        updated[index].weight = min(
            max(updated[index].weight, max(recommendation.suggestedLoad, 0)),
            loadUnit.maximumWorkoutLoad
        )
        updated[index].loadUnit = loadUnit
        updated[index].reps = min(
            max(updated[index].reps, max(recommendation.suggestedRepetitions, 1)),
            1_000
        )
    }
    return updated
}

func restoringProgressionSnapshot(
    in activeSets: [ActiveSet],
    exerciseID: UUID,
    snapshots: [ActiveSetProgressionSnapshot]
) -> [ActiveSet] {
    let valuesByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
    var updated = activeSets
    for index in updated.indices where updated[index].exerciseID == exerciseID {
        guard !updated[index].isComplete,
              let previous = valuesByID[updated[index].id] else { continue }
        updated[index].weight = previous.weight
        updated[index].reps = previous.repetitions
    }
    return updated
}

func backfillingCatalogIDs(
    in sets: [ActiveSet],
    from exercises: [WorkoutExercise]
) -> [ActiveSet] {
    let exerciseByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
    return sets.map { set in
        guard let exercise = exerciseByID[set.exerciseID] else { return set }
        var updated = set
        if updated.catalogID == nil,
           let catalogID = exercise.catalogID,
           !catalogID.isEmpty {
            updated.catalogID = catalogID
        }
        if updated.loadUnit == nil { updated.loadUnit = exercise.resolvedLoadUnit }
        return updated
    }
}

struct ActiveWorkoutDraft: Codable, Hashable {
    let templateID: UUID
    var templateName: String? = nil
    var exercises: [WorkoutExercise]? = nil
    let startedAt: Date
    let sets: [ActiveSet]
    let notes: String
    var restDeadline: Date? = nil
    var restSourceSetID: UUID? = nil
}

func normalizedWorkoutStart(
    savedStart: Date,
    now: Date,
    maximumResumeAge: TimeInterval = 6 * 60 * 60
) -> Date {
    let age = now.timeIntervalSince(savedStart)
    guard age >= 0, age <= maximumResumeAge else { return now }
    return savedStart
}

func validWorkoutIntervalStart(
    savedStart: Date,
    end: Date,
    maximumResumeAge: TimeInterval = 6 * 60 * 60,
    staleFallbackDuration: TimeInterval = 60
) -> Date {
    let normalized = normalizedWorkoutStart(
        savedStart: savedStart,
        now: end,
        maximumResumeAge: maximumResumeAge
    )
    guard normalized < end else {
        return end.addingTimeInterval(-max(staleFallbackDuration, 1))
    }
    return normalized
}

struct ActiveWorkoutDraftStore {
    private static let key = "activeWorkoutDraft"
    private static let fileName = "active-workout-draft.json"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ActiveWorkoutDraft? {
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let draft = try? JSONDecoder().decode(ActiveWorkoutDraft.self, from: data) {
            return draft
        }
        guard let legacyData = defaults.data(forKey: Self.key),
              let draft = try? JSONDecoder().decode(ActiveWorkoutDraft.self, from: legacyData) else {
            return nil
        }
        // Migrate existing drafts out of backup-managed preferences.
        _ = save(draft)
        return draft
    }

    @discardableResult
    func save(_ draft: ActiveWorkoutDraft) -> Bool {
        guard let data = try? JSONEncoder().encode(draft) else { return false }
        guard var fileURL else { return false }
        do {
            var directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            var directoryValues = URLResourceValues()
            directoryValues.isExcludedFromBackup = true
            try directoryURL.setResourceValues(directoryValues)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try fileURL.setResourceValues(resourceValues)
            defaults.removeObject(forKey: Self.key)
            return true
        } catch {
            // Keep any pre-migration legacy value untouched, but do not create a
            // new backup-managed or less-protected copy of a workout draft.
            return false
        }
    }

    func clear() {
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        defaults.removeObject(forKey: Self.key)
    }

    private var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(Self.fileName, isDirectory: false)
    }
}

struct ActiveWorkoutView: View {
    private enum FocusedField: Hashable {
        case weight(UUID)
        case repetitions(UUID)
        case notes
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var catalogStore = ExerciseCatalogStore.shared
    @Query(sort: \WorkoutSessionRecord.startedAt, order: .reverse) private var sessions: [WorkoutSessionRecord]

    let templateID: UUID
    let templateName: String
    let adjustment: WorkoutAdjustment
    let loadUnit: LoadUnit
    @State private var exercises: [WorkoutExercise]
    @State private var sets: [ActiveSet]
    @State private var startedAt = Date.now
    @State private var currentTime = Date.now
    @State private var restDeadline: Date?
    @State private var restSourceSetID: UUID?
    @State private var showingFinish = false
    @State private var showingDiscard = false
    @State private var showingExerciseLibrary = false
    @State private var showingCustomExercise = false
    @State private var notes = ""
    @State private var resumeNotice: String?
    @State private var detailExercise: ExerciseDefinition?
    @State private var detailSelection: [String] = []
    @State private var progressionExplanation: WorkoutProgressionRecommendation?
    @State private var progressionUndo: [UUID: [ActiveSetProgressionSnapshot]] = [:]
    @FocusState private var focusedField: FocusedField?
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let draftStore = ActiveWorkoutDraftStore()

    init(template: WorkoutTemplateRecord, adjustment: WorkoutAdjustment, loadUnit: LoadUnit) {
        templateID = template.id
        templateName = template.name
        let normalizedExercises = template.exercises.map { $0.converted(to: loadUnit) }
        self.adjustment = adjustment
        self.loadUnit = loadUnit
        if let draft = ActiveWorkoutDraftStore().load(), draft.templateID == template.id {
            let now = Date.now
            let normalizedStart = normalizedWorkoutStart(savedStart: draft.startedAt, now: now)
            let restoredExercises = (draft.exercises ?? normalizedExercises).map { $0.converted(to: loadUnit) }
            let restoredSets = backfillingCatalogIDs(in: draft.sets, from: restoredExercises).map { set in
                var converted = set
                let source = set.loadUnit ?? .pounds
                converted.weight = source.convert(set.weight, to: loadUnit)
                converted.loadUnit = loadUnit
                return converted
            }
            let restoredRestSource = draft.restSourceSetID.flatMap { sourceID in
                restoredSets.contains(where: { $0.id == sourceID && $0.isComplete }) ? sourceID : nil
            }
            let restoredRestDeadline = normalizedStart == draft.startedAt
                && restoredRestSource != nil
                && (draft.restDeadline ?? .distantPast) > now
                ? draft.restDeadline
                : nil
            _exercises = State(initialValue: restoredExercises)
            _sets = State(initialValue: restoredSets)
            _startedAt = State(initialValue: normalizedStart)
            _currentTime = State(initialValue: now)
            _restDeadline = State(initialValue: restoredRestDeadline)
            _restSourceSetID = State(initialValue: restoredRestDeadline == nil ? nil : restoredRestSource)
            _notes = State(initialValue: draft.notes)
            _resumeNotice = State(initialValue: normalizedStart == draft.startedAt ? nil : "This draft was from an earlier session, so its timer restarted. Your sets and notes were kept.")
        } else {
            var proposed: [ActiveSet] = []
            let setCounts = adaptedWorkingSetCounts(for: normalizedExercises, volumeMultiplier: adjustment.volumeMultiplier)
            for exercise in normalizedExercises {
                let count = setCounts[exercise.id, default: exercise.workingSets]
                for number in 1...count {
                    proposed.append(.init(
                        exerciseID: exercise.id,
                        catalogID: exercise.catalogID,
                        exerciseName: exercise.name,
                        setNumber: number,
                        weight: exercise.targetWeight,
                        loadUnit: loadUnit,
                        reps: exercise.targetReps,
                        restSeconds: exercise.restSeconds
                    ))
                }
            }
            _exercises = State(initialValue: normalizedExercises)
            _sets = State(initialValue: proposed)
            _restDeadline = State(initialValue: nil)
            _restSourceSetID = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let resumeNotice {
                    Section {
                        Label(resumeNotice, systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section { compactWorkoutHeader }

                if let workoutValidationMessage {
                    Section("Fix before finishing") {
                        Label {
                            Text(workoutValidationMessage)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.coachAmber)
                        }
                        .font(.subheadline)
                    }
                }

                ForEach(exercises) { exercise in
                    Section {
                        if let recommendation = progressionRecommendation(for: exercise) {
                            progressionCard(recommendation, exercise: exercise)
                        }
                        if let catalogID = exercise.catalogID,
                           catalogStore.exercises.contains(where: { $0.id == catalogID }) {
                            Button {
                                detailExercise = catalogStore.exercises.first(where: { $0.id == catalogID })
                            } label: {
                                Label("Technique and Instructions", systemImage: "info.circle")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.coachIndigo)
                        }
                        if dynamicTypeSize.isAccessibilitySize {
                            ForEach($sets) { $set in
                                if set.exerciseID == exercise.id {
                                    accessibleSetEditor($set)
                                }
                            }
                        } else {
                            Grid(horizontalSpacing: 8, verticalSpacing: 10) {
                                GridRow {
                                    columnHeader("SET", width: 26)
                                    columnHeader("PREVIOUS", width: 70)
                                    columnHeader(loadUnit.symbol.uppercased(), width: 62)
                                        .accessibilityLabel("Load in \(loadUnit.spokenName)")
                                    columnHeader("REPS", width: 48)
                                    Image(systemName: "checkmark")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44)
                                        .accessibilityHidden(true)
                                }

                                ForEach($sets) { $set in
                                    if set.exerciseID == exercise.id {
                                        standardSetEditor($set)
                                    }
                                }
                            }
                        }
                        Button {
                            addSet(to: exercise)
                        } label: {
                            Label("Add Set", systemImage: "plus")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    } header: {
                        exerciseHeader(exercise)
                    }
                }

                Section {
                    Menu {
                        Button {
                            showingExerciseLibrary = true
                        } label: {
                            Label("From exercise library", systemImage: "books.vertical.fill")
                        }
                        Button {
                            showingCustomExercise = true
                        } label: {
                            Label("Create custom exercise", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Label("Add exercise", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }

                Section("Session notes") {
                    TextField("Energy, soreness, substitutions…", text: $notes, axis: .vertical)
                        .focused($focusedField, equals: .notes)
                }
            }
            .listSectionSpacing(14)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if restRemaining > 0 { restTimerBar }
            }
            .navigationTitle(templateName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showingDiscard = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { showingFinish = true }
                        .disabled(!sets.contains { $0.isComplete } || workoutValidationMessage != nil)
                        .accessibilityHint(
                            workoutValidationMessage
                                ?? "Saves the completed sets and ends this workout"
                        )
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .navigationDestination(item: $detailExercise) { exercise in
                ExerciseDetailView(
                    exercise: exercise,
                    allowsSelection: false,
                    isAlreadyInTemplate: true,
                    selectedIDs: $detailSelection
                )
            }
            .sheet(isPresented: $showingExerciseLibrary) {
                ExerciseLibraryView(existingCatalogIDs: Set(exercises.compactMap(\.catalogID))) { definitions in
                    definitions.forEach { appendExercise($0.workoutExercise(loadUnit: loadUnit)) }
                }
            }
            .sheet(isPresented: $showingCustomExercise) {
                ExerciseEditorView(showsTargetRPE: false) { appendExercise($0.converted(to: loadUnit)) }
            }
            .alert(item: $progressionExplanation) { recommendation in
                Alert(
                    title: Text("Why this progression?"),
                    message: Text(recommendation.rationale + " Only exercise-level sets logged in Dayvera are used."),
                    dismissButton: .default(Text("Got it"))
                )
            }
            .onReceive(ticker) { date in
                currentTime = date
                if let restDeadline, date >= restDeadline {
                    clearRestTimer()
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "Rest complete. Start your next set when ready."
                    )
                }
            }
            .onAppear { saveDraft() }
            .task { await catalogStore.load() }
            .onChange(of: exercises) { _, _ in saveDraft() }
            .onChange(of: sets) { _, _ in saveDraft() }
            .onChange(of: notes) { _, _ in saveDraft() }
            .onChange(of: restDeadline) { _, _ in saveDraft() }
            .onChange(of: restSourceSetID) { _, _ in saveDraft() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                normalizeDraftTimingIfNeeded()
            }
            .confirmationDialog(finishDialogTitle, isPresented: $showingFinish, titleVisibility: .visible) {
                Button(completedSetCount == 1 ? "Save 1 completed set" : "Save \(completedSetCount) completed sets") {
                    finishWorkout()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(finishDialogMessage)
            }
            .confirmationDialog("Leave this workout?", isPresented: $showingDiscard, titleVisibility: .visible) {
                Button("Save and close") {
                    saveDraft()
                    dismiss()
                }
                Button("Discard workout", role: .destructive) {
                    draftStore.clear()
                    dismiss()
                }
                Button("Keep training", role: .cancel) {}
            } message: {
                Text("Your draft is saved automatically, so you can resume it later—or discard it now.")
            }
        }
    }

    private var compactWorkoutHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Label(elapsed, systemImage: "timer")
                    Text("\(completedSetCount) of \(sets.count) sets complete")
                }
            } else {
                HStack(spacing: 12) {
                    Label(elapsed, systemImage: "timer")
                    Spacer(minLength: 8)
                    Text("\(completedSetCount)/\(sets.count) sets")
                        .foregroundStyle(.secondary)
                }
            }

        }
        .font(.headline.monospacedDigit())
        .padding(.vertical, 2)
    }

    private func progressionCard(
        _ recommendation: WorkoutProgressionRecommendation,
        exercise: WorkoutExercise
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(progressionSummary(recommendation), systemImage: progressionSymbol(recommendation))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(recommendation.action == .hold ? Color.secondary : Color.coachIndigo)
                .fixedSize(horizontal: false, vertical: true)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    progressionButtons(recommendation, exercise: exercise)
                }
            } else {
                HStack(spacing: 8) {
                    progressionButtons(recommendation, exercise: exercise)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func progressionButtons(
        _ recommendation: WorkoutProgressionRecommendation,
        exercise: WorkoutExercise
    ) -> some View {
        Button("Why") { progressionExplanation = recommendation }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityLabel("Why this progression for \(exercise.name)")

        if progressionUndo[exercise.id] != nil {
            Button("Undo") { undoProgression(for: exercise) }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityLabel("Undo progression for \(exercise.name)")
        } else if progressionAlreadyApplied(recommendation, to: exercise) {
            Label("Applied", systemImage: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.coachMint)
                .frame(minHeight: 44)
        } else if recommendation.canApply {
            Button("Apply") { applyProgression(recommendation, to: exercise) }
                .buttonStyle(.borderedProminent)
                .tint(Color.coachIndigo)
                .frame(minHeight: 44)
                .disabled(!sets.contains { $0.exerciseID == exercise.id && !$0.isComplete })
                .accessibilityLabel("Apply progression to \(exercise.name)")
        }
    }

    private func exerciseHeader(_ exercise: WorkoutExercise) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.headline)
                    .foregroundStyle(Color.coachIndigo)
                    .fixedSize(horizontal: false, vertical: true)
                if let position = exercises.firstIndex(where: { $0.id == exercise.id }) {
                    Text("Exercise \(position + 1) of \(exercises.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Menu {
                Button {
                    addSet(to: exercise)
                } label: {
                    Label("Add set", systemImage: "plus")
                }
                Button {
                    removeLastSet(from: exercise)
                } label: {
                    Label("Remove last set", systemImage: "minus")
                }
                .disabled(!canRemoveLastSet(from: exercise))

                if let definition = catalogDefinition(for: exercise) {
                    Button {
                        detailExercise = definition
                    } label: {
                        Label("Technique and instructions", systemImage: "info.circle")
                    }
                }

                Divider()
                Button(role: .destructive) {
                    removeExercise(exercise)
                } label: {
                    Label("Remove exercise", systemImage: "trash")
                }
                .disabled(!canRemoveExercise(exercise))
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(exercise.name)")
        }
    }

    private func columnHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: width)
    }

    private func standardSetEditor(_ set: Binding<ActiveSet>) -> some View {
        GridRow {
            Text("\(set.wrappedValue.setNumber)")
                .font(.subheadline.bold())
                .frame(width: 26)
            previousSetControl(set).frame(width: 70)
            weightField(set).frame(width: 62)
            repsField(set).frame(width: 48)
            completionButton(set).frame(width: 44)
        }
        .padding(.vertical, 3)
        .background(
            set.wrappedValue.isComplete ? Color.coachMint.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private func accessibleSetEditor(_ set: Binding<ActiveSet>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Set \(set.wrappedValue.setNumber)").font(.headline)
                Spacer()
                completionButton(set)
            }
            LabeledContent("Previous") { previousSetControl(set) }
            LabeledContent("Load (\(loadUnit.symbol))") { weightField(set).frame(maxWidth: 150) }
            LabeledContent("Repetitions") { repsField(set).frame(maxWidth: 150) }
        }
        .padding(8)
        .background(
            set.wrappedValue.isComplete ? Color.coachMint.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func previousSetControl(_ set: Binding<ActiveSet>) -> some View {
        Group {
            if let previous = previousSetPerformance(
                catalogID: set.wrappedValue.catalogID,
                exerciseName: set.wrappedValue.exerciseName,
                setNumber: set.wrappedValue.setNumber,
                from: sessions,
                displayedIn: loadUnit
            ) {
                Button {
                    set.wrappedValue.weight = previous.weight
                    set.wrappedValue.loadUnit = loadUnit
                    set.wrappedValue.reps = previous.reps
                    progressionUndo.removeValue(forKey: set.wrappedValue.exerciseID)
                } label: {
                    Text("\(formattedLoad(previous.weight))×\(previous.reps)")
                        .foregroundStyle(set.wrappedValue.isComplete ? Color.secondary : Color.coachIndigo)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(set.wrappedValue.isComplete)
                .accessibilityLabel(
                    "\(set.wrappedValue.exerciseName), set \(set.wrappedValue.setNumber), previous: "
                        + "\(formattedLoad(previous.weight)) \(loadUnit.spokenName) for \(previous.reps) repetitions"
                )
                .accessibilityHint("Copies the previous load and repetitions into this set")
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(
                        "\(set.wrappedValue.exerciseName), set \(set.wrappedValue.setNumber), no previous set"
                    )
            }
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private var restTimerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .foregroundStyle(Color.coachAmber)
                Text("Rest \(restClock)")
                    .font(.headline.monospacedDigit())
                if let restSourceDescription {
                    Text("· \(restSourceDescription)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            restTimerControls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var restTimerControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { restTimerButtons }
            VStack(alignment: .leading, spacing: 8) { restTimerButtons }
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var restTimerButtons: some View {
        Button("−15 sec") { adjustRestTimer(by: -15) }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
        Button("+15 sec") { adjustRestTimer(by: 15) }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
        Button("Skip Rest") { clearRestTimer() }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
    }

    private func weightField(_ set: Binding<ActiveSet>) -> some View {
        TextField("Weight", value: set.weight, format: .number.precision(.fractionLength(0...1)))
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: .weight(set.wrappedValue.id))
            .frame(minHeight: 44)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(
                "\(set.wrappedValue.exerciseName), set \(set.wrappedValue.setNumber), weight in \(loadUnit.spokenName)"
            )
    }

    private func repsField(_ set: Binding<ActiveSet>) -> some View {
        TextField("Reps", value: set.reps, format: .number)
            .keyboardType(.numberPad)
            .focused($focusedField, equals: .repetitions(set.wrappedValue.id))
            .frame(minHeight: 44)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(
                "\(set.wrappedValue.exerciseName), set \(set.wrappedValue.setNumber), repetitions"
            )
    }

    private func completionButton(_ set: Binding<ActiveSet>) -> some View {
        Button {
            set.wrappedValue.isComplete.toggle()
            if set.wrappedValue.isComplete {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                startRestTimer(after: set.wrappedValue)
            } else if restSourceSetID == set.wrappedValue.id {
                clearRestTimer()
            }
        } label: {
            Image(systemName: set.wrappedValue.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(set.wrappedValue.isComplete ? Color.coachMint : .secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(set.wrappedValue.exerciseName), set \(set.wrappedValue.setNumber), "
                + (set.wrappedValue.isComplete ? "mark incomplete" : "mark complete")
        )
    }

    private var elapsed: String {
        let seconds = max(Int(currentTime.timeIntervalSince(startedAt)), 0)
        if seconds >= 3_600 {
            return String(
                format: "%d:%02d:%02d",
                seconds / 3_600,
                (seconds % 3_600) / 60,
                seconds % 60
            )
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var restClock: String {
        String(format: "%d:%02d", restRemaining / 60, restRemaining % 60)
    }

    private var completedSetCount: Int {
        sets.filter(\.isComplete).count
    }

    private var finishDialogTitle: String {
        completedSetCount < sets.count ? "Finish partial workout?" : "Finish this workout?"
    }

    private var finishDialogMessage: String {
        let incompleteCount = max(sets.count - completedSetCount, 0)
        guard incompleteCount > 0 else {
            return "All completed sets will be saved to Training History."
        }
        let noun = incompleteCount == 1 ? "set" : "sets"
        return "\(incompleteCount) incomplete \(noun) will be left out. Your \(completedSetCount) completed \(completedSetCount == 1 ? "set" : "sets") will be saved."
    }

    private var restRemaining: Int {
        guard let restDeadline else { return 0 }
        return max(Int(ceil(restDeadline.timeIntervalSince(currentTime))), 0)
    }

    private var restSourceDescription: String? {
        guard let restSourceSetID,
              let source = sets.first(where: { $0.id == restSourceSetID }) else { return nil }
        return "\(source.exerciseName), set \(source.setNumber)"
    }

    private var workoutValidationMessage: String? {
        for set in sets where set.isComplete {
            if !set.weight.isFinite || !(0...loadUnit.maximumWorkoutLoad).contains(set.weight) {
                return "\(set.exerciseName), set \(set.setNumber): enter a load from 0 to \(loadUnit.maximumWorkoutLoad.formatted()) \(loadUnit.symbol)."
            }
            if !(1...1_000).contains(set.reps) {
                return "\(set.exerciseName), set \(set.setNumber): enter 1 to 1,000 repetitions."
            }
        }
        return nil
    }

    private func progressionRecommendation(
        for exercise: WorkoutExercise
    ) -> WorkoutProgressionRecommendation? {
        guard let recommendation = workoutProgressionRecommendation(
            for: exercise,
            sessions: sessions,
            displayedIn: loadUnit,
            allowsProgression: adjustment.allowProgression
        ) else { return nil }
        let editableSets = sets.filter { $0.exerciseID == exercise.id && !$0.isComplete }
        let currentSets = editableSets.isEmpty
            ? sets.filter { $0.exerciseID == exercise.id }
            : editableSets
        return nonRegressiveProgressionRecommendation(
            recommendation,
            currentDraftLoad: currentSets.map(\.weight).max() ?? exercise.targetWeight,
            currentDraftRepetitions: currentSets.map(\.reps).max() ?? exercise.targetReps
        )
    }

    private func progressionSummary(_ recommendation: WorkoutProgressionRecommendation) -> String {
        switch recommendation.action {
        case .increaseLoad:
            "Try \(formattedLoad(recommendation.suggestedLoad)) \(loadUnit.symbol) × \(recommendation.suggestedRepetitions)"
        case .increaseRepetitions:
            recommendation.suggestedLoad > 0
                ? "Try \(formattedLoad(recommendation.suggestedLoad)) \(loadUnit.symbol) × \(recommendation.suggestedRepetitions)"
                : "Try \(recommendation.suggestedRepetitions) repetitions"
        case .hold:
            recommendation.currentLoad > 0
                ? "Keep \(formattedLoad(recommendation.currentLoad)) \(loadUnit.symbol) × \(recommendation.currentRepetitions)"
                : "Keep \(recommendation.currentRepetitions) repetitions"
        }
    }

    private func progressionSymbol(_ recommendation: WorkoutProgressionRecommendation) -> String {
        switch recommendation.action {
        case .increaseLoad: "arrow.up.right.circle.fill"
        case .increaseRepetitions: "plus.circle.fill"
        case .hold: "equal.circle.fill"
        }
    }

    private func progressionAlreadyApplied(
        _ recommendation: WorkoutProgressionRecommendation,
        to exercise: WorkoutExercise
    ) -> Bool {
        let editable = sets.filter { $0.exerciseID == exercise.id && !$0.isComplete }
        guard !editable.isEmpty, recommendation.canApply else { return false }
        return editable.allSatisfy {
            $0.weight + 0.000_1 >= recommendation.suggestedLoad
                && $0.reps >= recommendation.suggestedRepetitions
        }
    }

    private func applyProgression(
        _ recommendation: WorkoutProgressionRecommendation,
        to exercise: WorkoutExercise
    ) {
        let editableIndices = sets.indices.filter {
            sets[$0].exerciseID == exercise.id && !sets[$0].isComplete
        }
        guard !editableIndices.isEmpty else { return }
        progressionUndo[exercise.id] = editableIndices.map {
            ActiveSetProgressionSnapshot(
                id: sets[$0].id,
                weight: sets[$0].weight,
                repetitions: sets[$0].reps
            )
        }
        sets = applyingProgressionRecommendation(
            recommendation,
            to: sets,
            exerciseID: exercise.id,
            loadUnit: loadUnit
        )
    }

    private func undoProgression(for exercise: WorkoutExercise) {
        guard let snapshots = progressionUndo.removeValue(forKey: exercise.id) else { return }
        sets = restoringProgressionSnapshot(
            in: sets,
            exerciseID: exercise.id,
            snapshots: snapshots
        )
    }

    private func appendExercise(_ exercise: WorkoutExercise) {
        if let catalogID = exercise.catalogID,
           exercises.contains(where: { $0.catalogID == catalogID }) {
            return
        }
        let normalized = exercise.converted(to: loadUnit)
        exercises.append(normalized)
        let count = adaptedWorkingSetCounts(
            for: [normalized],
            volumeMultiplier: adjustment.volumeMultiplier
        )[normalized.id, default: max(normalized.workingSets, 1)]
        for number in 1...max(count, 1) {
            sets.append(ActiveSet(
                exerciseID: normalized.id,
                catalogID: normalized.catalogID,
                exerciseName: normalized.name,
                setNumber: number,
                weight: normalized.targetWeight,
                loadUnit: loadUnit,
                reps: normalized.targetReps,
                restSeconds: normalized.restSeconds
            ))
        }
    }

    private func addSet(to exercise: WorkoutExercise) {
        let exerciseSets = sets.filter { $0.exerciseID == exercise.id }
        let latest = exerciseSets.max(by: { $0.setNumber < $1.setNumber })
        sets.append(ActiveSet(
            exerciseID: exercise.id,
            catalogID: exercise.catalogID,
            exerciseName: exercise.name,
            setNumber: (latest?.setNumber ?? 0) + 1,
            weight: latest?.weight ?? exercise.targetWeight,
            loadUnit: loadUnit,
            reps: latest?.reps ?? exercise.targetReps,
            restSeconds: exercise.restSeconds
        ))
        progressionUndo.removeValue(forKey: exercise.id)
    }

    private func removeLastSet(from exercise: WorkoutExercise) {
        let exerciseSets = sets.filter { $0.exerciseID == exercise.id }
        guard exerciseSets.count > 1,
              let last = exerciseSets.max(by: { $0.setNumber < $1.setNumber }),
              !last.isComplete,
              let index = sets.firstIndex(where: { $0.id == last.id }) else { return }
        if restSourceSetID == last.id { clearRestTimer() }
        sets.remove(at: index)
        progressionUndo.removeValue(forKey: exercise.id)
    }

    private func removeExercise(_ exercise: WorkoutExercise) {
        guard canRemoveExercise(exercise) else { return }
        let removedSetIDs = Set(sets.filter { $0.exerciseID == exercise.id }.map(\.id))
        if let restSourceSetID, removedSetIDs.contains(restSourceSetID) { clearRestTimer() }
        sets.removeAll { $0.exerciseID == exercise.id }
        exercises.removeAll { $0.id == exercise.id }
        progressionUndo.removeValue(forKey: exercise.id)
    }

    private func canRemoveLastSet(from exercise: WorkoutExercise) -> Bool {
        let exerciseSets = sets.filter { $0.exerciseID == exercise.id }
        guard exerciseSets.count > 1,
              let last = exerciseSets.max(by: { $0.setNumber < $1.setNumber }) else { return false }
        return !last.isComplete
    }

    private func canRemoveExercise(_ exercise: WorkoutExercise) -> Bool {
        !sets.contains { $0.exerciseID == exercise.id && $0.isComplete }
    }

    private func catalogDefinition(for exercise: WorkoutExercise) -> ExerciseDefinition? {
        guard let catalogID = exercise.catalogID else { return nil }
        return catalogStore.exercises.first(where: { $0.id == catalogID })
    }

    private func startRestTimer(after set: ActiveSet, now: Date = .now) {
        guard set.restSeconds > 0 else {
            clearRestTimer()
            return
        }
        restSourceSetID = set.id
        restDeadline = now.addingTimeInterval(Double(set.restSeconds))
        currentTime = now
        UIAccessibility.post(
            notification: .announcement,
            argument: "Rest timer started for \(set.restSeconds) seconds after \(set.exerciseName), set \(set.setNumber)."
        )
    }

    private func adjustRestTimer(by seconds: TimeInterval, now: Date = .now) {
        guard let restDeadline else { return }
        let adjusted = restDeadline.addingTimeInterval(seconds)
        guard adjusted > now else {
            clearRestTimer()
            return
        }
        self.restDeadline = adjusted
        currentTime = now
    }

    private func clearRestTimer() {
        restDeadline = nil
        restSourceSetID = nil
    }

    private func formattedLoad(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func saveDraft() {
        let saved = draftStore.save(.init(
            templateID: templateID,
            templateName: templateName,
            exercises: exercises,
            startedAt: startedAt,
            sets: sets,
            notes: notes,
            restDeadline: restDeadline,
            restSourceSetID: restSourceSetID
        ))
        if !saved {
            resumeNotice = "This draft couldn’t be autosaved. Keep Dayvera open until you finish or try again after unlocking your iPhone."
        }
    }

    private func normalizeDraftTimingIfNeeded(now: Date = .now) {
        let normalizedStart = normalizedWorkoutStart(savedStart: startedAt, now: now)
        currentTime = now
        guard normalizedStart != startedAt else { return }

        startedAt = normalizedStart
        clearRestTimer()
        resumeNotice = "This draft was from an earlier session, so its timer restarted. Your sets and notes were kept."
        saveDraft()
    }

    private func finishWorkout() {
        guard workoutValidationMessage == nil else { return }
        let end = Date.now
        let effectiveStart = validWorkoutIntervalStart(savedStart: startedAt, end: end)
        let completed = sets.filter(\.isComplete).map { activeSet in
            let exercise = exercises.first(where: { $0.id == activeSet.exerciseID })
            return CompletedSet(
                exerciseID: activeSet.exerciseID,
                catalogID: activeSet.catalogID,
                muscleGroup: exercise?.muscleGroup,
                equipment: exercise?.equipment,
                movementPattern: exercise?.movementPattern,
                exerciseName: activeSet.exerciseName,
                setNumber: activeSet.setNumber,
                weight: activeSet.weight,
                loadUnit: activeSet.loadUnit ?? loadUnit,
                reps: activeSet.reps,
                isWarmup: false,
                completedAt: end
            )
        }
        let record = WorkoutSessionRecord(
            templateID: templateID,
            templateName: templateName,
            startedAt: effectiveStart,
            endedAt: end,
            readiness: appModel.snapshot.readinessBand,
            readinessScore: appModel.snapshot.readinessScore,
            readinessAvailable: appModel.snapshot.readinessAvailable,
            sets: completed,
            notes: notes
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            appModel.notice = "The workout could not be saved: \(error.localizedDescription)"
            return
        }
        draftStore.clear()
        Task { await appModel.recordStrengthWorkout(record, in: modelContext) }
        dismiss()
    }
}
