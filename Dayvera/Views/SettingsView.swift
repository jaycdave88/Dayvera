import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("appearancePreference") private var appearanceRawValue = AppAppearance.system.rawValue
    @Binding var showingDataSources: Bool
    @Binding var showingCalendarSetup: Bool

    var body: some View {
        Form {
            Section("Connections") {
                healthConnectionRow
                statusRow("Calendar", status: appModel.calendarStatus, symbol: "calendar")
                statusRow("Wake alarms", status: appModel.alarmStatus, symbol: "alarm.fill")
            }

            Section("Personalization") {
                NavigationLink {
                    TrainingPreferencesView(profile: $appModel.trainingProfile)
                } label: {
                    settingsRow(
                        title: "Workout Preferences",
                        detail: "\(appModel.trainingProfile.goal.title) · \(appModel.trainingProfile.targetSessionsPerWeek) days/week",
                        symbol: "dumbbell.fill"
                    )
                }
                NavigationLink {
                    NutritionView()
                } label: {
                    settingsRow(
                        title: "Nutrition Profile",
                        detail: "Meals, macro targets, goals, and adaptation",
                        symbol: "fork.knife"
                    )
                }
            }

            Section("Appearance") {
                Picker("Color mode", selection: $appearanceRawValue) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                Text("Applies immediately. System follows your iPhone’s appearance setting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                NavigationLink {
                    DataSourcesView()
                } label: {
                    settingsRow(
                        title: "Health Data & Sources",
                        detail: "Choose what appears on Today and shapes guidance",
                        symbol: "heart.text.square"
                    )
                }
                if appModel.calendarStatus == "Connected" {
                    NavigationLink {
                        CalendarSetupView()
                    } label: {
                        settingsRow(
                            title: "Calendar Setup",
                            detail: "Planning, Workout details, and privacy-safe Busy sharing",
                            symbol: "calendar.badge.checkmark"
                        )
                    }
                }
                NavigationLink {
                    NutritionSourcesView()
                } label: {
                    settingsRow(
                        title: "Nutrition Sources",
                        detail: "Authoritative intake and USDA catalog provenance",
                        symbol: "list.bullet.clipboard"
                    )
                }
            }

            Section("Privacy & safety") {
                Label("Health and workouts stay on this device", systemImage: "iphone.gen3")
                Label("No account, ads, or analytics", systemImage: "hand.raised.fill")
                Label("Fitness guidance—not medical advice", systemImage: "cross.case")
                Link(
                    "Read privacy policy",
                    destination: AppBrand.privacyURL
                )
                Text("Apple Health can return no readable samples without identifying whether access was declined. Dayvera reports only the data it can verify.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("About") {
                LabeledContent("Dayvera version", value: appVersion)
                Link(destination: ExerciseCatalogSource.homepageURL) {
                    Label(ExerciseCatalogSource.attribution, systemImage: "figure.strengthtraining.traditional")
                }
                Link("Exercise dataset license", destination: ExerciseCatalogSource.licenseURL)
                Link("USDA FoodData Central", destination: URL(string: "https://fdc.nal.usda.gov/")!)
                Text("Exercise illustrations and the USDA food catalog are cached on this device. Health and workout records are never included in catalog requests.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
        .navigationDestination(isPresented: $showingDataSources) {
            DataSourcesView()
        }
        .navigationDestination(isPresented: $showingCalendarSetup) {
            CalendarSetupView()
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private func settingsRow(title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var healthConnectionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow("Apple Health", status: appModel.healthStatus, symbol: "heart.fill")
            if appModel.healthConnectionState.canRequestAccess {
                Button("Connect Apple Health") {
                    Task { await appModel.connectHealth() }
                }
                .font(.subheadline.weight(.semibold))
            } else if appModel.healthAccessReviewRecommended {
                Label(
                    "New recovery, activity, and body-measurement categories are available.",
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(Color.coachAmber)
                .fixedSize(horizontal: false, vertical: true)

                Button("Review Health Access") {
                    Task { await appModel.connectHealth() }
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder
    private func statusRow(_ title: String, status: String, symbol: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: symbol)
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text(status).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
        }
    }
}

struct CalendarSetupView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            if let failure = appModel.calendarConfigurationFailure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Calendar refresh failed")
                }
            }

            Section {
                NavigationLink {
                    PlanningCalendarSelectionView()
                } label: {
                    CalendarSetupRow(
                        title: "Planning Calendars",
                        value: appModel.planningCalendarSelectionSummary,
                        symbol: "calendar"
                    )
                }
                NavigationLink {
                    DetailsCalendarSelectionView()
                } label: {
                    CalendarSetupRow(
                        title: "Workout Details",
                        value: appModel.detailedCalendarSelectionSummary,
                        symbol: "figure.strengthtraining.traditional"
                    )
                }
                NavigationLink {
                    BusyCalendarSelectionView()
                } label: {
                    CalendarSetupRow(
                        title: "Busy Sharing",
                        value: appModel.busyCalendarSelectionSummary,
                        symbol: "calendar.badge.clock"
                    )
                }
            } footer: {
                Text("Planning calendars are read for commitments. Workout details go to one writable calendar. Busy sharing creates privacy-safe copies without workout or health details.")
            }
        }
        .navigationTitle("Calendar Setup")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await appModel.refresh() }
    }

}

private struct CalendarSetupRow: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
            Text(value)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct PlanningCalendarSelectionView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Section {
                if appModel.calendarPreferences.planningCalendarIdentifiers != nil {
                    Button("Use all visible calendars") {
                        appModel.useAllCalendarsForPlanning()
                    }
                    .frame(minHeight: 44)
                } else {
                    Label("All visible calendars", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.coachIndigo)
                }
            } footer: {
                Text("All visible also includes calendars added later.")
            }

            ForEach(appModel.calendarSources) { source in
                Section(source.title) {
                    ForEach(source.calendars) { calendar in
                        Toggle(calendar.title, isOn: planningBinding(for: calendar.id))
                    }
                }
            }

            if !appModel.unavailablePlanningCalendarIdentifiers.isEmpty {
                Section("Unavailable") {
                    ForEach(appModel.unavailablePlanningCalendarIdentifiers.sorted(), id: \.self) { identifier in
                        unavailableSelectionRow(title: "Unavailable planning calendar") {
                            appModel.setCalendar(identifier, includedInPlanning: false)
                        }
                    }
                }
            }
        }
        .navigationTitle("Planning Calendars")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await appModel.refresh() }
    }

    private func planningBinding(for identifier: String) -> Binding<Bool> {
        Binding {
            appModel.isCalendarIncludedInPlanning(identifier)
        } set: { isIncluded in
            appModel.setCalendar(identifier, includedInPlanning: isIncluded)
        }
    }
}

