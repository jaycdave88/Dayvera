import SwiftUI
import UIKit

struct NightPlanView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: AppModel
    @State private var pendingApplication: PlanApplicationRequest?
    @State private var showingUndoConfirmation = false
    @State private var showingPlanDetails = false
    @State private var showingTimingAssumptions = false
    @State private var showingEnergyGuide = false
    @State private var showingPlanEditor = false
    @State private var editedPlan: PlanDraft?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                planHeader
                scheduleTimelineCard
                if editedPlan != nil { editedPlanReviewCard }
                if let failure = appModel.calendarReadFailure {
                    calendarFallbackCard(failure)
                }
                if let message = appModel.appliedPlanVerificationMessage,
                   appModel.appliedPlanStatus == nil {
                    appliedPlanVerificationCard(message)
                }
                if !visiblePlanWarnings.isEmpty { warningCard }
                if let status = appModel.appliedPlanStatus {
                    appliedPlanCard(status)
                } else {
                    planActions
                }
                integrationStatusCard
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
            if dynamicTypeSize.isAccessibilitySize, appModel.appliedPlanStatus == nil {
                applyPlanButton
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(.bar)
            }
        }
        .confirmationDialog("Apply tomorrow's plan?", isPresented: confirmationPresentation, titleVisibility: .visible) {
            Button(confirmationActionTitle) {
                guard let request = pendingApplication else { return }
                pendingApplication = nil
                Task { await appModel.applyPlan(request) }
            }
            Button("Cancel", role: .cancel) { pendingApplication = nil }
        } message: {
            Text(confirmationMessage)
        }
        .confirmationDialog("Undo applied plan?", isPresented: $showingUndoConfirmation, titleVisibility: .visible) {
            Button("Undo scheduled items", role: .destructive) {
                appModel.undoAppliedPlan()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Dayvera will remove only the wake alarm and Calendar events created by this applied plan.")
        }
        .sheet(isPresented: $showingPlanEditor) {
            PlanEditorView(
                calculated: calculatedDraft,
                initial: currentDraft,
                context: planEditContext
            ) { editedPlan = $0 == calculatedDraft ? nil : $0 }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--show-plan-editor") {
                showingPlanEditor = true
            }
            #endif
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
        let baseMessage: String
        if request.includesCalendarEvent,
           let destinations = request.calendarDestinations,
           let summary = appModel.calendarApplicationSummary(for: destinations) {
            baseMessage = "Create a wake alarm for \(request.wakeTime.shortTime), \(summary) from \(request.gymStart.shortTime)–\(request.gymEnd.shortTime)."
        } else {
            baseMessage = "Create a wake alarm for \(request.wakeTime.shortTime)."
        }
        guard appModel.calendarStatus == "Connected",
              let warning = appModel.calendarDestinationConfigurationWarning else {
            return baseMessage
        }
        return "\(baseMessage) \(warning)"
    }

    private var confirmationActionTitle: String {
        guard let request = pendingApplication, request.includesCalendarEvent else {
            return "Create wake alarm"
        }
        guard let destinations = request.calendarDestinations else {
            return "Create alarm and workout event"
        }
        let count = destinations.requestedCount
        if count > 1 { return "Create alarm and \(count) calendar events" }
        return destinations.detailedCalendarIdentifier == nil
            ? "Create alarm and Busy event"
            : "Create alarm and workout event"
    }

    private var planHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Tomorrow")
                .font(.title.bold())
            Text(commitmentContext)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var calculatedDraft: PlanDraft { PlanDraft(plan: appModel.plan) }

    private var currentDraft: PlanDraft { editedPlan ?? calculatedDraft }

    private var planEditContext: PlanDraftValidationContext {
        PlanDraftValidationContext(readyBy: readyTime)
    }

    private var currentApplicationRequest: PlanApplicationRequest {
        currentDraft.applicationRequest(basedOn: appModel.planApplicationRequest())
    }

    private var commitmentContext: String {
        if let commitment = appModel.plan.firstCommitment {
            return "Built around \(commitment.title) at \(commitment.startDate.shortTime)."
        }
        return "Built around your \(fallbackCommitmentTime) fallback commitment."
    }

    private var scheduleTimelineCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 16) {
                Label("Tomorrow’s schedule", systemImage: "calendar.badge.clock")
                    .font(.headline)
                PlanRow(symbol: "moon.stars.fill", title: "Bed", time: currentDraft.bedtime, tint: .indigo)
                connector
                PlanRow(symbol: "alarm.fill", title: "Wake", time: currentDraft.wakeTime, tint: .coachAmber)
                connector
                PlanRow(
                    symbol: "dumbbell.fill",
                    title: "Train",
                    time: currentDraft.gymStart,
                    endTime: currentDraft.gymEnd,
                    tint: appModel.snapshot.readinessAvailable ? appModel.plan.readiness.color : .coachIndigo
                )
                connector
                PlanRow(symbol: "checkmark.circle.fill", title: "Ready", time: readyTime, tint: .coachMint)
                connector
                PlanRow(symbol: "briefcase.fill", title: "First commitment", time: commitmentTime, tint: .coachIndigo)
                Text("Schedule-based planning, not sleep-cycle detection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var commitmentTime: Date {
        appModel.plan.firstCommitment?.startDate
            ?? Calendar.current.date(
                bySettingHour: appModel.preferences.fallbackCommitmentHour,
                minute: 0,
                second: 0,
                of: appModel.plan.wakeTime
            )
            ?? appModel.plan.wakeTime
    }

    private var readyTime: Date {
        Calendar.current.date(
            byAdding: .minute,
            value: -appModel.preferences.commitmentBufferMinutes,
            to: commitmentTime
        ) ?? commitmentTime
    }

    private var planActions: some View {
        VStack(spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                applyPlanButton
            }

            Button("Edit Plan", systemImage: "slider.horizontal.3") {
                showingPlanEditor = true
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)

            if appModel.calendarStatus == "Denied" {
                Button("Open Settings for Calendar", systemImage: "gear") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settingsURL)
                    }
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            } else if appModel.calendarStatus != "Connected" {
                Button("Connect Calendar for the gym event", systemImage: "calendar.badge.plus") {
                    Task { await appModel.connectCalendar() }
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            }

            if appModel.calendarStatus == "Connected",
               appModel.selectedDetailedCalendarIsUnavailable {
                NavigationLink {
                    CalendarSetupView()
                } label: {
                    Label(
                        appModel.calendarPreferences.detailedCalendarIdentifier == nil
                            ? "Set up Calendar destinations"
                            : "Repair Calendar destination",
                        systemImage: "calendar.badge.exclamationmark"
                    )
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            }

            Text(planActionExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var integrationStatusCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connections")
                    .font(.headline)
                integrationRow(
                    title: "Calendar",
                    status: appModel.calendarStatus,
                    symbol: "calendar"
                )
                Divider()
                integrationRow(
                    title: "Wake Alarms",
                    status: appModel.alarmStatus,
                    symbol: "alarm.fill"
                )
                NavigationLink {
                    CalendarSetupView()
                } label: {
                    Text("Review Calendar Setup")
                        .frame(minHeight: 44)
                }
                .font(.subheadline.weight(.semibold))
                .disabled(appModel.calendarStatus != "Connected")
            }
        }
    }

    private func integrationRow(title: String, status: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(title, systemImage: symbol)
            Spacer(minLength: 12)
            Text(status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(status)")
    }

    private var planActionExplanation: String {
        if let reason = appModel.calendarReapplyBlockingReason {
            return reason
        }
        guard appModel.calendarStatus == "Connected" else {
            return "Nothing changes until you confirm. Calendar is optional; connect it only if you want workout time added."
        }
        let destinations = appModel.writableCalendarEventDestinations
        let count = destinations.requestedCount
        guard count > 0 else {
            let base = "Calendar is connected, but no writable destination is configured. Applying creates only the wake alarm until you repair Calendar Setup."
            return [base, appModel.calendarDestinationConfigurationWarning]
                .compactMap { $0 }
                .joined(separator: " ")
        }
        let busyCount = destinations.busyCalendarIdentifiers.count
        if destinations.detailedCalendarIdentifier == nil {
            let base = "Nothing changes until you confirm. Applying updates one app-owned alarm and \(busyCount) privacy-safe Busy \(busyCount == 1 ? "event" : "events"); no Workout details event is configured."
            return [base, appModel.calendarDestinationConfigurationWarning]
                .compactMap { $0 }
                .joined(separator: " ")
        }
        if busyCount == 0 {
            return "Nothing changes until you confirm. Applying updates one app-owned alarm and one detailed Workout event."
        }
        let base = "Nothing changes until you confirm. Applying updates one app-owned alarm, one detailed Workout event, and \(busyCount) privacy-safe Busy \(busyCount == 1 ? "copy" : "copies")."
        return [base, appModel.calendarDestinationConfigurationWarning]
            .compactMap { $0 }
            .joined(separator: " ")
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
                pendingApplication = currentApplicationRequest
            } label: {
                if appModel.isApplying {
                    HStack {
                        SwiftUI.ProgressView()
                        Text("Applying plan…")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Label(
                        dynamicTypeSize.isAccessibilitySize
                            ? "Apply plan"
                            : applyButtonTitle,
                        systemImage: "checkmark.circle.fill"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.coachIndigo)
            .disabled(
                appModel.isApplying
                    || currentDraft.wakeTime <= .now
                    || appModel.calendarReapplyBlockingReason != nil
                    || (appModel.appliedPlanStatus != nil && appModel.appliedPlanVerificationMessage != nil)
            )
            .accessibilityLabel(
                applyButtonTitle
            )
        }
    }

    private var applyButtonTitle: String {
        if appModel.calendarReapplyBlockingReason != nil {
            return "Undo applied plan first"
        }
        let request = currentApplicationRequest
        let destinations = request.calendarDestinations
        let count = destinations?.requestedCount ?? 0
        if appModel.calendarStatus != "Connected" || count == 0 { return "Apply wake alarm" }
        if count > 1 { return "Apply alarm and \(count) calendar events" }
        return destinations?.detailedCalendarIdentifier == nil
            ? "Apply alarm and Busy event"
            : "Apply alarm and workout event"
    }

    private var isCurrentPlanApplied: Bool {
        guard let status = appModel.appliedPlanStatus,
              appModel.appliedPlanVerificationMessage == nil,
              status.wakeAlarmApplied,
              status.wakeTime == currentDraft.wakeTime,
              status.gymStart == currentDraft.gymStart,
              status.gymEnd == currentDraft.gymEnd else {
            return false
        }
        let expectsCalendarEvent = status.expectsCalendarEvent
        let desiredDestinations = appModel.writableCalendarEventDestinations
        return (!expectsCalendarEvent || status.calendarEventsComplete)
            && status.matches(calendarDestinations: desiredDestinations)
    }

    private var accessibilityScheduleSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bed · \(currentDraft.bedtime.shortTime)")
            Text("Wake · \(currentDraft.wakeTime.shortTime)")
            Text("Train · \(currentDraft.gymStart.shortTime)–\(currentDraft.gymEnd.shortTime)")
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

    private var editedPlanReviewCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Edited plan · not applied", systemImage: "pencil.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.coachIndigo)
                Text("Review these times, then use Apply Plan. Editing does not create an alarm or Calendar event.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                PlanTimeComparison(title: "Bed", before: calculatedDraft.bedtime, after: currentDraft.bedtime)
                PlanTimeComparison(title: "Wake", before: calculatedDraft.wakeTime, after: currentDraft.wakeTime)
                PlanTimeComparison(
                    title: "Train",
                    before: calculatedDraft.gymStart,
                    after: currentDraft.gymStart,
                    beforeEnd: calculatedDraft.gymEnd,
                    afterEnd: currentDraft.gymEnd
                )
                HStack {
                    Button("Adjust") { showingPlanEditor = true }
                    Spacer()
                    Button("Use calculated plan") { editedPlan = nil }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func appliedPlanCard(_ status: AppliedPlanStatus) -> some View {
        let needsReview = appModel.appliedPlanVerificationMessage != nil
        let expectsCalendarEvent = status.expectsCalendarEvent
        let isComplete = status.wakeAlarmApplied
            && (!expectsCalendarEvent || status.calendarEventsComplete)
        let headline = needsReview
            ? "Plan needs review"
            : (isComplete ? "Plan Applied" : "Partially applied")
        let statusTint = !needsReview && isComplete ? Color.coachMint : Color.coachAmber
        return CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(headline)
                } icon: {
                    Image(
                        systemName: !needsReview && isComplete
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(statusTint)
                }
                .font(.headline)
                .foregroundStyle(.primary)
                if let message = appModel.appliedPlanVerificationMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    appliedItemRow(
                        title: "Wake alarm",
                        scheduledDetail: status.wakeTime.shortTime,
                        isApplied: status.wakeAlarmApplied,
                        needsReview: reviewNeeded(for: .wakeAlarm),
                        reviewDestination: "Clock"
                    )
                    if expectsCalendarEvent || status.calendarEventApplied {
                        if status.calendarEventReceipts.isEmpty {
                            appliedItemRow(
                                title: "Workout event",
                                scheduledDetail: "\(status.gymStart.shortTime)–\(status.gymEnd.shortTime)",
                                isApplied: status.calendarEventApplied,
                                needsReview: reviewNeeded(for: .gymEvent),
                                reviewDestination: "Calendar"
                            )
                        } else {
                            ForEach(status.calendarEventReceipts) { receipt in
                                let receiptStart = receipt.startDate ?? status.gymStart
                                let receiptEnd = receipt.endDate ?? status.gymEnd
                                appliedItemRow(
                                    title: receipt.role.displayTitle,
                                    scheduledDetail: "\(receipt.calendarTitle) · \(receiptStart.shortTime)–\(receiptEnd.shortTime)",
                                    isApplied: true,
                                    needsReview: reviewNeeded(for: .gymEvent),
                                    reviewDestination: receipt.calendarTitle
                                )
                            }
                            let missingCount = max(
                                0,
                                status.requestedCalendarEventCount - status.appliedCalendarEventCount
                            )
                            if missingCount > 0 {
                                appliedItemRow(
                                    title: missingCount == 1 ? "Calendar destination" : "\(missingCount) Calendar destinations",
                                    scheduledDetail: "",
                                    isApplied: false,
                                    needsReview: false,
                                    reviewDestination: "Calendar"
                                )
                            }
                        }
                    }
                }
                .font(.subheadline)
                Button(role: .destructive) {
                    showingUndoConfirmation = true
                } label: {
                    Text("Undo")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .disabled(appModel.isApplying)
            }
        }
    }

    private func appliedItemRow(
        title: String,
        scheduledDetail: String,
        isApplied: Bool,
        needsReview: Bool,
        reviewDestination: String
    ) -> some View {
        Label {
            Text(
                isApplied
                    ? "\(title) · \(needsReview ? "Status unknown—check \(reviewDestination)" : scheduledDetail)"
                    : "\(title) · Not created"
            )
        } icon: {
            Image(
                systemName: !isApplied
                    ? "xmark.circle.fill"
                    : (needsReview ? "questionmark.circle.fill" : "checkmark.circle.fill")
            )
                .foregroundStyle(isApplied && !needsReview ? Color.coachMint : Color.coachAmber)
        }
    }

    private enum AppliedItem {
        case wakeAlarm
        case gymEvent
    }

    private func reviewNeeded(for item: AppliedItem) -> Bool {
        guard let message = appModel.appliedPlanVerificationMessage?.lowercased() else {
            return false
        }
        let mentionsWakeAlarm = message.contains("wake alarm") || message.contains("alarm:")
        let mentionsGymEvent = message.contains("gym event")
            || message.contains("busy event")
            || message.contains("workout details")
            || message.contains("calendar event")
            || message.contains("calendar:")
        guard mentionsWakeAlarm || mentionsGymEvent else { return true }
        switch item {
        case .wakeAlarm: return mentionsWakeAlarm
        case .gymEvent: return mentionsGymEvent
        }
    }

    private var planDetailsCard: some View {
        CoachCard {
            DisclosureGroup(isExpanded: $showingPlanDetails) {
                VStack(alignment: .leading, spacing: 14) {
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
                    Divider()
                    Text(appModel.plan.workoutAdjustment.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 14)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("How this plan was built").font(.headline)
                    Text("Planning anchor and recovery adjustment")
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
                ForEach(visiblePlanWarnings, id: \.self) { Text("• \($0)").font(.subheadline) }
            }
        }
    }

    private var visiblePlanWarnings: [String] {
        if appModel.calendarReadFailure != nil {
            return appModel.plan.warnings.filter {
                !$0.hasPrefix("No calendar commitment was found")
            }
        }
        if appModel.calendarStatus != "Connected" {
            return appModel.plan.warnings.map { warning in
                warning.hasPrefix("No calendar commitment was found")
                    ? "Calendar is optional and not connected; the plan uses your \(fallbackCommitmentTime) fallback."
                    : warning
            }
        }
        return appModel.plan.warnings
    }

    private func calendarFallbackCard(_ failure: String) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Calendar fallback active")
                } icon: {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(Color.coachAmber)
                }
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Calendar couldn’t be refreshed: \(failure)")
                    .font(.subheadline)
                Text("This plan uses your \(fallbackCommitmentTime) fallback commitment until Calendar refreshes successfully.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func appliedPlanVerificationCard(_ message: String) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Applied plan needs review")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.coachAmber)
                }
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.subheadline)
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

