import Combine
import SwiftData
import SwiftUI

struct WorkoutsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var appModel: AppModel
    @Query(sort: \WorkoutTemplateRecord.createdAt) private var templates: [WorkoutTemplateRecord]
    @Query(sort: \WorkoutSessionRecord.startedAt, order: .reverse) private var sessions: [WorkoutSessionRecord]
    @State private var showingNewTemplate = false
    @State private var templateToEdit: WorkoutTemplateRecord?
    @State private var activeTemplate: WorkoutTemplateRecord?
    @State private var activeDraft: ActiveWorkoutDraft?
    @State private var templateToDelete: WorkoutTemplateRecord?
    @State private var showingDiscardDraft = false
    @State private var showingDebugProgress = false
    @State private var appliedDebugRoute = false
    private let draftStore = ActiveWorkoutDraftStore()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let draft = activeDraft,
                   let template = templates.first(where: { $0.id == draft.templateID }) {
                    draftCard(draft, template: template)
                }

                todayTrainingCard
                templateSectionHeader

                if templates.isEmpty {
                    emptyTemplatesCard
                } else {
                    ForEach(templates) { template in
                        templateCard(template)
                    }
                }

                progressNavigationCard
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Train")
        .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
        .sheet(isPresented: $showingNewTemplate) { TemplateEditorView() }
        .sheet(item: $templateToEdit) { template in
            TemplateEditorView(template: template)
        }
        .fullScreenCover(item: $activeTemplate, onDismiss: loadDraftState) { template in
            ActiveWorkoutView(template: template, adjustment: appModel.plan.workoutAdjustment)
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

    private var todayTrainingCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Today's training")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: appModel.snapshot.readinessAvailable ? appModel.snapshot.readinessBand.symbol : "ellipsis.circle")
                        .foregroundStyle(appModel.snapshot.readinessAvailable ? appModel.snapshot.readinessBand.color : Color.coachIndigo)
                }
                .font(.caption.weight(.semibold))
                Text(appModel.plan.workoutAdjustment.title)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text(appModel.plan.workoutAdjustment.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var templateSectionHeader: some View {
        let title = activeDraft == nil ? "Start a workout" : "Workout templates"
        let subtitle = activeDraft == nil
            ? "Choose a template; today's readiness adjustment is applied when you start."
            : "Finish or discard the workout in progress before starting another."
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: title, subtitle: subtitle)
                newTemplateButton
            }
        } else {
            HStack(alignment: .bottom, spacing: 12) {
                SectionTitle(title: title, subtitle: subtitle)
                newTemplateButton
            }
        }
    }

    private var newTemplateButton: some View {
        Button {
            showingNewTemplate = true
        } label: {
            Label("New template", systemImage: "plus")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Build a workout from library or custom exercises")
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
                    Label("Create template", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.coachIndigo)
            }
        }
    }

    private var progressNavigationCard: some View {
        NavigationLink {
            TrainingHistoryView()
        } label: {
            CoachCard {
                HStack(spacing: 14) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2)
                        .foregroundStyle(Color.coachIndigo)
                        .frame(width: 44, height: 44)
                        .background(Color.coachIndigo.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Training history")
                            .font(.headline)
                        Text(progressSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows training trends and completed sessions")
    }

    private var progressSummary: String {
        guard let latest = sessions.first else { return "Completed workouts and training trends" }
        return "Last completed \(latest.startedAt.shortDay)"
    }

    private func templateCard(_ template: WorkoutTemplateRecord) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(template.name).font(.title3.bold())
                        Text("\(template.exercises.count) exercises · \(adaptedSetCount(template)) working sets today")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        if activeDraft?.templateID == template.id {
                            Button("Finish workout to edit", systemImage: "lock.fill") {}
                                .disabled(true)
                            Button("Finish workout to delete", systemImage: "lock.fill") {}
                                .disabled(true)
                        } else {
                            Button("Edit template", systemImage: "pencil") { templateToEdit = template }
                            Button("Delete…", role: .destructive) { templateToDelete = template }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("More options for \(template.name)")
                }

                ForEach(template.exercises.prefix(3)) { exercise in
                    templateExercisePreview(exercise)
                }

                if template.exercises.count > 3 {
                    Text("+ \(template.exercises.count - 3) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let lastCompleted = lastCompletedDate(for: template) {
                    Label("Last completed \(lastCompleted.shortDay)", systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if activeDraft == nil {
                    Button {
                        activeTemplate = template
                    } label: {
                        Label("Start workout", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.coachIndigo)
                } else if activeDraft?.templateID != template.id {
                    Label("Unavailable while another workout is active", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func draftCard(_ draft: ActiveWorkoutDraft, template: WorkoutTemplateRecord) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Workout in progress", systemImage: "figure.strengthtraining.traditional")
                    .font(.headline)
                    .foregroundStyle(Color.coachIndigo)
                Text("\(template.name) · \(draft.sets.filter(\.isComplete).count) of \(draft.sets.count) sets complete")
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
        guard templates.contains(where: { $0.id == draft.templateID }) else {
            draftStore.clear()
            activeDraft = nil
            return
        }
        activeDraft = draft
    }
}

struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

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
            exercises.append(definition.workoutExercise())
        }
    }

    private func prescriptionSummary(for exercise: WorkoutExercise) -> String {
        "\(exercise.workingSets) sets × \(exercise.targetReps) reps · \(exercise.targetWeight.formatted(.number.precision(.fractionLength(0...1)))) lb · RPE \(exercise.targetRPE.formatted(.number.precision(.fractionLength(0...1)))) · \(exercise.restSeconds)s rest"
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
                    "Load: \(exercise.targetWeight.formatted(.number.precision(.fractionLength(0...1)))) lb",
                    value: $exercise.targetWeight,
                    in: 0...1000,
                    step: 2.5
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
    }
}

private struct ExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (WorkoutExercise) -> Void
    @State private var name = ""
    @State private var muscle: MuscleGroup = .fullBody
    @State private var sets = 3
    @State private var reps = 8
    @State private var weight = 45.0
    @State private var rpe = 8.0
    @State private var rest = 120

    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise name", text: $name)
                Picker("Muscle group", selection: $muscle) {
                    ForEach(MuscleGroup.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Working sets: \(sets)", value: $sets, in: 1...10)
                Stepper("Target reps: \(reps)", value: $reps, in: 1...30)
                Stepper("Load: \(weight, specifier: "%.1f") lb", value: $weight, in: 0...1000, step: 2.5)
                Stepper("Target RPE: \(rpe, specifier: "%.1f")", value: $rpe, in: 5...10, step: 0.5)
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
    var reps: Int
    var rpe: Double
    let restSeconds: Int
    var isComplete = false
}

func backfillingCatalogIDs(
    in sets: [ActiveSet],
    from exercises: [WorkoutExercise]
) -> [ActiveSet] {
    let catalogIDByExercise = exercises.reduce(into: [UUID: String]()) { result, exercise in
        if let catalogID = exercise.catalogID, !catalogID.isEmpty {
            result[exercise.id] = catalogID
        }
    }
    return sets.map { set in
        guard set.catalogID == nil, let catalogID = catalogIDByExercise[set.exerciseID] else {
            return set
        }
        var updated = set
        updated.catalogID = catalogID
        return updated
    }
}

private struct ActiveWorkoutDraft: Codable, Hashable {
    let templateID: UUID
    let startedAt: Date
    let sets: [ActiveSet]
    let notes: String
}

private struct ActiveWorkoutDraftStore {
    private static let key = "activeWorkoutDraft"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ActiveWorkoutDraft? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(ActiveWorkoutDraft.self, from: data)
    }

    func save(_ draft: ActiveWorkoutDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let templateID: UUID
    let templateName: String
    let exercises: [WorkoutExercise]
    let adjustment: WorkoutAdjustment
    @State private var sets: [ActiveSet]
    @State private var startedAt = Date.now
    @State private var currentTime = Date.now
    @State private var restDeadline: Date?
    @State private var showingFinish = false
    @State private var showingDiscard = false
    @State private var notes = ""
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let draftStore = ActiveWorkoutDraftStore()

    init(template: WorkoutTemplateRecord, adjustment: WorkoutAdjustment) {
        templateID = template.id
        templateName = template.name
        exercises = template.exercises
        self.adjustment = adjustment
        if let draft = ActiveWorkoutDraftStore().load(), draft.templateID == template.id {
            _sets = State(initialValue: backfillingCatalogIDs(in: draft.sets, from: template.exercises))
            _startedAt = State(initialValue: draft.startedAt)
            _notes = State(initialValue: draft.notes)
        } else {
            var proposed: [ActiveSet] = []
            let setCounts = adaptedWorkingSetCounts(for: template.exercises, volumeMultiplier: adjustment.volumeMultiplier)
            for exercise in template.exercises {
                let count = setCounts[exercise.id, default: exercise.workingSets]
                for number in 1...count {
                    proposed.append(.init(
                        exerciseID: exercise.id,
                        catalogID: exercise.catalogID,
                        exerciseName: exercise.name,
                        setNumber: number,
                        weight: exercise.targetWeight,
                        reps: exercise.targetReps,
                        rpe: min(exercise.targetRPE, adjustment.rpeCap ?? 10),
                        restSeconds: exercise.restSeconds
                    ))
                }
            }
            _sets = State(initialValue: proposed)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label(elapsed, systemImage: "timer")
                        Spacer()
                        if restRemaining > 0 {
                            Label {
                                Text("Rest \(restRemaining)s")
                            } icon: {
                                Image(systemName: "hourglass").foregroundStyle(Color.coachAmber)
                            }
                        }
                    }
                    .font(.headline.monospacedDigit())
                }

                ForEach(exercises) { exercise in
                    Section(exercise.name) {
                        if dynamicTypeSize.isAccessibilitySize {
                            ForEach($sets) { $set in
                                if set.exerciseID == exercise.id {
                                    accessibleSetEditor($set)
                                }
                            }
                        } else {
                            Grid(horizontalSpacing: 8, verticalSpacing: 10) {
                                GridRow {
                                    columnHeader("SET", width: 28)
                                    columnHeader("LB", width: 64)
                                    columnHeader("REPS", width: 52)
                                    columnHeader("RPE", width: 52)
                                    Color.clear.frame(width: 32, height: 1)
                                }

                                ForEach($sets) { $set in
                                    if set.exerciseID == exercise.id {
                                        standardSetEditor($set)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Session notes") { TextField("Energy, soreness, substitutions…", text: $notes, axis: .vertical) }
            }
            .navigationTitle(templateName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showingDiscard = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { showingFinish = true }.disabled(!sets.contains { $0.isComplete })
                }
            }
            .onReceive(ticker) { date in
                currentTime = date
                if let restDeadline, date >= restDeadline { self.restDeadline = nil }
            }
            .onAppear { saveDraft() }
            .onChange(of: sets) { _, _ in saveDraft() }
            .onChange(of: notes) { _, _ in saveDraft() }
            .confirmationDialog("Finish this workout?", isPresented: $showingFinish, titleVisibility: .visible) {
                Button("Save completed sets") { finishWorkout() }
                Button("Cancel", role: .cancel) {}
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
                .frame(width: 28)
            weightField(set).frame(width: 64)
            repsField(set).frame(width: 52)
            rpeField(set).frame(width: 52)
            completionButton(set).frame(width: 32)
        }
        .padding(.vertical, 3)
        .opacity(set.wrappedValue.isComplete ? 0.6 : 1)
    }

    private func accessibleSetEditor(_ set: Binding<ActiveSet>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Set \(set.wrappedValue.setNumber)").font(.headline)
                Spacer()
                completionButton(set)
            }
            LabeledContent("Weight (lb)") { weightField(set).frame(maxWidth: 150) }
            LabeledContent("Repetitions") { repsField(set).frame(maxWidth: 150) }
            LabeledContent("Effort (RPE)") { rpeField(set).frame(maxWidth: 150) }
        }
        .padding(.vertical, 5)
        .opacity(set.wrappedValue.isComplete ? 0.6 : 1)
    }

    private func weightField(_ set: Binding<ActiveSet>) -> some View {
        TextField("Weight", value: set.weight, format: .number.precision(.fractionLength(0...1)))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Set \(set.wrappedValue.setNumber) weight in pounds")
    }

    private func repsField(_ set: Binding<ActiveSet>) -> some View {
        TextField("Reps", value: set.reps, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Set \(set.wrappedValue.setNumber) repetitions")
    }

    private func rpeField(_ set: Binding<ActiveSet>) -> some View {
        TextField("RPE", value: set.rpe, format: .number.precision(.fractionLength(0...1)))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Set \(set.wrappedValue.setNumber) effort RPE")
    }

    private func completionButton(_ set: Binding<ActiveSet>) -> some View {
        Button {
            set.wrappedValue.isComplete.toggle()
            restDeadline = set.wrappedValue.isComplete
                ? Date.now.addingTimeInterval(Double(set.wrappedValue.restSeconds))
                : nil
        } label: {
            Image(systemName: set.wrappedValue.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(set.wrappedValue.isComplete ? Color.coachMint : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(set.wrappedValue.isComplete ? "Mark set incomplete" : "Complete set")
    }

    private var elapsed: String {
        let seconds = max(Int(currentTime.timeIntervalSince(startedAt)), 0)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var restRemaining: Int {
        guard let restDeadline else { return 0 }
        return max(Int(ceil(restDeadline.timeIntervalSince(currentTime))), 0)
    }

    private func saveDraft() {
        draftStore.save(.init(templateID: templateID, startedAt: startedAt, sets: sets, notes: notes))
    }

    private func finishWorkout() {
        let completed = sets.filter(\.isComplete).map {
            CompletedSet(
                exerciseID: $0.exerciseID,
                catalogID: $0.catalogID,
                exerciseName: $0.exerciseName,
                setNumber: $0.setNumber,
                weight: $0.weight,
                reps: $0.reps,
                rpe: $0.rpe,
                isWarmup: false,
                completedAt: .now
            )
        }
        let end = Date.now
        let record = WorkoutSessionRecord(
            templateID: templateID,
            templateName: templateName,
            startedAt: startedAt,
            endedAt: end,
            readiness: appModel.snapshot.readinessBand,
            readinessScore: appModel.snapshot.readinessScore,
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
        Task { await appModel.recordStrengthWorkout(start: startedAt, end: end) }
        dismiss()
    }
}
