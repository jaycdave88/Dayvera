import Charts
import SwiftData
import SwiftUI

struct NutritionView: View {
    @EnvironmentObject private var nutrition: NutritionModel
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var date = Date.now
    @State private var showSetup = false
    @State private var showLogFood = false
    @State private var editMeal: MealRecord?
    @State private var copyMeal: MealRecord?
    @State private var showTotals = false
    @State private var showMeasurements = false
    @State private var showWhatIf = false
    @State private var showSources = false
    @State private var showProgress = false
    @State private var completionFeedback = 0
    @Query(sort: \WorkoutSessionRecord.startedAt, order: .reverse) private var sessions: [WorkoutSessionRecord]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Food journal").font(.headline)
                        DatePicker("Food journal", selection: $date, in: ...Date.now, displayedComponents: .date).labelsHidden()
                    }.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    DatePicker("Food journal", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .font(.headline).padding(.horizontal, 4)
                }
                if !nutrition.profile.completedSetup { setupCard }
                dailySummaryCard
                dayStatusCard
                mealsCard
                if nutrition.target(on: date) != nil {
                    NavigationLink { NutritionProgressView() } label: {
                        CoachCard { HStack { Label("Weight, measurements & progress", systemImage: "chart.xyaxis.line"); Spacer(); Image(systemName: "chevron.right") } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens nutrition progress")
                    recoveryCard
                    adjustmentCard
                }
                Button { showSetup = true } label: { Label("Profile and goal settings", systemImage: "slider.horizontal.3") }.frame(minHeight: 44)
            }.padding()
        }
        .background(Color.coachBackground)
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(typeSize.isAccessibilitySize ? .inline : .large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { showSources = true } label: { Label("Intake sources", systemImage: "heart.text.square") } }
        }
        .refreshable { await appModel.refresh(); await nutrition.refreshHealth(); nutrition.evaluateAdjustment() }
        .onAppear {
            nutrition.evaluateAdjustment()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--show-nutrition-scan") { showLogFood = true }
            if ProcessInfo.processInfo.arguments.contains("--show-nutrition-whatif") { showWhatIf = true }
            if ProcessInfo.processInfo.arguments.contains("--show-nutrition-profile") { showSetup = true }
            if ProcessInfo.processInfo.arguments.contains("--show-nutrition-progress") { showProgress = true }
            #endif
        }
        .navigationDestination(isPresented: $showProgress) { NutritionProgressView() }
        .sheet(isPresented: $showSetup) { NutritionSetupView(draft: startingProfile) }
        .sheet(isPresented: $showLogFood) { LogFoodLauncherView(date: date) }
        .sheet(item: $editMeal) { MealEditorView(existing: $0) }
        .sheet(item: $copyMeal) { MealEditorView(copying: $0, date: date) }
        .sheet(isPresented: $showTotals) { NutritionDailyTotalView(date: date) }
        .sheet(isPresented: $showMeasurements) { NutritionMeasurementView() }
        .sheet(isPresented: $showWhatIf) { NutritionWhatIfView() }
        .sheet(isPresented: $showSources) { NutritionSourcesView() }
        .sensoryFeedback(.success, trigger: completionFeedback)
    }
    private var startingProfile: NutritionProfile {
        var profile = nutrition.profile
        if !profile.completedSetup {
            profile.trainingDays = appModel.trainingProfile.targetSessionsPerWeek
            if let latest = appModel.snapshot.samples.filter({ $0.kind == .bodyMass && $0.value != nil }).max(by: { $0.endDate < $1.endDate }), let kg = latest.value {
                profile.weightKG = kg; profile.measurementSource = latest.sourceName; profile.measurementDate = latest.endDate
            }
        }
        return profile
    }
    private var setupCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("FUEL YOUR PROGRESS", systemImage: "leaf.fill").font(.caption.bold()).foregroundStyle(Color.coachMint)
                Text("A plan that learns with you.").font(.title2.bold())
                Text("Connect your meals, training and recovery. Start with a personal estimate; refine it with consistent real-world progress.").foregroundStyle(.secondary)
                Button("Build my nutrition plan") { showSetup = true }.buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
    }
    private var dailySummaryCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 16) {
                if let target = nutrition.target(on: date) {
                    let training = nutrition.day(on: date)?.trainingDay ?? false
                    let amounts = target.amounts(training: training)
                    let intake = nutrition.intake(on: date)
                    let remaining = intake.calories.map { amounts.calories - $0 }
                    adaptiveRow {
                        Text(training ? "TRAINING DAY" : "REST DAY").font(.caption.bold()).foregroundStyle(Color.coachIndigo)
                        if !typeSize.isAccessibilitySize { Spacer() }
                        Text("ESTIMATED TARGET").font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(remaining.map { value in
                            value >= 0 ? "\(Int(value.rounded())) kcal remaining" : "\(Int((-value).rounded())) kcal over target"
                        } ?? "\(amounts.calories.nutritionCalories) kcal target")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                        Text(intake.calories.map { "\(Int($0.rounded())) of \(amounts.calories.nutritionCalories) kcal logged" } ?? "No intake logged yet")
                            .font(.headline).foregroundStyle(.secondary)
                    }
                    Button { showLogFood = true } label: {
                        Label("Log Food", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                    Button { showMeasurements = true } label: { Label("Weigh In", systemImage: "scalemass") }
                        .buttonStyle(.bordered).frame(minHeight: 44)
                    Divider()
                    VStack(spacing: 12) {
                        MacroTargetRow(title: "Protein", grams: amounts.protein, energy: amounts.calories, factor: 4, color: .coachIndigo, intake: intake.protein, intakeKnown: intake.calories != nil)
                        MacroTargetRow(title: "Carbs", grams: amounts.carbs, energy: amounts.calories, factor: 4, color: .coachMint, intake: intake.carbs, intakeKnown: intake.calories != nil)
                        MacroTargetRow(title: "Fat", grams: amounts.fat, energy: amounts.calories, factor: 9, color: .coachAmber, intake: intake.fat, intakeKnown: intake.calories != nil)
                    }
                    Text("Protein planning range \(target.proteinLow.nutritionGrams)–\(target.proteinHigh.nutritionGrams) g · Fat \(target.fatLow.nutritionGrams)–\(target.fatHigh.nutritionGrams) g. Carbs fill the remaining energy.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Training day", isOn: Binding(get: { training }, set: { value in perform { try nutrition.updateDay(date, training: value) } }))
                    DisclosureGroup("How certain is this?") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Estimated maintenance: \(target.maintenance.nutritionCalories) kcal · working range \(target.maintenanceLow.nutritionCalories)–\(target.maintenanceHigh.nutritionCalories)")
                            ForEach(target.notes, id: \.self) { Text($0) }
                            Text("Profile-based estimate · Mifflin–St Jeor × whole-day activity. Consistent weight and intake records can improve calibration, but reporting error remains.")
                            Link("Calculation methods and evidence", destination: AppBrand.repositoryURL.appendingPathComponent("blob/main/NUTRITION.md"))
                        }.font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    if let next = nutrition.revisions.last, next.effectiveDate > .now {
                        Text("Updated targets begin \(next.effectiveDate.formatted(date: .abbreviated, time: .omitted)). Today’s target stays unchanged.").font(.footnote).foregroundStyle(Color.coachMint)
                    }
                    Button("Explore what if…") { showWhatIf = true }.buttonStyle(.bordered)
                } else {
                    Label("Your food journal", systemImage: "book.closed").font(.title2.bold())
                    Text(nutrition.profile.completedSetup ? "Personal targets are unavailable for this profile. You can keep a non-prescriptive food journal." : "Log a meal now or set up your profile for calorie and macro targets.").foregroundStyle(.secondary)
                    Button { showLogFood = true } label: { Label("Log Food", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    private var dayStatusCard: some View {
        let intake = nutrition.intake(on: date)
        let source = nutrition.day(on: date)?.source ?? "meals"
        return CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                adaptiveRow {
                    Text("Day status").font(.headline)
                    if !typeSize.isAccessibilitySize { Spacer() }
                    Text(intake.calories.map { "\(Int($0.rounded())) kcal" } ?? "Not logged").font(.title3.bold()).monospacedDigit()
                }
                if let calories = intake.calories, let target = nutrition.target(on: date)?.amounts(training: nutrition.day(on: date)?.trainingDay ?? false) {
                    let remaining = target.calories - calories
                    Text(remaining >= 0 ? "\(Int(remaining.rounded())) kcal remaining against today’s target" : "\(Int(-remaining.rounded())) kcal above today’s target")
                        .foregroundStyle(.secondary)
                }
                Picker("Authoritative intake source", selection: Binding(get: { source }, set: { value in perform { try nutrition.updateDay(date, source: value) } })) {
                    Text("Dayvera meals").tag("meals")
                    Text("Daily total").tag("manual")
                    ForEach(nutrition.healthSources, id: \.id) { Text($0.name).tag($0.id) }
                    if source.hasPrefix("health:"), !nutrition.healthSources.contains(where: { $0.id == source }) { Text("Selected Health source unavailable").tag(source) }
                }
                if source == "manual" { Button("Enter daily totals") { showTotals = true }.frame(minHeight: 44) }
                Toggle("Mark Day Complete", isOn: Binding(get: { nutrition.day(on: date)?.isComplete ?? false }, set: { value in
                    perform {
                        try nutrition.updateDay(date, complete: value)
                        if value { completionFeedback += 1 }
                    }
                }))
                    .disabled(intake.calories == nil)
                if nutrition.day(on: date)?.isComplete == true {
                    Label("Day complete", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.coachMint)
                        .accessibilityLabel("Nutrition day complete")
                }
                Text("\(intake.source) · \(intake.complete ? "Confirmed complete" : "Day open"). One source counts per day so totals are never double-counted. Complete days can become evidence for future target adjustments.").font(.footnote).foregroundStyle(.secondary)
                if let healthError = nutrition.healthError { Text(healthError).font(.footnote).foregroundStyle(Color.coachAmber) }
            }
        }
    }
    private var mealsCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "Meals", subtitle: "Reviewed portions, saved on your device")
                if nutrition.meals(on: date).isEmpty { Text("No meals saved for this day.").foregroundStyle(.secondary) }
                ForEach(nutrition.meals(on: date)) { meal in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { editMeal = meal } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(meal.name).font(.headline).foregroundStyle(.primary)
                                    Text("\(Int(meal.total.calories.rounded())) kcal · \(meal.entries.count) foods").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.right")
                            }
                        }.frame(minHeight: 44)
                        adaptiveRow {
                            Button { perform { try nutrition.toggleFavorite(meal) } } label: { Label(meal.favorite ? "Saved" : "Favorite", systemImage: meal.favorite ? "star.fill" : "star") }
                            if !typeSize.isAccessibilitySize { Spacer() }
                            Button("Repeat") { copyMeal = meal }
                            Button("Delete", role: .destructive) { perform { try nutrition.deleteMeal(meal) } }
                        }.font(.footnote).buttonStyle(.bordered)
                        Divider()
                    }
                }
                if !nutrition.meals.filter(\.favorite).isEmpty {
                    Menu("Add a favorite meal") {
                        ForEach(nutrition.meals.filter(\.favorite)) { meal in Button(meal.name) { copyMeal = meal } }
                    }
                }
            }
        }
    }
    private var recoveryCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Recovery and muscle priorities")
                if appModel.snapshot.readinessAvailable {
                    LabeledContent("Recovery", value: appModel.snapshot.readinessBand.rawValue.capitalized)
                    if let sleep = appModel.snapshot.latestSleep {
                        Text("Latest sleep: \(Int(sleep.asleepMinutes / 60))h \(Int(sleep.asleepMinutes) % 60)m · \(sleep.sourceName) · \(sleep.endDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else { Text("Recovery data unavailable. Nutrition targets do not assume poor recovery.").foregroundStyle(.secondary) }
                ForEach(nutrition.profile.musclePriorities.sorted { $0.rawValue < $1.rawValue }) { muscle in
                    let count = sessions.filter { $0.startedAt > Date.now.addingTimeInterval(-7 * 86_400) }.flatMap(\.sets).filter { !$0.isWarmup && $0.muscleGroup == muscle }.count
                    LabeledContent(muscle.title, value: "\(count) working sets / 7 days")
                }
                Text("Food supports overall growth. Training provides the local stimulus. Sleep and recovery are context—not calorie multipliers or evidence of nutrient deficiency.").font(.footnote).foregroundStyle(.secondary)
                NavigationLink("Review training", destination: WorkoutsView())
            }
        }
    }
    private var adjustmentCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Next adjustment", subtitle: "Small changes, supported by progress")
                if let pending = nutrition.adjustments.first(where: { $0.status == "pending" }) {
                    Text(pending.reason)
                    Text("Suggested average: \(pending.proposedCalories.nutritionCalories) kcal/day").font(.headline)
                    adaptiveRow {
                        Button("Apply tomorrow") { perform { try nutrition.accept(pending) } }.buttonStyle(.borderedProminent)
                        Button("Dismiss") { perform { try nutrition.dismiss(pending) } }.buttonStyle(.bordered)
                    }
                } else { Text(nutrition.evaluation()?.reason ?? "Build a consistent intake and weight history before adjusting targets.").foregroundStyle(.secondary) }
                if let flag = nutrition.underfuelingMessage { Text(flag).font(.callout).foregroundStyle(Color.coachAmber) }
            }
        }
    }
    private var adaptiveRow: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 8))
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { nutrition.error = error.localizedDescription } }
}

