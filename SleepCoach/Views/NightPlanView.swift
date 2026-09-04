import SwiftUI

struct NightPlanView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var appModel: AppModel
    @State private var pendingApplication: PlanApplicationRequest?
    @State private var showingPlanDetails = false
    @State private var showingTimingAssumptions = false
    @State private var showingEnergyGuide = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                planSentenceCard
                if !appModel.plan.warnings.isEmpty { warningCard }
                planActions
                if let status = appModel.appliedPlanStatus { appliedPlanCard(status) }
                planDetailsCard
                timingAssumptionsCard
                energyGuide
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
        .safeAreaInset(edge: .bottom) {
            if dynamicTypeSize.isAccessibilitySize {
                applyPlanButton
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(.bar)
            }
        }
        .confirmationDialog("Apply tomorrow's plan?", isPresented: confirmationPresentation, titleVisibility: .visible) {
            Button(pendingApplication?.includesCalendarEvent == true ? "Create alarm and gym event" : "Create wake alarm") {
                guard let request = pendingApplication else { return }
                pendingApplication = nil
                Task { await appModel.applyPlan(request) }
            }
            Button("Cancel", role: .cancel) { pendingApplication = nil }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationPresentation: Binding<Bool> {
        Binding(
            get: { pendingApplication != nil },
            set: { if !$0 { pendingApplication = nil } }
        )
    }

    private var confirmationMessage: String {
        guard let request = pendingApplication else { return "Review the proposed schedule before applying it." }
        let gymChange = request.includesCalendarEvent
            ? " and add a gym event from \(request.gymStart.shortTime)–\(request.gymEnd.shortTime)"
            : ""
        return "Create a wake alarm for \(request.wakeTime.shortTime)\(gymChange)."
    }

    private var planSentenceCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Schedule-based wake target", systemImage: "calendar.badge.clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.coachIndigo)
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityScheduleSummary
                } else {
                    Text(planSentence)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Built from your next commitment and timing assumptions—not sleep-cycle detection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var planSentence: String {
        let commitment = appModel.plan.firstCommitment.map {
            "\($0.title) at \($0.startDate.shortTime)"
        } ?? "your \(fallbackCommitmentTime) fallback commitment"
        return "Be in bed by \(appModel.plan.bedtime.shortTime), wake at \(appModel.plan.wakeTime.shortTime), train \(appModel.plan.gymStart.shortTime)–\(appModel.plan.gymEnd.shortTime), and be ready for \(commitment)."
    }

    private var planActions: some View {
        VStack(spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                applyPlanButton
            }

            if appModel.calendarStatus != "Connected" {
                Button("Connect Calendar for the gym event", systemImage: "calendar.badge.plus") {
                    Task { await appModel.connectCalendar() }
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            }

            Text(appModel.calendarStatus == "Connected"
                 ? "Nothing changes until you confirm. Applying updates one app-owned alarm and one Calendar event."
                 : "Nothing changes until you confirm. Calendar is optional; connect it only if you want the gym event added.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var applyPlanButton: some View {
        if isCurrentPlanApplied {
            Label("Plan applied", systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity, minHeight: 44)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.vertical, 8)
                .background(Color.coachMint.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.coachMint.opacity(0.65), lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Plan applied")
        } else {
            Button {
                pendingApplication = appModel.planApplicationRequest()
            } label: {
                if appModel.isApplying {
                    HStack {
                        ProgressView()
                        Text("Applying plan…")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Label(
                        dynamicTypeSize.isAccessibilitySize
                            ? "Apply plan"
                            : (appModel.calendarStatus == "Connected" ? "Apply alarm and gym event" : "Apply wake alarm"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.coachIndigo)
            .disabled(appModel.isApplying || appModel.plan.wakeTime <= .now)
            .accessibilityLabel(
                appModel.calendarStatus == "Connected" ? "Apply alarm and gym event" : "Apply wake alarm"
            )
        }
    }

    private var isCurrentPlanApplied: Bool {
        guard let status = appModel.appliedPlanStatus,
              status.wakeAlarmApplied,
              status.wakeTime == appModel.plan.wakeTime,
              status.gymStart == appModel.plan.gymStart,
              status.gymEnd == appModel.plan.gymEnd else {
            return false
        }
        return appModel.calendarStatus != "Connected" || status.calendarEventApplied
    }

    private var accessibilityScheduleSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bed · \(appModel.plan.bedtime.shortTime)")
            Text("Wake · \(appModel.plan.wakeTime.shortTime)")
            Text("Train · \(appModel.plan.gymStart.shortTime)–\(appModel.plan.gymEnd.shortTime)")
            Text(accessibilityCommitmentSummary)
        }
        .font(.headline)
    }

    private var accessibilityCommitmentSummary: String {
        guard let commitment = appModel.plan.firstCommitment else {
            return "Ready · \(fallbackCommitmentTime) fallback"
        }
        return "Ready · \(commitment.startDate.shortTime) for \(commitment.title)"
    }

    private func appliedPlanCard(_ status: AppliedPlanStatus) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Plan applied", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.coachMint)
                VStack(alignment: .leading, spacing: 4) {
                    if status.wakeAlarmApplied {
                        Text("Wake alarm · \(status.wakeTime.shortTime)")
                    }
                    if status.calendarEventApplied {
                        Text("Gym event · \(status.gymStart.shortTime)–\(status.gymEnd.shortTime)")
                    }
                }
                .font(.subheadline)
                Button("Undo applied plan", role: .destructive) {
                    appModel.undoAppliedPlan()
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            }
        }
    }

    private var planDetailsCard: some View {
        CoachCard {
            DisclosureGroup(isExpanded: $showingPlanDetails) {
                VStack(alignment: .leading, spacing: 18) {
                    PlanRow(symbol: "moon.stars.fill", title: "In bed", time: appModel.plan.bedtime, tint: .indigo)
                    connector
                    PlanRow(symbol: "alarm.fill", title: "Wake", time: appModel.plan.wakeTime, tint: .coachAmber)
                    connector
                    PlanRow(
                        symbol: "dumbbell.fill",
                        title: appModel.plan.workoutAdjustment.title,
                        time: appModel.plan.gymStart,
                        endTime: appModel.plan.gymEnd,
                        tint: appModel.snapshot.readinessAvailable ? appModel.plan.readiness.color : .coachIndigo
                    )
                    Divider()
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Planning anchor", systemImage: "calendar")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.coachIndigo)
                        if let event = appModel.plan.firstCommitment {
                            Text(event.title).font(.headline)
                            Text("\(event.startDate.shortDay) at \(event.startDate.shortTime)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Fallback commitment").font(.headline)
                            Text("No hard event was found. Using \(fallbackCommitmentTime).")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 14)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("How this plan was built").font(.headline)
                    Text("Timeline and planning anchor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.coachIndigo)
        }
    }

    private var connector: some View {
        Rectangle().fill(Color.secondary.opacity(0.18)).frame(width: 2, height: 15).padding(.leading, 17)
    }

    private var timingAssumptionsCard: some View {
        CoachCard {
            DisclosureGroup(isExpanded: $showingTimingAssumptions) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Sleep target", value: appModel.preferences.sleepNeedMinutes.hoursMinutes)
                            .font(.subheadline.weight(.semibold))
                        Slider(value: $appModel.preferences.sleepNeedMinutes, in: 420...600, step: 15)
                            .accessibilityLabel("Sleep target")
                            .accessibilityValue(appModel.preferences.sleepNeedMinutes.hoursMinutes)
                    }
                    Divider()
                    Stepper(
                        "Gym duration · \(appModel.preferences.gymDurationMinutes) min",
                        value: $appModel.preferences.gymDurationMinutes,
                        in: 20...180,
                        step: 5
                    )
                    Stepper(
                        "Travel to gym · \(appModel.preferences.travelToGymMinutes) min",
                        value: $appModel.preferences.travelToGymMinutes,
                        in: 0...90,
                        step: 5
                    )
                    Stepper(
                        "Shower and prep · \(appModel.preferences.postWorkoutMinutes) min",
                        value: $appModel.preferences.postWorkoutMinutes,
                        in: 0...90,
                        step: 5
                    )
                    Stepper(
                        "Before commitment · \(appModel.preferences.commitmentBufferMinutes) min",
                        value: $appModel.preferences.commitmentBufferMinutes,
                        in: 0...60,
                        step: 5
                    )
                    Stepper(
                        "Fallback commitment · \(fallbackCommitmentTime)",
                        value: $appModel.preferences.fallbackCommitmentHour,
                        in: 6...14
                    )
                    Label("The proposed schedule updates as you edit.", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 14)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Timing assumptions").font(.headline)
                    Text("Sleep need, gym time, travel, and buffers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.coachIndigo)
        }
    }

    private var fallbackCommitmentTime: String {
        var components = DateComponents()
        components.hour = appModel.preferences.fallbackCommitmentHour
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var energyGuide: some View {
        CoachCard {
            DisclosureGroup(isExpanded: $showingEnergyGuide) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("This is a wake-relative heuristic, not a measurement or a promise about how alert you will feel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(appModel.plan.energyWindows) { window in
                        HStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color(for: window.kind))
                                .frame(width: 5, height: 36)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading) {
                                Text(window.title).font(.subheadline.bold())
                                Text("\(window.startDate.shortTime)–\(window.endDate.shortTime)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 12)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Typical energy guide").font(.headline)
                    Text("Optional wake-relative heuristic")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.coachIndigo)
        }
    }

    private var warningCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("Check the tradeoffs")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.coachAmber)
                }
                .font(.headline)
                ForEach(appModel.plan.warnings, id: \.self) { Text("• \($0)").font(.subheadline) }
            }
        }
    }

    private func color(for kind: EnergyWindow.Kind) -> Color {
        switch kind {
        case .grogginess: .coachAmber
        case .peak: .coachMint
        case .dip: .coachRose
        case .windDown: .coachIndigo
        }
    }
}

private struct PlanRow: View {
    let symbol: String
    let title: String
    let time: Date
    var endTime: Date?
    let tint: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).foregroundStyle(.white).frame(width: 36, height: 36).background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(endTime.map { "\(time.shortTime)–\($0.shortTime)" } ?? time.shortTime)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
