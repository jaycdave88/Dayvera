import SwiftUI

enum MealEditorInitialAction {
    case takePhoto, choosePhoto, search, nutritionLabel
}

struct MealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutrition: NutritionModel
    let existing: MealRecord?
    @State private var name: String
    @State private var date: Date
    @State private var entries: [FoodEntry]
    @State private var photo: Data?
    @State private var candidates: [RecognizedFood] = []
    @State private var searchRequest: FoodSearchRequest?
    @State private var editEntry: FoodEntry?
    @State private var showCapture = false
    @State private var captureSource: FoodCaptureSource = .choice
    @State private var appliedInitialAction = false
    @State private var reviewed = false
    @State private var error: String?
    private let initialAction: MealEditorInitialAction?
    private let onSaved: (() -> Void)?

    init(existing: MealRecord? = nil, date: Date = .now, capture: Bool = false, initialAction: MealEditorInitialAction? = nil, onSaved: (() -> Void)? = nil) {
        self.existing = existing; _name = State(initialValue: existing?.name ?? "Meal")
        _date = State(initialValue: existing?.date ?? date)
        _entries = State(initialValue: existing?.entries ?? [])
        self.initialAction = initialAction ?? (capture ? .takePhoto : nil)
        self.onSaved = onSaved
    }

    init(copying meal: MealRecord, date: Date, onSaved: (() -> Void)? = nil) {
        existing = nil
        _name = State(initialValue: meal.name)
        _date = State(initialValue: date)
        _entries = State(initialValue: meal.entries)
        initialAction = nil
        self.onSaved = onSaved
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Meal name", text: $name)
                    DatePicker("When", selection: $date, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                    if let data = photo ?? existing?.photoFilename.flatMap({ NutritionStore.photoURL($0).flatMap { try? Data(contentsOf: $0) } }), let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 210).clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    Button { captureSource = .choice; showCapture = true } label: { Label("Add or replace photo", systemImage: "camera.fill") }
                        .frame(minHeight: 44)
                }
                if !candidates.isEmpty {
                    Section("Check the detected foods") {
                        ForEach(candidates) { candidate in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(candidate.name).font(.headline)
                                Text("Estimated portion · ~\(Int(candidate.estimatedGrams)) g").foregroundStyle(.secondary)
                                Text("Food match needed").font(.subheadline.weight(.semibold)).foregroundStyle(Color.coachAmber)
                                Text(candidate.question).font(.footnote)
                                HStack {
                                    Button("Find Food") { searchRequest = FoodSearchRequest(candidate: candidate) }.buttonStyle(.borderedProminent)
                                    Button("Remove", role: .destructive) { candidates.removeAll { $0.id == candidate.id } }.buttonStyle(.borderless)
                                }
                            }.padding(.vertical, 4)
                        }
                        Text("Photos can miss ingredients, oils, sauces, and exact portions. Match every suggestion to a trusted catalog food before saving.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Foods and portions") {
                    ForEach(entries) { entry in
                        Button { editEntry = entry } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name).foregroundStyle(.primary)
                                Text("\(entry.grams.formatted(.number.precision(.fractionLength(0...1)))) g · \(Int(entry.nutrients.calories.rounded())) kcal").font(.subheadline)
                                Text(entry.provenance.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.onDelete { entries.remove(atOffsets: $0); reviewed = false }
                    Button { searchRequest = FoodSearchRequest() } label: { Label("Add Missing Food", systemImage: "plus.circle.fill") }
                        .frame(minHeight: 44)
                }
                Section("Meal total") {
                    let total = entries.reduce(NutritionAmounts.zero) { $0 + $1.nutrients }
                    LabeledContent("Calories", value: "\(Int(total.calories.rounded())) kcal")
                    LabeledContent("Protein / carbs / fat", value: "\(Int(total.protein.rounded())) / \(Int(total.carbs.rounded())) / \(Int(total.fat.rounded())) g")
                    Text("Database and label calories can differ from 4/4/9 macro arithmetic because of fiber and food-specific energy factors.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("I checked the foods, portions, and preparation", isOn: $reviewed)
                    if nutrition.day(on: date)?.source != nil && nutrition.day(on: date)?.source != "meals" {
                        Text("This day currently uses another intake source. The meal will be saved; choose Dayvera meals on the dashboard to count it instead.").font(.footnote).foregroundStyle(Color.coachAmber)
                    }
                }
                if let error { Text(error).foregroundStyle(Color.coachRose) }
            }.navigationTitle(!candidates.isEmpty ? "Review Foods" : existing == nil ? "Review Meal" : "Edit Meal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save meal") {
                        do {
                            try nutrition.saveMeal(id: existing?.id, name: name, date: date, entries: entries, photo: photo)
                            onSaved?()
                            dismiss()
                        }
                        catch { self.error = error.localizedDescription }
                    }.disabled(!reviewed || entries.isEmpty || !candidates.isEmpty)
                }
            }
            .onAppear { applyInitialActionIfNeeded() }
            .sheet(isPresented: $showCapture) {
                FoodCaptureView(initialSource: captureSource) { data, result in photo = data; candidates = result; reviewed = false }
            }
            .sheet(item: $searchRequest) { request in
                FoodSearchView(request: request) { entry in
                    entries.append(entry); reviewed = false
                    if let id = request.candidate?.id { candidates.removeAll { $0.id == id } }
                }
            }
            .sheet(item: $editEntry) { entry in
                FoodEntryEditor(entry: entry) { updated in
                    if let index = entries.firstIndex(where: { $0.id == updated.id }) { entries[index] = updated; reviewed = false }
                }
            }
        }
    }

    private func applyInitialActionIfNeeded() {
        guard !appliedInitialAction else { return }
        appliedInitialAction = true
        switch initialAction {
        case .takePhoto:
            captureSource = .camera; showCapture = true
        case .choosePhoto:
            captureSource = .photoLibrary; showCapture = true
        case .search:
            searchRequest = FoodSearchRequest()
        case .nutritionLabel:
            searchRequest = FoodSearchRequest(directCustom: true)
        case nil:
            break
        }
    }
}