private enum LogFoodDestination: Identifiable {
    case takePhoto, choosePhoto, search, nutritionLabel, dailyTotals, copiedMeal(MealRecord)

    var id: String {
        switch self {
        case .takePhoto: "take-photo"
        case .choosePhoto: "choose-photo"
        case .search: "search"
        case .nutritionLabel: "nutrition-label"
        case .dailyTotals: "daily-totals"
        case .copiedMeal(let meal): "meal-\(meal.id)"
        }
    }
}

private struct LogFoodLauncherView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutrition: NutritionModel
    let date: Date
    @State private var destination: LogFoodDestination?

    var body: some View {
        NavigationStack {
            List {
                Section("Capture") {
                    launcherRow("Take Photo", symbol: "camera.fill", detail: "Use the camera, then review every suggested food") { destination = .takePhoto }
                    launcherRow("Choose Photo", symbol: "photo.on.rectangle", detail: "Select a photo from your library") { destination = .choosePhoto }
                }
                Section("Find or enter") {
                    launcherRow("Search Foods", symbol: "magnifyingglass", detail: "Match foods from the trusted catalog") { destination = .search }
                    launcherRow("Enter Nutrition Label", symbol: "text.document", detail: "Enter the values printed on a package") { destination = .nutritionLabel }
                }
                Section("Recent") {
                    let recent = nutrition.meals.sorted { $0.date > $1.date }
                    if recent.isEmpty {
                        Text("Recent meals will appear here after you save them.").foregroundStyle(.secondary)
                    } else {
                        ForEach(recent) { meal in
                            launcherRow(meal.name, symbol: "clock.arrow.circlepath", detail: "\(Int(meal.total.calories.rounded())) kcal · \(Int(meal.total.protein.rounded())) g protein") {
                                destination = .copiedMeal(meal)
                            }
                        }
                    }
                }
                Section("Favorites") {
                    let favorites = nutrition.meals.filter(\.favorite).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    if favorites.isEmpty {
                        Text("Favorite meals will appear here after you save them.").foregroundStyle(.secondary)
                    } else {
                        ForEach(favorites) { meal in
                            launcherRow(meal.name, symbol: "star.fill", detail: "\(Int(meal.total.calories.rounded())) kcal · \(Int(meal.total.protein.rounded())) g protein") {
                                destination = .copiedMeal(meal)
                            }
                        }
                    }
                }
                Section("Advanced") {
                    launcherRow("Enter Daily Totals", symbol: "sum", detail: "Use one confirmed total for the whole day") { destination = .dailyTotals }
                }
            }
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $destination) { destination in
                switch destination {
                case .takePhoto:
                    MealEditorView(date: date, initialAction: .takePhoto, onSaved: finishLogging)
                case .choosePhoto:
                    MealEditorView(date: date, initialAction: .choosePhoto, onSaved: finishLogging)
                case .search:
                    MealEditorView(date: date, initialAction: .search, onSaved: finishLogging)
                case .nutritionLabel:
                    MealEditorView(date: date, initialAction: .nutritionLabel, onSaved: finishLogging)
                case .dailyTotals:
                    NutritionDailyTotalView(date: date, onSaved: finishLogging)
                case .copiedMeal(let meal):
                    MealEditorView(copying: meal, date: date, onSaved: finishLogging)
                }
            }
        }
    }

    private func launcherRow(_ title: String, symbol: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).frame(width: 28).foregroundStyle(Color.coachIndigo).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary).accessibilityHidden(true)
            }.frame(minHeight: 52)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(detail)
    }

    private func finishLogging() {
        destination = nil
        dismiss()
    }
}

