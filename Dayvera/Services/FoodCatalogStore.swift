import Foundation

struct FoodCatalogStore: Sendable {
    struct Document: Decodable { let version: String; let foods: [CatalogFood] }
    let version: String
    let foods: [CatalogFood]
    private let normalizedNames: [String]

    init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "FoodCatalog", withExtension: "json") else {
            throw NutritionError.invalid("The offline food catalog is missing. Manual entry is still available.")
        }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        version = document.version; foods = document.foods
        normalizedNames = foods.map { Self.normalize($0.name) }
    }

    func search(_ query: String, limit: Int = 30) -> [CatalogFood] {
        let terms = Self.normalize(query).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        return foods.indices.compactMap { i -> (Int, Int)? in
            let name = normalizedNames[i]
            guard terms.allSatisfy({ name.contains($0) }) else { return nil }
            let score = (name.hasPrefix(terms[0]) ? 1000 : 0) - name.count
            return (i, score)
        }.sorted { $0.1 == $1.1 ? foods[$0.0].id < foods[$1.0].id : $0.1 > $1.1 }
            .prefix(limit).map { foods[$0.0] }
    }

    func entry(food: CatalogFood, grams: Double, photo: Bool = false, note: String = "") throws -> FoodEntry {
        guard foods.contains(where: { $0.id == food.id }), grams.isFinite, (0.1...10_000).contains(grams) else {
            throw NutritionError.invalid("Select a catalog food and a portion between 0.1 and 10,000 grams.")
        }
        return FoodEntry(name: food.name, grams: grams, nutrients: food.nutrients.scaled(grams / 100),
                         catalogID: food.id, catalogVersion: version, provenance: photo ? .photo : .database, portionNote: note)
    }

    func entry(food: CatalogFood, portion: FoodPortion, count: Double = 1, photo: Bool = false, note: String = "") throws -> FoodEntry {
        guard foods.contains(where: { $0.id == food.id }), food.portions.contains(portion),
              count.isFinite, (0.01...1000).contains(count), portion.grams.isFinite, portion.grams > 0 else {
            throw NutritionError.invalid("Select a catalog portion and a valid count.")
        }
        let quantity = Self.quantity(from: portion)
        let grams = portion.grams * count
        let portionNote = [note, "Catalog portion: \(portion.label)"].filter { !$0.isEmpty }.joined(separator: " · ")
        return FoodEntry(name: food.name, grams: grams, nutrients: food.nutrients.scaled(grams / 100),
                         catalogID: food.id, catalogVersion: version, provenance: photo ? .photo : .database,
                         portionNote: portionNote, amount: quantity.amount, unit: quantity.unit,
                         count: count, gramsPerUnit: portion.grams / quantity.amount)
    }

    static func quantity(from portion: FoodPortion) -> (amount: Double, unit: String) {
        let pieces = portion.label.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard let first = pieces.first, let amount = Double(first), amount > 0 else {
            return (1, portion.label)
        }
        let unit = pieces.count > 1 ? String(pieces[1]) : "portion"
        return (amount, unit)
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
    }
}
