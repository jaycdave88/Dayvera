import SwiftUI

struct NutritionWhatIfView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutrition: NutritionModel
    @State private var delta = 200.0
    @State private var protein = 1.8
    @State private var cycling = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if let current = nutrition.target(on: .now) {
                    Section {
                        Label("SCENARIO · NOT APPLIED", systemImage: "slider.horizontal.3")
                            .font(.caption.bold()).foregroundStyle(Color.coachIndigo)
                            .accessibilityLabel("Scenario. Not applied")
                        Text("Explore a change before committing.").font(.headline)
                        Text("This is a scenario, not a prediction of muscle or fat gain. Weight also changes with water, glycogen, digestion and activity.").foregroundStyle(.secondary)
                    }
                    Section("Your scenario") {
                        LabeledContent("Daily energy change", value: String(format: "%+.0f kcal", delta))
                        Slider(value: $delta, in: -300...300, step: 50).accessibilityLabel("Calorie change")
                        LabeledContent("Protein", value: String(format: "%.1f g/kg", protein))
                        Slider(value: $protein, in: nutrition.profile.goal.proteinRange, step: 0.1).accessibilityLabel("Protein per kilogram")
                        Toggle("Training/rest-day cycling", isOn: $cycling)
                    }
                    if let target = scenario {
                        Section("Comparison") {
                            LabeledContent("Current daily average", value: "\(current.averageCalories.nutritionCalories) kcal")
                            LabeledContent("Scenario daily average", value: "\(target.averageCalories.nutritionCalories) kcal")
                            LabeledContent("Training day", value: "\(target.trainingDay.calories.nutritionCalories) kcal")
                            LabeledContent("Rest day", value: "\(target.restDay.calories.nutritionCalories) kcal")
                            LabeledContent("Protein", value: "\(target.trainingDay.protein.nutritionGrams) g")
                            LabeledContent("Training carbs / fat", value: "\(target.trainingDay.carbs.nutritionGrams) / \(target.trainingDay.fat.nutritionGrams) g")
                            LabeledContent("Weekly energy change", value: String(format: "%+.0f kcal", delta * 7))
                            Text("A 200-kcal increase adds 1,400 kcal per week. It does not establish how much will become muscle, fat, or increased expenditure.").font(.footnote).foregroundStyle(.secondary)
                            Button("Apply Tomorrow") {
                                do { try nutrition.applyScenario(calories: target.averageCalories, protein: protein, cycling: cycling); dismiss() }
                                catch { self.error = error.localizedDescription }
                            }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                            Button("Reset") { resetScenario() }.frame(minHeight: 44)
                        }
                    } else { Text(scenarioError ?? "This scenario cannot be calculated.").foregroundStyle(Color.coachAmber) }
                    Section("Am I eating enough?") {
                        Text(nutrition.underfuelingMessage ?? "Compare confirmed complete days with your target and weekly progress. A partial food log cannot establish adequate intake.")
                    }
                } else { Text("Set up an eligible nutrition profile first.") }
                if let error { Text(error).foregroundStyle(Color.coachRose) }
            }.navigationTitle("What if?").navigationBarTitleDisplayMode(.inline)
            .onAppear { resetScenario() }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
    private func calculate() throws -> NutritionTarget {
        guard let current = nutrition.target(on: .now), var profile = nutrition.revision(on: .now)?.profile else { throw NutritionError.invalid("No current target.") }
        profile.proteinPerKG = protein; profile.cyclesCalories = cycling
        return try NutritionEngine.calculate(profile, calorieOverride: current.averageCalories + delta)
    }
    private var scenario: NutritionTarget? { try? calculate() }
    private var scenarioError: String? { do { _ = try calculate(); return nil } catch { return error.localizedDescription } }
    private func resetScenario() {
        delta = 0
        protein = nutrition.revision(on: .now)?.profile?.proteinPerKG ?? nutrition.profile.proteinPerKG
        cycling = nutrition.revision(on: .now)?.profile?.cyclesCalories ?? false
    }
}