struct MacroTargetRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let grams: Double
    let energy: Double
    let factor: Double
    let color: Color
    let intake: Double?
    let intakeKnown: Bool
    var body: some View {
        VStack(spacing: 5) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())) {
                Text(title).font(.subheadline.weight(.semibold))
                if !typeSize.isAccessibilitySize { Spacer() }
                Text("\(grams.nutritionGrams) g · \(Int((grams * factor / max(energy, 1) * 100).rounded()))%").font(.subheadline).monospacedDigit()
            }
            SwiftUI.ProgressView(value: min(max(intake ?? 0, 0), grams), total: max(grams, 1)).tint(color)
                .accessibilityLabel(title).accessibilityValue(intake.map { "\(Int($0)) of \(Int(grams)) grams logged" } ?? (intakeKnown ? "Unknown" : "Not logged"))
            HStack {
                Text(intake.map { value in
                    let remaining = max(grams - value, 0)
                    return "\(Int(value.rounded())) g logged · \(Int(remaining.rounded())) g remaining"
                } ?? (intakeKnown ? "Unknown · target \(grams.nutritionGrams) g" : "Not logged · target \(grams.nutritionGrams) g"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

struct NutritionTodayCard: View {
    @EnvironmentObject private var nutrition: NutritionModel
    var body: some View {
        NavigationLink { NutritionView() } label: {
            CoachCard {
                HStack(alignment: .top) {
                    Image(systemName: "leaf.fill").foregroundStyle(Color.coachMint)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Fuel your day").font(.headline).foregroundStyle(.primary)
                        if let target = nutrition.target(on: .now) {
                            let current = nutrition.intake(on: .now).calories.map { "\(Int($0))" } ?? "Not logged"
                            Text("\(current) · target \(target.amounts(training: nutrition.day(on: .now)?.trainingDay ?? false).calories.nutritionCalories) kcal").font(.subheadline).foregroundStyle(.secondary)
                        } else { Text("Meals, macros, and a personal nutrition plan").font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Spacer(); Image(systemName: "chevron.right")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Nutrition")
    }
}