private struct DetailsCalendarSelectionView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            if appModel.selectedDetailedCalendarIsUnavailable {
                Section {
                    Label(detailedDestinationWarning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(appModel.calendarSources) { source in
                Section(source.title) {
                    ForEach(source.calendars) { calendar in
                        Button {
                            appModel.selectDetailedCalendar(calendar.id)
                        } label: {
                            calendarChoiceLabel(
                                calendar,
                                isSelected: appModel.calendarPreferences.detailedCalendarIdentifier == calendar.id
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!calendar.allowsContentModifications)
                    }
                }
            }
        }
        .navigationTitle("Workout Details")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await appModel.refresh() }
    }

    private var detailedDestinationWarning: String {
        if appModel.calendarPreferences.detailedCalendarIdentifier == nil {
            return "Choose a writable calendar before applying Calendar events."
        }
        return "The selected calendar is missing or read-only. Dayvera will not redirect the event automatically."
    }
}

private struct BusyCalendarSelectionView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            ForEach(appModel.calendarSources) { source in
                Section(source.title) {
                    ForEach(source.calendars) { calendar in
                        Toggle(isOn: busyBinding(for: calendar.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(calendar.title)
                                if !calendar.allowsContentModifications {
                                    Text("Read-only")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if calendar.id == appModel.calendarPreferences.detailedCalendarIdentifier {
                                    Text("Already receives Workout details")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(
                            calendar.id == appModel.calendarPreferences.detailedCalendarIdentifier
                                || (!calendar.allowsContentModifications && !appModel.isBusyCalendar(calendar.id))
                        )
                    }
                }
            }

            if !appModel.unavailableBusyCalendarIdentifiers.isEmpty {
                Section("Unavailable") {
                    ForEach(appModel.unavailableBusyCalendarIdentifiers.sorted(), id: \.self) { identifier in
                        unavailableSelectionRow(title: "Unavailable Busy calendar") {
                            appModel.setCalendar(identifier, sharesBusy: false)
                        }
                    }
                }
            }
        }
        .navigationTitle("Busy Sharing")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Text("Busy events contain no workout or health details.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.bar)
        }
        .refreshable { await appModel.refresh() }
    }

    private func busyBinding(for identifier: String) -> Binding<Bool> {
        Binding {
            appModel.isBusyCalendar(identifier)
        } set: { isSelected in
            appModel.setCalendar(identifier, sharesBusy: isSelected)
        }
    }
}

private func calendarChoiceLabel(_ calendar: CalendarDescriptor, isSelected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(calendar.title)
                    .foregroundStyle(.primary)
                if !calendar.allowsContentModifications {
                    Text("Read-only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.coachIndigo)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected ? "Selected" : (calendar.allowsContentModifications ? "Not selected" : "Read-only"))
}

private func unavailableSelectionRow(title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: "calendar.badge.exclamationmark")
                .font(.subheadline)
            Spacer()
            Button("Remove", role: .destructive, action: action)
                .frame(minHeight: 44)
        }
}

private struct TrainingPreferencesView: View {
    @Binding var profile: TrainingProfile
    @State private var showingExcludedExercises = false

