import SwiftUI

struct NutritionSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutrition: NutritionModel
    @State var draft: NutritionProfile
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Fuel the work. Support the recovery.").font(.title2.bold())
                    Text("Start with an estimate, then learn from consistent intake and weight records. Photos make logging easier; they cannot measure portions.")
                        .foregroundStyle(.secondary)
                }
                Section("Your starting point") {
                    Toggle("Metric units", isOn: $draft.usesMetric)
                    Stepper("Age: \(draft.age)", value: $draft.age, in: 1...100)
                    Picker("Energy equation", selection: $draft.sex) {
                        ForEach(NutritionSex.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Text("The original equation uses sex-based coefficients. Use both estimates if neither is appropriate; this increases uncertainty.").font(.footnote).foregroundStyle(.secondary)
                    if draft.usesMetric {
                        numberField("Height (cm)", value: $draft.heightCM)
                    } else {
                        imperialHeightFields
                    }
                    numberField(draft.usesMetric ? "Weight (kg)" : "Weight (lb)", value: Binding(
                        get: { draft.usesMetric ? draft.weightKG : draft.weightKG / 0.45359237 },
                        set: { draft.weightKG = draft.usesMetric ? $0 : $0 * 0.45359237; draft.measurementSource = "User entered"; draft.measurementDate = .now }))
                    Toggle("Include body-fat estimate", isOn: Binding(get: { draft.bodyFatPercent != nil }, set: { draft.bodyFatPercent = $0 ? 20 : nil }))
                    if draft.bodyFatPercent != nil {
                        numberField("Body fat (%)", value: Binding(get: { draft.bodyFatPercent ?? 20 }, set: { draft.bodyFatPercent = $0 }))
                    }
                    Text("\(draft.measurementSource) · \(draft.measurementDate.formatted(date: .abbreviated, time: .omitted)). Confirm these values. Body-fat readings inform progress, not the calorie equation.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Activity and training") {
                    Picker("Whole-day activity", selection: $draft.activity) {
                        ForEach(NutritionActivity.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Text(draft.activity.detail + " Include work and exercise together; workout calories are not added twice.").font(.footnote).foregroundStyle(.secondary)
                    Stepper("Training days: \(draft.trainingDays)/week", value: $draft.trainingDays, in: 0...7)
                    Stepper("Typical session: \(draft.trainingMinutes) min", value: $draft.trainingMinutes, in: 10...240, step: 5)
                    Picker("Experience", selection: $draft.experience) {
                        ForEach(["Beginner", "Intermediate", "Experienced"], id: \.self) { Text($0) }
                    }
                }
                Section("Goal and macros") {
                    Picker("Goal", selection: $draft.goal) { ForEach(NutritionGoal.allCases) { Text($0.rawValue).tag($0) } }
                        .onChange(of: draft.goal) { _, goal in draft.proteinPerKG = goal.defaultProtein; draft.calorieOffset = goal.defaultOffset }
                    if draft.goal == .gain || draft.goal == .loss {
                        LabeledContent("Calorie adjustment", value: String(format: "%+.0f%%", draft.calorieOffset * 100))
                        Slider(value: $draft.calorieOffset, in: draft.goal == .gain ? 0.05...0.10 : -0.15 ... -0.10, step: 0.01)
                            .accessibilityLabel("Calorie adjustment")
                    }
                    LabeledContent("Protein", value: String(format: "%.1f g/kg", draft.proteinPerKG))
                    Slider(value: $draft.proteinPerKG, in: draft.goal.proteinRange, step: 0.1).accessibilityLabel("Protein per kilogram")
                    Toggle("More carbohydrates on training days", isOn: $draft.cyclesCalories)
                    Text("Optional 200-calorie training/rest difference with the same weekly average. Protein stays consistent.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Muscles you want to develop") {
                    ForEach(MuscleGroup.allCases.filter { $0 != .fullBody }) { muscle in
                        Toggle(muscle.title, isOn: Binding(get: { draft.musclePriorities.contains(muscle) }, set: {
                            if $0 { draft.musclePriorities.insert(muscle) } else { draft.musclePriorities.remove(muscle) }
                        }))
                    }
                    Text("Nutrition supports overall muscle growth. Targeted resistance training determines which muscles receive the strongest stimulus. Food cannot direct growth to one body area.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Appropriate guidance") {
                    Toggle("Pregnant, breastfeeding, or need supervised nutrition", isOn: $draft.needsSupervision)
                    Text("Includes an eating disorder, a condition affecting nutrition needs, or a clinician-prescribed diet. Personal calorie targets will be unavailable; a food journal remains available.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Current illness or concerning symptoms", isOn: $draft.illnessOrSymptoms)
                    Toggle("I am an adult and these estimates are appropriate for me", isOn: $draft.confirmedEligibility)
                    Text("This calculator’s guardrails are not proof that an intake is adequate. Persistent fatigue, rapid unintended weight change, or impaired recovery warrant professional review.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(Color.coachRose) } }
            }
            .navigationTitle("Nutrition profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try nutrition.saveProfile(draft); dismiss() } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }
    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        HStack { Text(title); Spacer(); TextField(title, value: value, format: .number.precision(.fractionLength(0...1))).multilineTextAlignment(.trailing).keyboardType(.decimalPad).frame(maxWidth: 110) }
    }

    private var imperialHeightFields: some View {
        HStack(spacing: 8) {
            Text("Height")
            Spacer()
            TextField("Feet", value: imperialFeet, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 42)
                .accessibilityLabel("Height feet")
            Text("ft").foregroundStyle(.secondary)
            TextField("Inches", value: imperialInches, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 42)
                .accessibilityLabel("Height inches")
            Text("in").foregroundStyle(.secondary)
        }
    }

    private var imperialFeet: Binding<Int> {
        Binding(
            get: { totalImperialInches / 12 },
            set: { feet in
                let inches = totalImperialInches % 12
                draft.heightCM = Double(max(feet, 0) * 12 + inches) * 2.54
            }
        )
    }

    private var imperialInches: Binding<Int> {
        Binding(
            get: { totalImperialInches % 12 },
            set: { inches in
                let feet = totalImperialInches / 12
                draft.heightCM = Double(feet * 12 + min(max(inches, 0), 11)) * 2.54
            }
        )
    }

    private var totalImperialInches: Int {
        max(Int((draft.heightCM / 2.54).rounded()), 0)
    }
}