struct FoodSearchRequest: Identifiable {
    let id = UUID()
    var candidate: RecognizedFood? = nil
    var directCustom = false
}

struct FoodSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutrition: NutritionModel
    let request: FoodSearchRequest
    let onAdd: (FoodEntry) -> Void
    @State private var query = ""
    @State private var selection: CatalogFood?
    @State private var grams = 100.0
    @State private var custom = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search foods, e.g. chicken roasted", text: $query).autocorrectionDisabled()
                    Text("Try a simple ingredient and preparation, such as ‘rice cooked’. USDA SR Legacy is a reference catalog, not a live branded-food directory.").font(.footnote).foregroundStyle(.secondary)
                    if nutrition.catalog == nil { Text("The food catalog could not be loaded. Use manual values.").foregroundStyle(Color.coachAmber) }
                    Button("Enter custom food or label values") { custom = true }
                }
                if let selection {
                    Section("Confirm the match and portion") {
                        Text(selection.name).font(.headline)
                        HStack { Text("Grams"); TextField("Grams", value: $grams, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        ForEach(selection.portions, id: \.self) { portion in
                            Button("\(portion.label) · \(portion.grams.formatted()) g") { grams = portion.grams }
                        }
                        if let question = request.candidate?.question { Text(question).font(.footnote).foregroundStyle(.secondary) }
                        let preview = selection.nutrients.scaled(max(grams, 0) / 100)
                        LabeledContent("Calories", value: "\(Int(preview.calories.rounded())) kcal")
                        LabeledContent("Protein", value: "\(preview.protein.nutritionGrams) g")
                        LabeledContent("Carbs", value: "\(preview.carbs.nutritionGrams) g")
                        LabeledContent("Fat", value: "\(preview.fat.nutritionGrams) g")
                        Label("Trusted catalog match · USDA SR Legacy", systemImage: "checkmark.shield")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Add this food") {
                            do {
                                guard let catalog = nutrition.catalog else { return }
                                let entry = try catalog.entry(food: selection, grams: grams, photo: request.candidate != nil, note: request.candidate?.question ?? "")
                                onAdd(entry); dismiss()
                            } catch { self.error = error.localizedDescription }
                        }.buttonStyle(.borderedProminent)
                    }
                }
                Section("Database matches") {
                    ForEach(nutrition.catalog?.search(query) ?? []) { food in
                        Button { selection = food } label: {
                            VStack(alignment: .leading) {
                                Text(food.name).foregroundStyle(.primary)
                                Text("\(Int(food.nutrients.calories)) kcal / 100 g · FDC \(food.id)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !query.isEmpty && (nutrition.catalog?.search(query).isEmpty ?? true) {
                        Text("No match. Simplify the search, enter ingredients separately, or use label values.").foregroundStyle(.secondary)
                    }
                }
                if let error { Text(error).foregroundStyle(Color.coachRose) }
            }.navigationTitle("Find food").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                query = request.candidate?.name ?? ""
                grams = request.candidate?.estimatedGrams ?? 100
                if request.directCustom { custom = true }
            }
            .sheet(isPresented: $custom) {
                FoodEntryEditor(entry: FoodEntry(name: query, grams: grams, nutrients: .zero, provenance: .manual), isNew: true) {
                    onAdd($0); dismiss()
                }
            }
        }
    }
}

