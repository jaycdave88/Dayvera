import SwiftUI
import SwiftData

private enum AppTab: String, Hashable {
    case today, plan, train, exercises, settings

    static var launchSelection: AppTab {
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        if arguments.contains("--show-data-sources")
            || arguments.contains(where: { $0.hasPrefix("--show-signal-source=") }) {
            return .settings
        }
        if arguments.contains(where: { $0.hasPrefix("--show-exercise=") }) {
            return .exercises
        }
        if arguments.contains("--show-recovery-progress") {
            return .today
        }
        if arguments.contains(where: {
            [
                "--show-template-editor",
                "--show-template-library",
                "--show-active-workout",
                "--show-progress"
            ].contains($0)
        }) {
            return .train
        }
        #endif
        let prefix = "--tab="
        guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return .today
        }
        let requested = String(argument.dropFirst(prefix.count))
        switch requested {
        case "workout", "progress":
            return .train
        default:
            return AppTab(rawValue: requested) ?? .today
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedGuidedSetup") private var hasCompletedGuidedSetup = false
    @State private var selection = AppTab.launchSelection
    @State private var showingDataSources = false

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                DashboardView(
                    onOpenTrain: { selection = .train },
                    onOpenDataSources: {
                        selection = .settings
                        showingDataSources = true
                    }
                )
            }
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(AppTab.today)
            NavigationStack { NightPlanView() }
                .tabItem { Label("Plan", systemImage: "calendar.badge.clock") }
                .tag(AppTab.plan)
            NavigationStack { WorkoutsView() }
                .tabItem { Label("Train", systemImage: "figure.strengthtraining.traditional") }
                .tag(AppTab.train)
            NavigationStack { ExerciseLibraryView() }
                .tabItem { Label("Exercises", systemImage: "dumbbell.fill") }
                .tag(AppTab.exercises)
            NavigationStack { SettingsView(showingDataSources: $showingDataSources) }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .tint(Color.coachIndigo)
        .fullScreenCover(isPresented: onboardingPresentation) {
            GuidedSetupView {
                hasCompletedGuidedSetup = true
            }
            .interactiveDismissDisabled()
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--demo-data") {
                try? DemoDataSeeder.seedWorkouts(in: modelContext)
            }
            #endif
            await appModel.start()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--demo-data"),
               ProcessInfo.processInfo.arguments.contains("--demo-applied-plan") {
                await appModel.applyPlan()
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await appModel.refreshForForeground() }
            }
        }
        .alert("Sleep Coach", isPresented: Binding(
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
                !hasCompletedGuidedSetup
                    && appModel.healthConnectionState == .notRequested
                    && !ProcessInfo.processInfo.arguments.contains("--skip-onboarding")
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
                        Text("Wake ready. Train with context.")
                            .font(.largeTitle.bold())
                        Text("Sleep Coach turns your overnight recovery and tomorrow's commitments into one clear wake and training plan.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    CoachCard {
                        VStack(alignment: .leading, spacing: 16) {
                            setupBenefit(
                                symbol: "heart.text.square.fill",
                                title: "Connect through Apple Health",
                                detail: "Read sleep, HRV, and resting heart rate shared by sources such as Eight Sleep and Hume."
                            )
                            Divider()
                            setupBenefit(
                                symbol: "calendar.badge.clock",
                                title: "Plan only when you ask",
                                detail: "Calendar and wake-alarm access are requested later from Plan, when you apply a schedule."
                            )
                            Divider()
                            setupBenefit(
                                symbol: "lock.shield.fill",
                                title: "Private by default",
                                detail: "Your health and workout records stay on this device."
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
                            Text("You can fine-tune this later in Plan.")
                                .font(.caption)
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
                            await appModel.connectHealth()
                            isConnecting = false
                            onComplete()
                        }
                    } label: {
                        Group {
                            if isConnecting {
                                HStack {
                                    ProgressView()
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

                    Button("Continue without health data") {
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
