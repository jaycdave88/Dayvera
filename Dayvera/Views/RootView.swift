import SwiftUI
import SwiftData

private enum AppTab: String, Hashable {
    case today, plan, train, nutrition, progress

    static var launchSelection: AppTab {
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        if arguments.contains("--show-data-sources")
            || arguments.contains("--show-calendar-setup")
            || arguments.contains(where: { $0.hasPrefix("--show-signal-source=") }) {
            return .today
        }
        if arguments.contains(where: { $0.hasPrefix("--show-exercise=") }) {
            return .train
        }
        if arguments.contains(where: { $0.hasPrefix("--show-nutrition-") }) { return .nutrition }
        if arguments.contains("--show-recovery-progress") {
            return .progress
        }
        if arguments.contains(where: {
            [
                "--show-template-editor",
                "--show-template-library",
                "--show-active-workout"
            ].contains($0)
        }) {
            return .train
        }
        if arguments.contains("--show-progress") {
            return .progress
        }
        #endif
        #if DEBUG
        let prefix = "--tab="
        guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return .today
        }
        let requested = String(argument.dropFirst(prefix.count))
        switch requested {
        case "workout", "exercises":
            return .train
        case "settings":
            return .today
        default:
            return AppTab(rawValue: requested) ?? .today
        }
        #else
        return .today
        #endif
    }
}

private enum LaunchDestination {
    static var showsSettings: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--show-data-sources")
            || arguments.contains("--show-calendar-setup")
            || arguments.contains(where: { $0.hasPrefix("--show-signal-source=") })
            || arguments.contains("--tab=settings")
        #else
        return false
        #endif
    }

    static var showsDataSources: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--show-data-sources")
            || arguments.contains(where: { $0.hasPrefix("--show-signal-source=") })
        #else
        return false
        #endif
    }

    static var showsCalendarSetup: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--show-calendar-setup")
        #else
        false
        #endif
    }

    static var showsExerciseLibrary: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--tab=exercises")
            || arguments.contains(where: { $0.hasPrefix("--show-exercise=") })
        #else
        return false
        #endif
    }

    static var progressSection: ProgressSection {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-progress") {
            return .training
        }
        #endif
        return .recovery
    }
}

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var nutrition: NutritionModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedGuidedSetup") private var hasCompletedGuidedSetup = false
    @State private var selection = AppTab.launchSelection
    @State private var showingSettings = LaunchDestination.showsSettings
    @State private var showingDataSources = false
    @State private var pendingDataSources = LaunchDestination.showsDataSources
    @State private var showingCalendarSetup = false
    @State private var pendingCalendarSetup = LaunchDestination.showsCalendarSetup
    @State private var showingExerciseLibrary = LaunchDestination.showsExerciseLibrary
    @State private var progressSection = LaunchDestination.progressSection
    @State private var returningExperience: ReturningExperience = .none
    @State private var evaluatedReturningExperience = false

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                DashboardView(
                    returningExperience: returningExperience,
                    onOpenTrain: { selection = .train },
                    onOpenPlan: { selection = .plan },
                    onOpenRecoveryTrends: {
                        progressSection = .recovery
                        selection = .progress
                    },
                    onOpenDataSources: {
                        selection = .today
                        pendingDataSources = true
                        showingSettings = true
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .accessibilityHint("Manage health data, integrations, and privacy")
                    }
                }
                .navigationDestination(isPresented: $showingSettings) {
                    SettingsView(
                        showingDataSources: $showingDataSources,
                        showingCalendarSetup: $showingCalendarSetup
                    )
                        .task {
                            if pendingDataSources {
                                pendingDataSources = false
                                await Task.yield()
                                showingDataSources = true
                            } else if pendingCalendarSetup {
                                pendingCalendarSetup = false
                                await Task.yield()
                                showingCalendarSetup = true
                            }
                        }
                }
            }
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(AppTab.today)
            NavigationStack { NightPlanView() }
                .tabItem { Label("Plan", systemImage: "calendar.badge.clock") }
                .tag(AppTab.plan)
            NavigationStack {
                WorkoutsView(onOpenToday: { selection = .today })
                    .navigationDestination(isPresented: $showingExerciseLibrary) {
                        ExerciseLibraryView()
                    }
            }
                .tabItem { Label("Train", systemImage: "figure.strengthtraining.traditional") }
                .tag(AppTab.train)
            NavigationStack { NutritionView() }
                .tabItem { Label("Nutrition", systemImage: "leaf.fill") }
                .tag(AppTab.nutrition)
            NavigationStack { ProgressView(section: $progressSection) }
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.progress)
        }
        .tint(Color.coachIndigo)
        .fullScreenCover(isPresented: onboardingPresentation) {
            GuidedSetupView {
                hasCompletedGuidedSetup = true
            }
            .interactiveDismissDisabled()
        }
        .task {
            if !evaluatedReturningExperience {
                evaluatedReturningExperience = true
                returningExperience = appModel.returningExperience()
            }
            nutrition.attach(modelContext)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--demo-data") {
                try? DemoDataSeeder.seedWorkouts(in: modelContext)
            }
            #endif
            await appModel.start()
            nutrition.updateHealthContext(appModel.snapshot)
            await nutrition.refreshHealth()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--demo-data") { nutrition.seedDemo() }
            #endif
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--demo-data"),
               ProcessInfo.processInfo.arguments.contains("--demo-applied-plan") {
                await appModel.applyPlan()
            }
            #endif
            if hasCompletedGuidedSetup {
                appModel.recordMeaningfulUse()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                returningExperience = appModel.returningExperience()
                evaluatedReturningExperience = true
                if hasCompletedGuidedSetup {
                    appModel.recordMeaningfulUse()
                }
                Task { await appModel.refreshForForeground(); nutrition.updateHealthContext(appModel.snapshot); await nutrition.refreshHealth() }
            } else if (phase == .inactive || phase == .background), hasCompletedGuidedSetup {
                appModel.recordMeaningfulUse()
            }
        }
        .onChange(of: appModel.snapshot.generatedAt) { _, _ in nutrition.updateHealthContext(appModel.snapshot) }
        .alert("Nutrition", isPresented: Binding(get: { nutrition.error != nil }, set: { if !$0 { nutrition.error = nil } })) {
            Button("OK") { nutrition.error = nil }
        } message: { Text(nutrition.error ?? "") }
        .alert(AppBrand.name, isPresented: Binding(
            get: { appModel.notice != nil },
            set: { if !$0 { appModel.notice = nil } }
        )) {
            Button("OK") { appModel.notice = nil }
        } message: {
            Text(appModel.notice ?? "")
        }
    }

    private var onboardingPresentation: Binding<Bool> {
        Binding(
            get: {
                #if DEBUG
                let skipsOnboarding = ProcessInfo.processInfo.arguments.contains("--skip-onboarding")
                #else
                let skipsOnboarding = false
                #endif
                return !hasCompletedGuidedSetup
                    && appModel.healthConnectionState == .notRequested
                    && !skipsOnboarding
            },
            set: { isPresented in
                if !isPresented { hasCompletedGuidedSetup = true }
            }
        )
    }
}