private struct PlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let calculated: PlanDraft
    let context: PlanDraftValidationContext
    let onSave: (PlanDraft) -> Void
    private let assistant: any PlanDraftSuggesting

    @State private var draft: PlanDraft
    @State private var request = ""
    @State private var proposal: PlanDraftProposal?
    @State private var assistantMessage: String?
    @State private var isSuggesting = false
    @State private var useOnDeviceAssistance = false

    init(
        calculated: PlanDraft,
        initial: PlanDraft,
        context: PlanDraftValidationContext,
        assistant: any PlanDraftSuggesting = FoundationModelPlanAssistant(),
        onSave: @escaping (PlanDraft) -> Void
    ) {
        self.calculated = calculated
        self.context = context
        self.assistant = assistant
        self.onSave = onSave
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Bed", selection: $draft.bedtime, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Wake", selection: $draft.wakeTime, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Train", selection: $draft.gymStart, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Finish", selection: $draft.gymEnd, displayedComponents: [.date, .hourAndMinute])
                } header: {
                    Text("Draft times")
                } footer: {
                    Text("Keep at least 7 hours for sleep, 20–180 minutes for training, and finish by \(context.readyBy.shortTime).")
                }

                if !validationIssues.isEmpty {
                    Section("Needs attention") {
                        ForEach(validationIssues, id: \.self) { issue in
                            Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.coachAmber)
                        }
                    }
                }

                Section {
                    PlanTimeComparison(title: "Bed", before: calculated.bedtime, after: draft.bedtime)
                    PlanTimeComparison(title: "Wake", before: calculated.wakeTime, after: draft.wakeTime)
                    PlanTimeComparison(
                        title: "Train",
                        before: calculated.gymStart,
                        after: draft.gymStart,
                        beforeEnd: calculated.gymEnd,
                        afterEnd: draft.gymEnd
                    )
                } header: {
                    Text("Calculated → draft")
                } footer: {
                    Text("Nothing is scheduled from this editor. Apply Plan still shows the exact alarm and Calendar changes for confirmation.")
                }

                Section("Optional on-device suggestion") {
                    Toggle("Use on-device assistance for this request", isOn: $useOnDeviceAssistance)
                    if useOnDeviceAssistance {
                        TextField(
                            "For example: start 30 minutes later",
                            text: $request,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        Button {
                            Task { await requestSuggestion() }
                        } label: {
                            if isSuggesting {
                                HStack {
                                    SwiftUI.ProgressView()
                                    Text("Creating suggestion…")
                                }
                            } else {
                                Label("Suggest bounded changes", systemImage: "wand.and.stars")
                            }
                        }
                        .disabled(isSuggesting || request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Text("Manual editing is fully available. Turn this on only when you want help translating a timing preference into a bounded draft.")
                            .foregroundStyle(.secondary)
                    }

                    if let assistantMessage {
                        Text(assistantMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let proposal {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Suggestion · not applied", systemImage: "sparkles")
                                .font(.headline)
                            Text(proposal.rationale)
                                .font(.subheadline)
                            PlanTimeComparison(title: "Bed", before: proposal.current.bedtime, after: proposal.proposed.bedtime)
                            PlanTimeComparison(title: "Wake", before: proposal.current.wakeTime, after: proposal.proposed.wakeTime)
                            PlanTimeComparison(
                                title: "Train",
                                before: proposal.current.gymStart,
                                after: proposal.proposed.gymStart,
                                beforeEnd: proposal.current.gymEnd,
                                afterEnd: proposal.proposed.gymEnd
                            )
                            Button("Use this suggestion") {
                                draft = proposal.proposed
                                self.proposal = nil
                                assistantMessage = "Suggestion copied into your draft. Review and save it below."
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                Section {
                    Button("Use calculated plan") {
                        draft = calculated
                        proposal = nil
                        assistantMessage = nil
                    }
                }
            }
            .navigationTitle("Edit Plan")
            .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Draft") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!validationIssues.isEmpty)
                }
            }
            .onChange(of: draft) { _, _ in invalidateStaleProposal() }
            .onChange(of: request) { _, _ in invalidateStaleProposal() }
            .onChange(of: useOnDeviceAssistance) { _, enabled in
                if !enabled { invalidateStaleProposal() }
            }
        }
    }

    private var validationIssues: [PlanDraftValidationIssue] {
        PlanDraftValidator.issues(for: draft, context: context)
    }

    private func invalidateStaleProposal() {
        guard proposal != nil else { return }
        proposal = nil
        assistantMessage = "The prior suggestion was cleared because the draft or request changed."
    }

    @MainActor
    private func requestSuggestion() async {
        let sourceDraft = draft
        let sourceRequest = request
        isSuggesting = true
        proposal = nil
        assistantMessage = nil
        defer { isSuggesting = false }
        do {
            let result = try await assistant.propose(
                request: sourceRequest,
                current: sourceDraft,
                context: context
            )
            guard useOnDeviceAssistance, draft == sourceDraft, request == sourceRequest else {
                assistantMessage = "The suggestion was cleared because the draft or request changed."
                return
            }
            proposal = result
        } catch is CancellationError {
            assistantMessage = nil
        } catch {
            assistantMessage = error.localizedDescription
        }
    }
}

private struct PlanTimeComparison: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let before: Date
    let after: Date
    var beforeEnd: Date? = nil
    var afterEnd: Date? = nil

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) { content }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) { content }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("Calculated \(formatted(before, end: beforeEnd)); draft \(formatted(after, end: afterEnd))")
    }

    @ViewBuilder private var content: some View {
        Text(title).font(.subheadline.weight(.semibold))
        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
        Text(formatted(before, end: beforeEnd))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .strikethrough(before != after || beforeEnd != afterEnd)
        Image(systemName: "arrow.right")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        Text(formatted(after, end: afterEnd))
            .font(.subheadline.weight(.semibold))
    }

    private func formatted(_ start: Date, end: Date?) -> String {
        end.map { "\(start.shortTime)–\($0.shortTime)" } ?? start.shortTime
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
