import SwiftUI

struct NutritionSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutrition: NutritionModel
    @State var draft: NutritionProfile
    @State private var error: String?
    @State private var measurementEditor: ProfileMeasurementEditor?

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
                    measurementRow("Height", value: heightDescription) { measurementEditor = .height }
                    measurementRow("Weight", value: weightDescription) { measurementEditor = .weight }
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
            .sheet(item: $measurementEditor) { editor in
                ProfileMeasurementEditorSheet(kind: editor, usesMetric: draft.usesMetric,
                                              initialValue: editor == .height ? draft.heightCM : draft.weightKG) { value in
                    if editor == .height { draft.heightCM = value }
                    else {
                        draft.weightKG = value
                        draft.measurementSource = "User entered"
                        draft.measurementDate = .now
                    }
                }
            }
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

    private func measurementRow(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(value).foregroundStyle(.secondary).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }.frame(minHeight: 44)
        }
    }

    private var heightDescription: String {
        if draft.usesMetric { return "\(draft.heightCM.formatted(.number.precision(.fractionLength(0...1)))) cm" }
        let inches = Int((draft.heightCM / 2.54).rounded())
        return "\(inches / 12) ft \(inches % 12) in"
    }

    private var weightDescription: String {
        let value = draft.usesMetric ? draft.weightKG : draft.weightKG / 0.45359237
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(draft.usesMetric ? "kg" : "lb")"
    }
}

private enum ProfileMeasurementEditor: String, Identifiable {
    case height, weight
    var id: String { rawValue }
}

private struct ProfileMeasurementEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let kind: ProfileMeasurementEditor
    let usesMetric: Bool
    let onSave: (Double) -> Void
    @State private var value: Double
    @State private var feet: Int
    @State private var inches: Int

    init(kind: ProfileMeasurementEditor, usesMetric: Bool, initialValue: Double, onSave: @escaping (Double) -> Void) {
        self.kind = kind
        self.usesMetric = usesMetric
        self.onSave = onSave
        _value = State(initialValue: kind == .weight && !usesMetric ? initialValue / 0.45359237 : initialValue)
        let totalInches = Int((initialValue / 2.54).rounded())
        _feet = State(initialValue: totalInches / 12)
        _inches = State(initialValue: totalInches % 12)
    }

    var body: some View {
        NavigationStack {
            Form {
                if kind == .height && !usesMetric {
                    Section("Height") {
                        Picker("Feet", selection: $feet) { ForEach(3...8, id: \.self) { Text("\($0) ft").tag($0) } }
                            .pickerStyle(.wheel)
                        Picker("Inches", selection: $inches) { ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) } }
                            .pickerStyle(.wheel)
                    }
                } else {
                    Section {
                        HStack {
                            TextField(kind == .height ? "Height" : "Weight", value: $value,
                                      format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                            Text(kind == .height ? "cm" : usesMetric ? "kg" : "lb").foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(kind == .height ? "Height" : "Weight")
                    } footer: {
                        Text(kind == .height ? "Supported estimate range: 120–230 cm." : "Supported estimate range: 35–300 kg.")
                    }
                }
            }
            .navigationTitle("Edit \(kind.rawValue.capitalized)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(canonicalValue)
                        dismiss()
                    }
                    .disabled(!canonicalValue.isFinite || !supportedRange.contains(canonicalValue))
                }
            }
        }
    }

    private var canonicalValue: Double {
        if kind == .height && !usesMetric { return Double(feet * 12 + inches) * 2.54 }
        if kind == .weight && !usesMetric { return value * 0.45359237 }
        return value
    }

    private var supportedRange: ClosedRange<Double> {
        kind == .height ? 120...230 : 35...300
    }
}
