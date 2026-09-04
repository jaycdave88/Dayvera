import Foundation
import SwiftUI
import UIKit

@MainActor
struct ExerciseLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var store: ExerciseCatalogStore

    private let existingCatalogIDs: Set<String>
    private let onCommit: (([ExerciseDefinition]) -> Void)?

    @State private var searchText = ""
    @State private var selectedEquipment: String?
    @State private var selectedMuscle: String?
    @State private var selectedDifficulty: String?
    @State private var selectedIDs: [String] = []
    @State private var showingFilters = false
    @State private var detailExercise: ExerciseDefinition?
    @State private var appliedDebugRoute = false

    /// A navigation destination for the first-class Exercises tab.
    init() {
        _store = ObservedObject(wrappedValue: ExerciseCatalogStore.shared)
        existingCatalogIDs = []
        onCommit = nil
    }

    /// A browse-only destination with an injected store, primarily for previews and tests.
    init(store: ExerciseCatalogStore) {
        _store = ObservedObject(wrappedValue: store)
        existingCatalogIDs = []
        onCommit = nil
    }

    /// A sheet-ready, navigation-owning multi-select library for template building.
    init(
        existingCatalogIDs: Set<String> = [],
        onCommit: @escaping ([ExerciseDefinition]) -> Void
    ) {
        _store = ObservedObject(wrappedValue: ExerciseCatalogStore.shared)
        self.existingCatalogIDs = existingCatalogIDs
        self.onCommit = onCommit
    }

    /// Selection-mode injection point for previews and tests.
    init(
        store: ExerciseCatalogStore,
        existingCatalogIDs: Set<String> = [],
        onCommit: @escaping ([ExerciseDefinition]) -> Void
    ) {
        _store = ObservedObject(wrappedValue: store)
        self.existingCatalogIDs = existingCatalogIDs
        self.onCommit = onCommit
    }

    var body: some View {
        Group {
            if isSelectionMode {
                NavigationStack { libraryRoot }
            } else {
                libraryRoot
            }
        }
        .sheet(isPresented: $showingFilters) {
            ExerciseFilterSheet(
                equipment: $selectedEquipment,
                muscle: $selectedMuscle,
                difficulty: $selectedDifficulty,
                equipmentOptions: equipmentOptions,
                muscleOptions: muscleOptions,
                difficultyOptions: difficultyOptions
            )
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        }
        .task {
            await store.load()
            applyDebugRouteIfNeeded()
        }
    }

    private var libraryRoot: some View {
        libraryContent
            .navigationTitle(isSelectionMode ? "Add Exercises" : "Exercises")
            .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search exercises"
            )
            .toolbar {
                if isSelectionMode {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelectionMode { selectionCommitBar }
            }
            .navigationDestination(item: $detailExercise) { exercise in
                detailView(for: exercise)
            }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if store.exercises.isEmpty {
            if store.isLoading {
                loadingState
            } else if let errorMessage = store.errorMessage {
                errorState(errorMessage)
            } else {
                loadingState
            }
        } else {
            catalogList
        }
    }

    private var catalogList: some View {
        List {
            Section {
                filterControls
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)

            if let errorMessage = store.errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("The saved catalog is still available", systemImage: "wifi.exclamationmark")
                            .font(.subheadline.bold())
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Retry update") {
                            Task { await store.load(forceRefresh: true) }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if filteredExercises.isEmpty {
                Section { noResultsRow }
            } else if isShowingResults {
                Section {
                    ForEach(filteredExercises) { exercise in
                        exerciseRow(exercise)
                    }
                } header: {
                    Text(resultSummary)
                }
            } else {
                ForEach(alphabetSections) { section in
                    Section(section.title) {
                        ForEach(section.exercises) { exercise in
                            exerciseRow(exercise)
                        }
                    }
                }
            }

            Section { attributionFooter }
                .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.load(forceRefresh: true) }
    }

    @ViewBuilder
    private var filterControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Button { showingFilters = true } label: {
                Label(
                    filterButtonTitle,
                    systemImage: activeFilterCount == 0
                        ? "line.3.horizontal.decrease"
                        : "line.3.horizontal.decrease.circle.fill"
                )
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Choose equipment, muscle, and difficulty filters")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterMenu(title: "Equipment", selection: $selectedEquipment, options: equipmentOptions)
                    filterMenu(title: "Muscle", selection: $selectedMuscle, options: muscleOptions)
                    filterMenu(title: "Level", selection: $selectedDifficulty, options: difficultyOptions)
                    if activeFilterCount > 0 {
                        Button("Clear") { clearFilters() }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .frame(minHeight: 44)
                    }
                }
            }
        }
    }

    private func filterMenu(
        title: String,
        selection: Binding<String?>,
        options: [String]
    ) -> some View {
        Menu {
            Button {
                selection.wrappedValue = nil
            } label: {
                if selection.wrappedValue == nil {
                    Label("Any \(title.lowercased())", systemImage: "checkmark")
                } else {
                    Text("Any \(title.lowercased())")
                }
            }
            Divider()
            ForEach(options, id: \.self) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    if selection.wrappedValue == option {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selection.wrappedValue ?? title)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selection.wrappedValue == nil ? Color.primary : Color.coachIndigo)
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
            .background(
                selection.wrappedValue == nil ? Color.coachSurface : Color.coachIndigo.opacity(0.14),
                in: Capsule()
            )
        }
        .accessibilityLabel(selection.wrappedValue.map { "\(title), \($0)" } ?? "\(title), any")
    }

    @ViewBuilder
    private func exerciseRow(_ exercise: ExerciseDefinition) -> some View {
        if onCommit == nil {
            NavigationLink {
                detailView(for: exercise)
            } label: {
                ExerciseLibraryRow(exercise: exercise)
            }
        } else {
            selectionRow(exercise)
        }
    }

    private func selectionRow(_ exercise: ExerciseDefinition) -> some View {
        let isExisting = existingCatalogIDs.contains(exercise.id)
        let isSelected = selectedIDs.contains(exercise.id)
        return HStack(spacing: 8) {
            Button {
                toggleSelection(exercise.id)
            } label: {
                HStack(spacing: 10) {
                    ExerciseLibraryRow(exercise: exercise)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                    Image(systemName: isExisting || isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isExisting ? Color.secondary : Color.coachIndigo)
                        .frame(width: 44, height: 44)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .disabled(isExisting)
            .accessibilityLabel(
                isExisting
                    ? "\(exercise.name), already in template"
                    : (isSelected ? "Remove \(exercise.name) from selection" : "Select \(exercise.name)")
            )

            Button {
                detailExercise = exercise
            } label: {
                Image(systemName: "info.circle")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .fixedSize()
            .accessibilityLabel("About \(exercise.name)")
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 4 : 0)
    }

    private func detailView(for exercise: ExerciseDefinition) -> some View {
        ExerciseDetailView(
            exercise: exercise,
            allowsSelection: onCommit != nil,
            isAlreadyInTemplate: existingCatalogIDs.contains(exercise.id),
            selectedIDs: $selectedIDs
        )
    }

    private var selectionCommitBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                commitSelection()
            } label: {
                Text(commitButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.coachIndigo)
            .disabled(selectedIDs.isEmpty)
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial)
    }

    private var attributionFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Link(destination: ExerciseCatalogSource.homepageURL) {
                Label(ExerciseCatalogSource.attribution, systemImage: "arrow.up.right.square")
            }
            Text("The catalog is saved after its first successful download. Viewed illustrations are cached when possible.")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .padding(.vertical, 8)
        .accessibilityHint("Opens the RepDB website")
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            SwiftUI.ProgressView()
                .controlSize(.large)
            Text("Loading exercise library…")
                .font(.headline)
            Text("A saved catalog is used whenever one is available.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Exercise library unavailable", systemImage: "wifi.slash")
        } description: {
            Text("\(message) Connect once to save the catalog for offline use.")
        } actions: {
            Button("Retry") {
                Task { await store.load(forceRefresh: true) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var noResultsRow: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(Color.coachIndigo)
            Text("No exercises found")
                .font(.headline)
            Text("Try another search or clear your filters.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Clear search and filters") {
                searchText = ""
                clearFilters()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.coachIndigo)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .listRowBackground(Color.clear)
    }

    private var filteredExercises: [ExerciseDefinition] {
        store.exercises.filter {
            $0.matches(
                query: searchText,
                equipment: selectedEquipment,
                muscle: selectedMuscle,
                difficulty: selectedDifficulty
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var alphabetSections: [ExerciseAlphabetSection] {
        let grouped = Dictionary(grouping: filteredExercises) { exercise in
            guard let first = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).first,
                  first.isLetter else { return "#" }
            return String(first).uppercased()
        }
        return grouped.keys
            .sorted { lhs, rhs in
                if lhs == "#" { return false }
                if rhs == "#" { return true }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            .map { ExerciseAlphabetSection(title: $0, exercises: grouped[$0, default: []]) }
    }

    private var equipmentOptions: [String] {
        sortedUnique(store.exercises.map(\.equipmentTitle))
    }

    private var muscleOptions: [String] {
        let values = store.exercises.flatMap { exercise in
            [exercise.bodyPartTitle]
                + exercise.primaryMuscles.map { catalogTitle($0) }
                + exercise.secondaryMuscles.map { catalogTitle($0) }
        }
        return sortedUnique(values)
    }

    private var difficultyOptions: [String] {
        sortedUnique(store.exercises.map(\.difficultyTitle))
    }

    private var activeFilterCount: Int {
        [selectedEquipment, selectedMuscle, selectedDifficulty].compactMap { $0 }.count
    }

    private var isSelectionMode: Bool { onCommit != nil }

    private var isShowingResults: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activeFilterCount > 0
    }

    private var filterButtonTitle: String {
        activeFilterCount == 0 ? "Filters" : "Filters, \(activeFilterCount) active"
    }

    private var resultSummary: String {
        "\(filteredExercises.count) \(filteredExercises.count == 1 ? "result" : "results")"
    }

    private var commitButtonTitle: String {
        guard !selectedIDs.isEmpty else { return "Add Exercises" }
        return "Add \(selectedIDs.count) \(selectedIDs.count == 1 ? "Exercise" : "Exercises")"
    }

    private func toggleSelection(_ id: String) {
        guard !existingCatalogIDs.contains(id) else { return }
        if let index = selectedIDs.firstIndex(of: id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(id)
        }
    }

    private func commitSelection() {
        let lookup = Dictionary(uniqueKeysWithValues: store.exercises.map { ($0.id, $0) })
        let exercises = selectedIDs.compactMap { lookup[$0] }
        guard !exercises.isEmpty else { return }
        onCommit?(exercises)
        dismiss()
    }

    private func clearFilters() {
        selectedEquipment = nil
        selectedMuscle = nil
        selectedDifficulty = nil
    }

    private func applyDebugRouteIfNeeded() {
        #if DEBUG
        guard !appliedDebugRoute else { return }
        let prefix = "--show-exercise="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else { return }
        let identifier = String(argument.dropFirst(prefix.count))
        guard let exercise = store.exercises.first(where: { $0.id == identifier }) else { return }
        appliedDebugRoute = true
        detailExercise = exercise
        #endif
    }

    private func sortedUnique(_ values: [String]) -> [String] {
        Array(Set(values.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func catalogTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private struct ExerciseAlphabetSection: Identifiable {
    let title: String
    let exercises: [ExerciseDefinition]
    var id: String { title }
}

private struct ExerciseFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var equipment: String?
    @Binding var muscle: String?
    @Binding var difficulty: String?

    let equipmentOptions: [String]
    let muscleOptions: [String]
    let difficultyOptions: [String]

    var body: some View {
        NavigationStack {
            Form {
                filterPicker("Equipment", selection: $equipment, options: equipmentOptions)
                filterPicker("Muscle", selection: $muscle, options: muscleOptions)
                filterPicker("Difficulty", selection: $difficulty, options: difficultyOptions)
            }
            .navigationTitle("Filter Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        equipment = nil
                        muscle = nil
                        difficulty = nil
                    }
                    .disabled(equipment == nil && muscle == nil && difficulty == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func filterPicker(_ title: String, selection: Binding<String?>, options: [String]) -> some View {
        Picker(title, selection: selection) {
            Text("Any").tag(Optional<String>.none)
            ForEach(options, id: \.self) { option in
                Text(option).tag(Optional(option))
            }
        }
    }
}

private struct ExerciseLibraryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let exercise: ExerciseDefinition

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 9) {
                    thumbnail.frame(width: 96, height: 96)
                    description
                }
            } else {
                HStack(spacing: 12) {
                    thumbnail.frame(width: 68, height: 68)
                    description
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var thumbnail: some View {
        CachedExerciseImage(
            url: exercise.thumbnailURL,
            accessibilityLabel: "\(exercise.name) exercise illustration",
            showsProgress: false
        )
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(exercise.primaryMuscleTitle) · \(exercise.equipmentTitle)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(exercise.difficultyTitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ExerciseDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let exercise: ExerciseDefinition
    let allowsSelection: Bool
    let isAlreadyInTemplate: Bool
    @Binding var selectedIDs: [String]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ExerciseMediaViewer(exercise: exercise)
                overviewCard
                instructionsSection
                if !exercise.tips.isEmpty { tipsSection }
                safetyCard
                attributionCard
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if allowsSelection { detailSelectionBar }
        }
    }

    private var overviewCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(exercise.name)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                if let summary = exercise.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) { metadataItems }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { metadataItems }
                            VStack(alignment: .leading, spacing: 8) { metadataItems }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var metadataItems: some View {
        ExerciseMetadataLabel(symbol: "figure.strengthtraining.traditional", text: exercise.primaryMuscleTitle)
        ExerciseMetadataLabel(symbol: "dumbbell.fill", text: exercise.equipmentTitle)
        ExerciseMetadataLabel(symbol: "chart.bar.fill", text: exercise.difficultyTitle)
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "How to Perform")
            if exercise.instructions.isEmpty {
                Text("Step-by-step instructions are not available for this exercise yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.coachIndigo, in: Circle())
                            .accessibilityHidden(true)
                        Text(instruction)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(Color.coachSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Step \(index + 1). \(instruction)")
                }
            }
        }
    }

    private var tipsSection: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Technique tips", systemImage: "lightbulb.fill")
                    .font(.headline)
                ForEach(Array(exercise.tips.enumerated()), id: \.offset) { _, tip in
                    Label {
                        Text(tip).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.coachMint)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private var safetyCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Safety", systemImage: "exclamationmark.shield.fill")
                    .font(.headline)
                Text("Use a load and range of motion you can control. Stop if you feel sharp pain, dizziness, numbness, or a loss of control. This technique guidance is educational and is not medical advice.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var attributionCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 8) {
                Link(destination: ExerciseCatalogSource.homepageURL) {
                    Label(ExerciseCatalogSource.attribution, systemImage: "arrow.up.right.square")
                }
                .frame(minHeight: 44, alignment: .leading)
                Link("View the RepDB data license", destination: ExerciseCatalogSource.licenseURL)
                    .font(.footnote)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .font(.subheadline)
        }
    }

    private var detailSelectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            if isAlreadyInTemplate {
                Label("Already in template", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    toggleSelection()
                } label: {
                    Label(
                        isSelected ? "Remove from selection" : "Add to selection",
                        systemImage: isSelected ? "minus.circle.fill" : "plus.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.coachIndigo)
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
        }
        .background(.regularMaterial)
    }

    private var isSelected: Bool { selectedIDs.contains(exercise.id) }

    private func toggleSelection() {
        if let index = selectedIDs.firstIndex(of: exercise.id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(exercise.id)
        }
    }
}

private struct ExerciseMetadataLabel: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.coachSurface, in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}

private enum ExerciseMediaMode: String, CaseIterable, Identifiable {
    case start = "Start"
    case finish = "Finish"
    case autoPreview = "Preview"

    var id: String { rawValue }
}

private struct ExerciseMediaViewer: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let exercise: ExerciseDefinition
    @State private var mode: ExerciseMediaMode = .start

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if imageURLs.isEmpty {
                    mediaPlaceholder
                } else if mode == .autoPreview {
                    ExerciseAutoPreview(
                        exerciseName: exercise.name,
                        urls: Array(imageURLs.prefix(2)),
                        reduceMotion: reduceMotion
                    )
                } else {
                    CachedExerciseImage(
                        url: stillURL,
                        accessibilityLabel: "\(exercise.name), \(mode.rawValue.lowercased()) position",
                        showsProgress: true
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 210 : 240)
            .background(Color.coachSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            if modes.count > 1 {
                if dynamicTypeSize.isAccessibilitySize {
                    Picker("Exercise preview", selection: $mode) {
                        ForEach(modes) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: 44)
                } else {
                    Picker("Exercise preview", selection: $mode) {
                        ForEach(modes) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: 44)
                }
            }

            if imageURLs.count > 1, !reduceMotion {
                Text("Preview alternates the start and finish positions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: imageURLs.count) { _, _ in
            if !modes.contains(mode) { mode = .start }
        }
        .onChange(of: reduceMotion) { _, isEnabled in
            if isEnabled, mode == .autoPreview { mode = .start }
        }
    }

    private var imageURLs: [URL] {
        exercise.imagePaths.compactMap(exercise.imageURL)
    }

    private var modes: [ExerciseMediaMode] {
        guard imageURLs.count > 1 else { return [.start] }
        return reduceMotion ? [.start, .finish] : ExerciseMediaMode.allCases
    }

    private var stillURL: URL? {
        guard !imageURLs.isEmpty else { return nil }
        switch mode {
        case .start, .autoPreview:
            return imageURLs[0]
        case .finish:
            return imageURLs[min(1, imageURLs.count - 1)]
        }
    }

    private var mediaPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 42))
                .foregroundStyle(Color.coachIndigo)
            Text("Illustration unavailable")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ExerciseAutoPreview: View {
    let exerciseName: String
    let urls: [URL]
    let reduceMotion: Bool

    @State private var frameIndex = 0

    var body: some View {
        VStack(spacing: 7) {
            CachedExerciseImage(
                url: urls.isEmpty ? nil : urls[min(frameIndex, urls.count - 1)],
                accessibilityLabel: "\(exerciseName) alternating key-position preview",
                showsProgress: true
            )
            .id(urls.isEmpty ? "empty" : urls[min(frameIndex, urls.count - 1)].absoluteString)
            .transition(.opacity)

            if reduceMotion {
                Label("Preview paused by Reduce Motion", systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: reduceMotion) {
            frameIndex = 0
            guard urls.count > 1, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task<Never, Never>.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    frameIndex = (frameIndex + 1) % urls.count
                }
            }
        }
    }
}

private struct CachedExerciseImage: View {
    let url: URL?
    let accessibilityLabel: String
    let showsProgress: Bool

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            } else if showsProgress, url != nil, !didFail {
                SwiftUI.ProgressView()
            } else {
                Image(systemName: didFail ? "photo.badge.exclamationmark" : "figure.strengthtraining.traditional")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .task(id: url) { await loadImage() }
    }

    @MainActor
    private func loadImage() async {
        image = nil
        didFail = false
        guard let url else { return }
        do {
            let loaded = try await ExerciseImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            image = loaded
        } catch is CancellationError {
            return
        } catch {
            didFail = true
        }
    }
}

@MainActor
private final class ExerciseImageCache {
    static let shared = ExerciseImageCache()

    private let memory = NSCache<NSURL, UIImage>()

    func image(for url: URL) async throws -> UIImage {
        if let image = memory.object(forKey: url as NSURL) { return image }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .returnCacheDataElseLoad

        if let cached = URLCache.shared.cachedResponse(for: request),
           let image = UIImage(data: cached.data) {
            memory.setObject(image, forKey: url as NSURL)
            return image
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }

        URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
        memory.setObject(image, forKey: url as NSURL)
        return image
    }
}
