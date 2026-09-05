import Charts
import SwiftUI

struct NutritionProgressView: View {
    @EnvironmentObject private var nutrition: NutritionModel
    @State private var window = 28
    @State private var showMeasurement = false
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                Picker("Window", selection: $window) { Text("7 days").tag(7); Text("28 days").tag(28) }.pickerStyle(.segmented)
                CoachCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(title: "Weight trend", subtitle: "Daily observations and seven-day averages")
                        if points.isEmpty { Text("Add a weigh-in or connect body-weight data through Apple Health.").foregroundStyle(.secondary) }
                        else {
                            Chart {
                                ForEach(points) { point in
                                    PointMark(x: .value("Day", point.date), y: .value("Weight", displayedWeight(point.kg)))
                                        .foregroundStyle(Color.coachIndigo.opacity(0.6))
                                }
                                ForEach(weeklyMeans) { point in
                                    LineMark(x: .value("Week", point.date), y: .value("Average", displayedWeight(point.kg)))
                                        .foregroundStyle(Color.coachMint).symbol(.circle)
                                }
                            }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 210)
                                .accessibilityLabel("Body weight in \(nutrition.profile.usesMetric ? "kilograms" : "pounds")")
                            Text("\(points.count) weigh-in days · \(points.first?.source ?? "") · missing days stay missing").font(.footnote).foregroundStyle(.secondary)
                            if let slope = NutritionAdaptationEngine.slope(points) {
                                LabeledContent("Robust weekly trend", value: String(format: "%+.2f%% / week", slope))
                            }
                        }
                        Button("Add weight or measurements") { showMeasurement = true }.buttonStyle(.bordered)
                    }
                }
                CoachCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(title: "Intake and consistency", subtitle: "Only confirmed complete days inform adjustments")
                        Chart {
                            ForEach(evidence, id: \.date) { day in
                                if let calories = day.intake.calories {
                                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Logged calories", calories))
                                        .foregroundStyle(day.intake.complete ? Color.coachMint : Color.coachAmber.opacity(0.6))
                                }
                                if let target = day.targetCalories {
                                    PointMark(x: .value("Day", day.date), y: .value("Saved target", target)).foregroundStyle(Color.coachIndigo)
                                }
                            }
                        }.frame(height: 200)
                        Text("Green: complete · amber: unconfirmed · indigo: saved target. Empty dates mean missing intake.").font(.footnote).foregroundStyle(.secondary)
                        LabeledContent("Complete intake days", value: "\(evidence.filter { $0.intake.complete }.count) / \(window)")
                        let proteinDays = evidence.filter { day in
                            guard day.intake.complete, let protein = day.intake.protein,
                                  let target = nutrition.revision(on: day.date.addingTimeInterval(86_399))?.target else { return false }
                            return (target.proteinLow...target.proteinHigh).contains(protein)
                        }.count
                        LabeledContent("Days within protein range", value: "\(proteinDays) / \(evidence.filter { $0.intake.complete && $0.intake.protein != nil }.count) known complete days")
                        if let maintenance = nutrition.observedMaintenance {
                            Text("Observed maintenance estimate: about \(maintenance.nutritionCalories) kcal/day during stable weight. Food-log error still applies.").font(.callout)
                        }
                        Text(nutrition.evaluation()?.reason ?? "Your progress will appear as you log.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                CoachCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Body measurements", subtitle: "Changes in measurements are not direct measurements of muscle growth")
                        ForEach(nutrition.measurements.suffix(12).reversed()) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.date.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                                if let weight = item.weightKG { Text("Weight: \(displayedWeight(weight).formatted(.number.precision(.fractionLength(1)))) \(nutrition.profile.usesMetric ? "kg" : "lb")") }
                                ForEach(measurementLabels(item), id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
                                Button("Delete", role: .destructive) { do { try nutrition.deleteMeasurement(item) } catch { nutrition.error = error.localizedDescription } }.font(.footnote)
                                Divider()
                            }
                        }
                        if nutrition.measurements.isEmpty { Text("Use consistent conditions and tape placement when measuring.").foregroundStyle(.secondary) }
                    }
                }
                CoachCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Target history")
                        ForEach(nutrition.revisions.reversed()) { revision in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(revision.effectiveDate.formatted(date: .abbreviated, time: .omitted)) · \(revision.target?.averageCalories.nutritionCalories ?? "—") kcal/day").font(.headline)
                                Text(revision.reason).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(nutrition.adjustments) { adjustment in
                            Text("\(adjustment.evaluatedAt.formatted(date: .abbreviated, time: .omitted)): \(adjustment.status.capitalized) · \(adjustment.proposedCalories.nutritionCalories) kcal suggestion")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding()
        }.background(Color.coachBackground).navigationTitle("Nutrition progress")
            .sheet(isPresented: $showMeasurement) { NutritionMeasurementView() }
    }
    private var points: [NutritionWeightPoint] { nutrition.weightPoints.filter { $0.date >= Calendar.current.date(byAdding: .day, value: -window, to: .now)! } }
    private var weeklyMeans: [NutritionWeightPoint] {
        stride(from: window, through: 7, by: -7).compactMap { offset in
            let start = Calendar.current.date(byAdding: .day, value: -offset, to: Calendar.current.startOfDay(for: .now))!
            let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
            let observations = points.filter { $0.date >= start && $0.date < end }
            guard observations.count >= 4 else { return nil }
            return NutritionWeightPoint(date: end, kg: observations.reduce(0) { $0 + $1.kg } / Double(observations.count), source: "Weekly average")
        }
    }
    private var evidence: [NutritionDailyEvidence] { Array(nutrition.evidence().prefix(window).reversed()) }
    private func displayedWeight(_ kg: Double) -> Double { nutrition.profile.usesMetric ? kg : kg / 0.45359237 }
    private func measurementLabels(_ item: BodyMeasurementRecord) -> [String] {
        [("Waist", item.waistCM), ("Hips", item.hipsCM), ("Arm", item.armCM), ("Thigh", item.thighCM)].compactMap { name, cm in
            cm.map { "\(name): \((nutrition.profile.usesMetric ? $0 : $0 / 2.54).formatted(.number.precision(.fractionLength(1)))) \(nutrition.profile.usesMetric ? "cm" : "in")" }
        }
    }
}

