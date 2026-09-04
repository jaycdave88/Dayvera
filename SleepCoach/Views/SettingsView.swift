import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var showingDataSources: Bool
    @Binding var showingCalendarSetup: Bool

    var body: some View {
        Form {
            Section("Health & sources") {
                healthConnectionRow
                NavigationLink {
                    DataSourcesView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Health Data & Sources", systemImage: "slider.horizontal.3")
                            .font(.headline)
                        Text("Choose what appears on Today and which Apple Health data shapes your guidance.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 3)
                }
            }

            Section {
                statusRow("Calendar", status: appModel.calendarStatus, symbol: "calendar")
                if appModel.calendarStatus == "Connected" {
                    NavigationLink {
                        CalendarSetupView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Calendar Setup", systemImage: "calendar.badge.checkmark")
                                .font(.headline)
                            Text("Choose planning, Workout details, and privacy-safe Busy calendars.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
                statusRow("Wake alarms", status: appModel.alarmStatus, symbol: "alarm.fill")
            } header: {
                Text("Morning plan")
            } footer: {
                Text("Calendar and alarm access are requested from Plan. After connecting Calendar, configure each calendar here.")
            }

            Section("Training") {
                NavigationLink {
                    TrainingPreferencesView(profile: $appModel.trainingProfile)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Workout Preferences", systemImage: "slider.horizontal.3")
                            .font(.headline)
                        Text("\(appModel.trainingProfile.goal.title) · \(appModel.trainingProfile.activeEquipmentProfile.name) · \(appModel.trainingProfile.targetSessionsPerWeek) days/week")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }

            Section("Exercise library") {
                Link(destination: ExerciseCatalogSource.homepageURL) {
                    Label(ExerciseCatalogSource.attribution, systemImage: "figure.strengthtraining.traditional")
                }
                Link("View dataset license", destination: ExerciseCatalogSource.licenseURL)
                    .font(.subheadline)
                Text("Exercises and illustrations download from RepDB and are cached on this device. Your health and workout records are not included in those requests.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy & safety") {
                Label("Health and workouts stay on this device", systemImage: "iphone.gen3")
                Label("No account, ads, or analytics", systemImage: "hand.raised.fill")
                Label("Fitness guidance—not medical advice", systemImage: "cross.case")
                Link(
                    "Read privacy policy",
                    destination: URL(string: "https://github.com/jaycdave88/SleepCoach/blob/main/PRIVACY.md")!
                )
                Text("Apple Health can return no readable samples without identifying whether access was declined. Sleep Coach reports only the data it can verify.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    private enum SelectionRole {
        case planning
        case detailed
        case busy

        var accessibilityLabel: String {
            switch self {
            case .planning: "Planning calendars"
            case .detailed: "Workout details destination"
            case .busy: "Busy calendars"
            }
        }
    }

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
                selectionSummaryRow(
                    title: "Planning calendars",
                    value: appModel.planningCalendarSelectionSummary,
                    symbol: "calendar"
                )
                if appModel.calendarPreferences.planningCalendarIdentifiers != nil {
                    Button("Use all visible calendars") {
                        appModel.useAllCalendarsForPlanning()
                    }
                }
                ForEach(appModel.calendarSources) { source in
                    DisclosureGroup {
                        ForEach(source.calendars) { calendar in
                            Toggle(
                                calendar.title,
                                isOn: planningBinding(for: calendar.id)
                            )
                        }
                    } label: {
                        sourceDisclosureLabel(source, role: .planning)
                    }
                }
                ForEach(
                    appModel.unavailablePlanningCalendarIdentifiers.sorted(),
                    id: \.self
                ) { identifier in
                    unavailableSelectionRow(
                        title: "Unavailable planning calendar",
                        buttonTitle: "Remove"
                    ) {
                        appModel.setCalendar(identifier, includedInPlanning: false)
                    }
                }
            } header: {
                Text("Plan from")
            } footer: {
                Text("Uses selected calendars to find tomorrow’s first hard commitment. “All visible” also includes calendars added later.")
            }

            Section {
                selectionSummaryRow(
                    title: "Workout details destination",
                    value: appModel.detailedCalendarSelectionSummary,
                    symbol: "figure.strengthtraining.traditional"
                )
                if appModel.selectedDetailedCalendarIsUnavailable {
                    Label(
                        detailedDestinationWarning,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                ForEach(appModel.calendarSources) { source in
                    DisclosureGroup {
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
                    } label: {
                        sourceDisclosureLabel(source, role: .detailed)
                    }
                }
            } header: {
                Text("Workout details")
            } footer: {
                Text("One writable calendar receives workout title, readiness, and confidence. Missing choices are never replaced automatically.")
            }

            Section {
                selectionSummaryRow(
                    title: "Busy calendars",
                    value: appModel.busyCalendarSelectionSummary,
                    symbol: "calendar.badge.clock"
                )
                ForEach(appModel.calendarSources) { source in
                    DisclosureGroup {
                        ForEach(source.calendars) { calendar in
                            Toggle(
                                isOn: busyBinding(for: calendar.id)
                            ) {
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
                                    || (!calendar.allowsContentModifications
                                        && !appModel.isBusyCalendar(calendar.id))
                            )
                        }
                    } label: {
                        sourceDisclosureLabel(source, role: .busy)
                    }
                }
                ForEach(
                    appModel.unavailableBusyCalendarIdentifiers.sorted(),
                    id: \.self
                ) { identifier in
                    unavailableSelectionRow(
                        title: "Unavailable Busy calendar",
                        buttonTitle: "Remove"
                    ) {
                        appModel.setCalendar(identifier, sharesBusy: false)
                    }
                }
            } header: {
                Text("Share as Busy")
            } footer: {
                Text("Optional events are titled “Busy,” contain no workout or health details, and use Busy availability when supported.")
            }
        }
        .navigationTitle("Calendar Setup")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await appModel.refresh() }
    }

    private var detailedDestinationWarning: String {
        if appModel.calendarPreferences.detailedCalendarIdentifier == nil {
            return "No writable default calendar is available. Choose a writable calendar before applying Calendar events."
        }
        return "The selected Workout calendar is missing or read-only. Choose another calendar; Sleep Coach will not redirect the event automatically."
    }

    private func selectionSummaryRow(
        title: String,
        value: String,
        symbol: String
    ) -> some View {
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

    private func sourceDisclosureLabel(
        _ source: CalendarSourceDescriptor,
        role: SelectionRole
    ) -> some View {
        let value = sourceSelectionSummary(source, role: role)
        return VStack(alignment: .leading, spacing: 2) {
            Text(source.title)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(role.accessibilityLabel), \(source.title)")
        .accessibilityValue(value)
    }

    private func sourceSelectionSummary(
        _ source: CalendarSourceDescriptor,
        role: SelectionRole
    ) -> String {
        let selected: [CalendarDescriptor]
        let emptyValue: String
        switch role {
        case .planning:
            selected = source.calendars.filter {
                appModel.isCalendarIncludedInPlanning($0.id)
            }
            emptyValue = "None selected"
        case .detailed:
            selected = source.calendars.filter {
                appModel.calendarPreferences.detailedCalendarIdentifier == $0.id
            }
            emptyValue = "No details destination"
        case .busy:
            selected = source.calendars.filter {
                appModel.isBusyCalendar($0.id)
            }
            emptyValue = "No Busy calendars"
        }
        if selected.count == 1, let calendar = selected.first {
            return role == .detailed
                ? "Selected: \(calendar.title)"
                : calendar.title
        }
        if selected.isEmpty { return emptyValue }
        return "\(selected.count) selected"
    }

    private func planningBinding(for identifier: String) -> Binding<Bool> {
        Binding {
            appModel.isCalendarIncludedInPlanning(identifier)
        } set: { isIncluded in
            appModel.setCalendar(identifier, includedInPlanning: isIncluded)
        }
    }

    private func busyBinding(for identifier: String) -> Binding<Bool> {
        Binding {
            appModel.isBusyCalendar(identifier)
        } set: { isSelected in
            appModel.setCalendar(identifier, sharesBusy: isSelected)
        }
    }

    private func calendarChoiceLabel(
        _ calendar: CalendarDescriptor,
        isSelected: Bool
    ) -> some View {
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
    }

    private func unavailableSelectionRow(
        title: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Label(title, systemImage: "calendar.badge.exclamationmark")
                .font(.subheadline)
            Spacer()
            Button(buttonTitle, role: .destructive, action: action)
        }
    }
}

private struct TrainingPreferencesView: View {
    @Binding var profile: TrainingProfile
    @State private var showingExcludedExercises = false

    var body: some View {
        Form {
            Section("Goal") {
                Picker("Training Goal", selection: $profile.goal) {
                    ForEach(TrainingGoal.allCases, id: \.self) { goal in
                        Text(goal.title).tag(goal)
                    }
                }
                Stepper(
                    "Target: \(profile.targetSessionsPerWeek) days per week",
                    value: $profile.targetSessionsPerWeek,
                    in: 2...6
                )
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
                Text("Exclusions are hard rules. Sleep Coach never removes them automatically or treats them as a medical diagnosis.")
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