private struct GuidedSetupView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isConnecting = false
    @State private var connectionError: String?
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "moon.stars.circle.fill")
                        .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 54 : 68))
                        .foregroundStyle(Color.coachIndigo.gradient)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppBrand.tagline)
                            .font(.largeTitle.bold())
                        Text("Dayvera connects training, nutrition, and recovery into a personal plan for your day.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    CoachCard {
                        VStack(alignment: .leading, spacing: 16) {
                            setupBenefit(
                                symbol: "heart.text.square.fill",
                                title: "Use Apple Health Data",
                                detail: "Use sleep, HRV, and resting heart rate shared by sources like Eight Sleep and Hume."
                            )
                            Divider()
                            setupBenefit(
                                symbol: "calendar.badge.clock",
                                title: "You Control Calendar and Alarms",
                                detail: "Dayvera asks for access only when you schedule a morning from Plan."
                            )
                            Divider()
                            setupBenefit(
                                symbol: "lock.shield.fill",
                                title: "Private by Design",
                                detail: "Workouts stay on this device. Export to Apple Health happens only after you grant access."
                            )
                        }
                    }

                    CoachCard {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("Sleep target", value: appModel.preferences.sleepNeedMinutes.hoursMinutes)
                                .font(.headline)
                            Slider(value: $appModel.preferences.sleepNeedMinutes, in: 420...600, step: 15)
                                .accessibilityLabel("Sleep target")
                                .accessibilityValue(appModel.preferences.sleepNeedMinutes.hoursMinutes)
                            Text("You can change this later in Plan.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                }
                .padding(24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        isConnecting = true
                        Task {
                            let connected = await appModel.connectHealth()
                            isConnecting = false
                            if connected {
                                onComplete()
                            } else {
                                connectionError = appModel.notice ?? "Apple Health could not be connected. Please try again."
                                appModel.notice = nil
                            }
                        }
                    } label: {
                        Group {
                            if isConnecting {
                                HStack {
                                    SwiftUI.ProgressView()
                                    Text("Connecting…")
                                }
                            } else {
                                Label("Connect Apple Health", systemImage: "heart.fill")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.coachIndigo)
                    .disabled(isConnecting)

                    Button("Set Up Later") {
                        onComplete()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.coachIndigo)
                    .frame(minHeight: 44)
                    .disabled(isConnecting)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .background(.bar)
            }
        }
        .alert("Couldn’t connect Apple Health", isPresented: Binding(
            get: { connectionError != nil },
            set: { if !$0 { connectionError = nil } }
        )) {
            Button("OK") { connectionError = nil }
        } message: {
            Text(connectionError ?? "")
        }
    }

    private func setupBenefit(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.coachIndigo)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