struct NutritionMeasurementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutrition: NutritionModel
    @State private var date = Date.now
    @State private var weight = ""
@State private var waist = ""
@State private var hips = ""
@State private var arm = ""
@State private var thigh = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                Section("Leave unmeasured values blank") {
                    field(nutrition.profile.usesMetric ? "Weight (kg)" : "Weight (lb)", text: $weight)
                    field("Waist \(unit)", text: $waist); field("Hips \(unit)", text: $hips)
                    field("Arm \(unit)", text: $arm); field("Thigh \(unit)", text: $thigh)
                    Text("Use similar conditions for weigh-ins. Changes can reflect hydration, digestion, fat, and muscle; they are not direct measurements of muscle growth.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(Color.coachRose) }
            }.navigationTitle("Log measurements").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    do {
                        func parse(_ text: String, factor: Double) throws -> Double? {
                            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
                            guard let value = Double(text.replacingOccurrences(of: ",", with: ".")) else { throw NutritionError.invalid("Enter numeric measurements or leave the field blank.") }
                            return value * factor
                        }
                        let length = nutrition.profile.usesMetric ? 1.0 : 2.54
                        try nutrition.saveMeasurement(date: date, weight: parse(weight, factor: nutrition.profile.usesMetric ? 1 : 0.45359237),
                            waist: parse(waist, factor: length), hips: parse(hips, factor: length), arm: parse(arm, factor: length), thigh: parse(thigh, factor: length))
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                } }
            }
        }
    }
    private var unit: String { nutrition.profile.usesMetric ? "(cm)" : "(in)" }
    private func field(_ title: String, text: Binding<String>) -> some View { HStack { Text(title); TextField("Optional", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing) } }
}

struct NutritionDailyTotalView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutrition: NutritionModel
    let date: Date
    @State private var amounts = NutritionAmounts.zero
    @State private var confirmed = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Text("This total replaces meal or Health totals for this day. Existing meals stay saved.").foregroundStyle(.secondary)
                value("Calories", amount: $amounts.calories); value("Protein (g)", amount: $amounts.protein)
                value("Carbs (g)", amount: $amounts.carbs); value("Fat (g)", amount: $amounts.fat)
                Toggle("I entered all four values; zero means none", isOn: $confirmed)
                if let error { Text(error).foregroundStyle(Color.coachRose) }
            }.navigationTitle("Daily total").navigationBarTitleDisplayMode(.inline)
            .onAppear { amounts = nutrition.day(on: date)?.manualAmounts ?? .zero }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    do { try nutrition.updateDay(date, manual: amounts); dismiss() } catch { self.error = error.localizedDescription }
                }.disabled(!confirmed) }
            }
        }
    }
    private func value(_ title: String, amount: Binding<Double>) -> some View { HStack { Text(title); TextField(title, value: amount, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) } }
}

struct NutritionSourcesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutrition: NutritionModel
    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Health dietary import") {
                    Toggle("Import dietary data", isOn: Binding(get: { nutrition.healthImportEnabled }, set: { value in Task { await nutrition.setHealthImport(value) } }))
                    Text("Optional read access to calories, protein, carbohydrates and fat. Select one source for each day on the dashboard. Dayvera does not export meals to Health.").font(.footnote).foregroundStyle(.secondary)
                    if let refreshed = nutrition.healthRefreshedAt { LabeledContent("Last refreshed", value: refreshed.formatted(date: .abbreviated, time: .shortened)) }
                    if let error = nutrition.healthError { Text(error).foregroundStyle(Color.coachAmber) }
                    Button("Refresh dietary data") { Task { await nutrition.refreshHealth() } }.disabled(nutrition.isRefreshing || !nutrition.healthImportEnabled)
                    if nutrition.healthSources.isEmpty { Text("No readable dietary samples. Apple Health does not disclose whether read permission was denied.").foregroundStyle(.secondary) }
                    ForEach(nutrition.healthSources, id: \.id) { Text($0.name) }
                }
                Section("Private by design") {
                    Text("Your profile, meals, photos and measurements stay in protected local storage. Photo recognition uses Apple’s on-device model. No cloud model is used.")
                    Text("The food catalog is USDA SR Legacy (2018). Portion weights and preparation still require your review.")
                    Link("USDA FoodData Central", destination: URL(string: "https://fdc.nal.usda.gov/")!)
                }
            }.navigationTitle("Nutrition sources").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