struct FoodEntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: FoodEntry
    var isNew = false
    let onSave: (FoodEntry) -> Void
    @State private var error: String?
    @State private var valuesConfirmed = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Food name", text: $entry.name)
                    number("Portion (grams)", value: Binding(get: { entry.grams }, set: { value in
                        if !isNew && entry.grams > 0 && value > 0 { entry.nutrients = entry.nutrients.scaled(value / entry.grams) }
                        entry.grams = value
                    }))
                    if !isNew { Text("Changing the portion scales this entry’s saved nutrient values.").font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Values for this entire portion") {
                    number("Calories (kcal)", value: nutrientBinding(\.calories))
                    number("Protein (g)", value: nutrientBinding(\.protein))
                    number("Carbohydrate (g)", value: nutrientBinding(\.carbs))
                    number("Fat (g)", value: nutrientBinding(\.fat))
                    Text("Enter the amount you ate, not values per 100 grams. Do not infer missing nutrients as zero.").font(.footnote).foregroundStyle(.secondary)
                }.onChange(of: entry.nutrients) { _, _ in
                    if isNew { entry.provenance = .manual }
                }
                Toggle("All four nutrient values are known; zero means none", isOn: $valuesConfirmed)
                if let error { Text(error).foregroundStyle(Color.coachRose) }
            }.navigationTitle(isNew ? "Custom food" : "Adjust food")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    guard !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          entry.grams.isFinite, (0.1...10_000).contains(entry.grams), entry.nutrients.isValid else {
                        error = "Check the food name, portion and nonnegative nutrient values."; return
                    }
                    onSave(entry); dismiss()
                }.disabled(!valuesConfirmed) }
            }
        }
    }
    private func nutrientBinding(_ keyPath: WritableKeyPath<NutritionAmounts, Double>) -> Binding<Double> {
        Binding(get: { entry.nutrients[keyPath: keyPath] }, set: { value in
            entry.nutrients[keyPath: keyPath] = value
            entry.provenance = .manual; entry.catalogID = nil; entry.catalogVersion = nil
        })
    }
    private func number(_ title: String, value: Binding<Double>) -> some View {
        HStack { Text(title); Spacer(); TextField(title, value: value, format: .number.precision(.fractionLength(0...1))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 100) }
    }
}