    var body: some View {
        Form {
            Section {
                Picker("Default workout type", selection: $profile.preferredModality) {
                    ForEach(TrainingModality.allCases) { modality in
                        Text(modality.title).tag(modality)
                    }
                }
                Picker("Experience level", selection: $profile.experienceLevel) {
                    ForEach(WorkoutExperienceLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                Picker("Strength emphasis", selection: $profile.goal) {
                    ForEach(TrainingGoal.allCases, id: \.self) { goal in
                        Text(goal.title).tag(goal)
                    }
                }
                Stepper(
                    "Target: \(profile.targetSessionsPerWeek) days per week",
                    value: $profile.targetSessionsPerWeek,
                    in: 2...6
                )
            } header: {
                Text("Training")
            } footer: {
                Text("Strength emphasis is used only for strength and resistance sessions.")
            }

            Section("Workout Defaults") {
                Picker("Equipment", selection: $profile.activeEquipmentProfileID) {
                    ForEach(profile.equipmentProfiles) { item in
                        Text(item.name).tag(item.id)
                    }
                }
                Picker("Load Unit", selection: $profile.loadUnit) {
                    Text("lb").tag(LoadUnit.pounds)
                    Text("kg").tag(LoadUnit.kilograms)
                }
                .pickerStyle(.segmented)
                NavigationLink("Custom Equipment") {
                    CustomEquipmentProfileView(profile: $profile)
                }
            }

            Section {
                ForEach(MovementPattern.allCases, id: \.self) { pattern in
                    Toggle(pattern.title, isOn: exclusionBinding(for: pattern))
                }
                Button {
                    showingExcludedExercises = true
                } label: {
                    LabeledContent("Excluded Exercises") {
                        Text("\(profile.excludedExerciseIDs.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            } header: {
                Text("Movement Exclusions")
            } footer: {
                Text("Exclusions are hard rules. Dayvera never removes them automatically or treats them as a medical diagnosis.")
            }

            Section {
                Toggle("On-Device Personalization", isOn: $profile.onDevicePersonalizationEnabled)
                LabeledContent("Availability", value: WorkoutPersonalizationAvailabilityPresentation.current)
                    .font(.subheadline)
            } header: {
                Text("Apple Intelligence")
            } footer: {
                Text("Optional. Apple Intelligence may rank already-valid workouts and write a short explanation. Planning and safety rules work without AI, and model sessions are not saved.")
            }
        }
        .navigationTitle("Workout Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingExcludedExercises) {
            NavigationStack {
                ExerciseExclusionPicker(excludedIDs: $profile.excludedExerciseIDs)
            }
        }
    }

    private func exclusionBinding(for pattern: MovementPattern) -> Binding<Bool> {
        Binding {
            profile.excludedMovementPatterns.contains(pattern)
        } set: { isExcluded in
            if isExcluded { profile.excludedMovementPatterns.insert(pattern) }
            else { profile.excludedMovementPatterns.remove(pattern) }
        }
    }
}

@MainActor
private struct ExerciseExclusionPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ExerciseCatalogStore.shared
    @Binding var excludedIDs: Set<String>
    @State private var searchText = ""

    var body: some View {
        List(filteredExercises) { exercise in
            Button {
                if excludedIDs.contains(exercise.id) { excludedIDs.remove(exercise.id) }
                else { excludedIDs.insert(exercise.id) }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exercise.name).foregroundStyle(.primary)
                        Text("\(exercise.primaryMuscleTitle) · \(exercise.equipmentTitle)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: excludedIDs.contains(exercise.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(Color.coachIndigo)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(exercise.name), \(excludedIDs.contains(exercise.id) ? "excluded" : "allowed")")
        }
        .overlay {
            if store.isLoading && store.exercises.isEmpty { SwiftUI.ProgressView("Loading exercises…") }
        }
        .searchable(text: $searchText, prompt: "Search exercises")
        .navigationTitle("Excluded Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task { await store.load() }
    }

    private var filteredExercises: [ExerciseDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.exercises }
        return store.exercises.filter {
            $0.matches(query: query, equipment: nil, muscle: nil, difficulty: nil)
        }
    }
}

private struct CustomEquipmentProfileView: View {
    @Binding var profile: TrainingProfile
    private let customID = EquipmentProfileID(rawValue: "custom")

    var body: some View {
        Form {
            Section {
                ForEach(EquipmentID.allCases, id: \.self) { equipment in
                    Toggle(equipment.title, isOn: equipmentBinding(equipment))
                        .disabled(equipment == .bodyweight)
                }
            } footer: {
                Text("Bodyweight is always available. Select Custom on the previous screen to use this profile for recommendations.")
            }
        }
        .navigationTitle("Custom Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: ensureCustomProfile)
    }

    private func equipmentBinding(_ equipment: EquipmentID) -> Binding<Bool> {
        Binding {
            customProfile.equipment.contains(equipment)
        } set: { isAvailable in
            ensureCustomProfile()
            guard let index = profile.equipmentProfiles.firstIndex(where: { $0.id == customID }) else { return }
            if isAvailable { profile.equipmentProfiles[index].equipment.insert(equipment) }
            else if equipment != .bodyweight { profile.equipmentProfiles[index].equipment.remove(equipment) }
        }
    }

    private var customProfile: EquipmentProfile {
        profile.equipmentProfiles.first(where: { $0.id == customID })
            ?? EquipmentProfile(id: customID, name: "Custom", equipment: [.bodyweight])
    }

    private func ensureCustomProfile() {
        guard !profile.equipmentProfiles.contains(where: { $0.id == customID }) else { return }
        profile.equipmentProfiles.append(
            EquipmentProfile(id: customID, name: "Custom", equipment: [.bodyweight])
        )
    }
}
