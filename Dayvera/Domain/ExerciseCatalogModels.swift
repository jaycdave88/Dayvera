import Foundation

struct ExerciseCatalogEnvelope: Decodable, Sendable {
    let name: String
    let homepage: String
    let schemaVersion: Int
    let count: Int
    let exercises: [ExerciseDefinition]

    enum CodingKeys: String, CodingKey {
        case name, homepage, count, exercises
        case schemaVersion = "schema_version"
    }
}

struct ExerciseDefinition: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let summary: String?
    let category: String
    let forceType: String?
    let mechanic: String?
    let difficulty: String?
    let equipment: String?
    let bodyPart: String
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let goals: [String]
    let tags: [String]
    let isUnilateral: Bool
    let isBodyweight: Bool
    let instructions: [String]
    let tips: [String]
    let images: ExerciseImageSet?

    enum CodingKeys: String, CodingKey {
        case id, category, mechanic, difficulty, equipment, goals, tags, images
        case name = "name_en"
        case summary = "description_en"
        case forceType = "force_type"
        case bodyPart = "body_part"
        case primaryMuscles = "primary_muscles"
        case secondaryMuscles = "secondary_muscles"
        case isUnilateral = "is_unilateral"
        case isBodyweight = "is_bodyweight"
        case instructions = "instructions_en"
        case tips = "tips_en"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        summary = try values.decodeIfPresent(String.self, forKey: .summary)
        category = try values.decodeIfPresent(String.self, forKey: .category) ?? "strength"
        forceType = try values.decodeIfPresent(String.self, forKey: .forceType)
        mechanic = try values.decodeIfPresent(String.self, forKey: .mechanic)
        difficulty = try values.decodeIfPresent(String.self, forKey: .difficulty)
        equipment = try values.decodeIfPresent(String.self, forKey: .equipment)
        bodyPart = try values.decodeIfPresent(String.self, forKey: .bodyPart) ?? "full_body"
        primaryMuscles = try values.decodeIfPresent([String].self, forKey: .primaryMuscles) ?? []
        secondaryMuscles = try values.decodeIfPresent([String].self, forKey: .secondaryMuscles) ?? []
        goals = try values.decodeIfPresent([String].self, forKey: .goals) ?? []
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        isUnilateral = try values.decodeIfPresent(Bool.self, forKey: .isUnilateral) ?? false
        isBodyweight = try values.decodeIfPresent(Bool.self, forKey: .isBodyweight) ?? false
        instructions = try values.decodeIfPresent([String].self, forKey: .instructions) ?? []
        tips = try values.decodeIfPresent([String].self, forKey: .tips) ?? []
        images = try values.decodeIfPresent(ExerciseImageSet.self, forKey: .images)
    }

    var equipmentTitle: String {
        if isBodyweight { return "Bodyweight" }
        return (equipment ?? "Other").catalogTitle
    }

    var bodyPartTitle: String { bodyPart.catalogTitle }
    var difficultyTitle: String { (difficulty ?? "Not rated").catalogTitle }
    var primaryMuscleTitle: String { (primaryMuscles.first ?? bodyPart).catalogTitle }

    var imagePaths: [String] {
        guard let flat = images?.flat else { return [] }
        return [flat.start, flat.peak, flat.main]
            .compactMap { $0 }
            .reduce(into: []) { paths, path in
                if !paths.contains(path) { paths.append(path) }
            }
    }

    func imageURL(for path: String) -> URL? {
        guard let url = URL(string: path, relativeTo: ExerciseCatalogSource.mediaBaseURL)?.absoluteURL,
              url.scheme == "https",
              url.host == ExerciseCatalogSource.mediaBaseURL.host else {
            return nil
        }
        return url
    }

    var thumbnailURL: URL? {
        imagePaths.first.flatMap(imageURL)
    }

    var searchableText: String {
        var terms = [name, summary ?? "", equipmentTitle, bodyPartTitle, difficultyTitle]
        terms.append(contentsOf: primaryMuscles.map(\.catalogTitle))
        terms.append(contentsOf: secondaryMuscles.map(\.catalogTitle))
        terms.append(contentsOf: goals.map(\.catalogTitle))
        terms.append(contentsOf: tags.map(\.catalogTitle))
        terms.append(forceType?.catalogTitle ?? "")
        terms.append(mechanic?.catalogTitle ?? "")
        terms.append(contentsOf: instructions)
        terms.append(contentsOf: tips)
        return terms
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    func matches(
        query: String,
        equipment selectedEquipment: String?,
        muscle selectedMuscle: String?,
        difficulty selectedDifficulty: String?
    ) -> Bool {
        let normalizedQuery = query
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let matchesQuery = normalizedQuery.isEmpty || searchableText.contains(normalizedQuery)
        let matchesEquipment = selectedEquipment == nil || equipmentTitle == selectedEquipment
        let muscleTitles = (primaryMuscles + secondaryMuscles).map(\.catalogTitle)
        let matchesMuscle = selectedMuscle == nil || muscleTitles.contains(selectedMuscle!) || bodyPartTitle == selectedMuscle
        let matchesDifficulty = selectedDifficulty == nil || difficultyTitle == selectedDifficulty
        return matchesQuery && matchesEquipment && matchesMuscle && matchesDifficulty
    }

    func workoutExercise(loadUnit: LoadUnit = .pounds) -> WorkoutExercise {
        let compound = mechanic?.lowercased() == "compound"
        return WorkoutExercise(
            catalogID: id,
            equipment: equipmentTitle,
            movementPattern: planningMovementPattern,
            name: name,
            muscleGroup: mappedMuscleGroup,
            workingSets: 3,
            targetReps: compound ? 6 : 10,
            // A catalog cannot know a safe, personal training load. The
            // template editor asks the user to review this neutral value.
            targetWeight: 0,
            loadUnit: loadUnit,
            targetRPE: 7,
            restSeconds: compound ? 120 : 75
        )
    }

    private var mappedMuscleGroup: MuscleGroup {
        let value = ([bodyPart] + primaryMuscles).joined(separator: " ").lowercased()
        if value.contains("chest") || value.contains("pector") { return .chest }
        if value.contains("lat") || value.contains("back") || value.contains("trap") || value.contains("rhomboid") || value.contains("erector") { return .back }
        if value.contains("shoulder") || value.contains("deltoid") || value.contains("rotator") { return .shoulders }
        if value.contains("bicep") || value.contains("tricep") || value.contains("forearm") || value.contains("arm") { return .arms }
        if value.contains("quad") { return .quads }
        if value.contains("hamstring") { return .hamstrings }
        if value.contains("glute") { return .glutes }
        if value.contains("calf") || value.contains("gastrocnemius") || value.contains("soleus") { return .calves }
        if value.contains("core") || value.contains("abdomin") || value.contains("oblique") { return .core }
        return .fullBody
    }

    private var planningMovementPattern: String {
        let value = ([name, bodyPart, forceType ?? "", mechanic ?? ""] + tags)
            .joined(separator: " ")
            .lowercased()
        if value.contains("squat") || value.contains("leg press") { return "squat" }
        if value.contains("deadlift") || value.contains("hinge") || value.contains("good morning") { return "hinge" }
        if value.contains("bench") || value.contains("push-up") || value.contains("chest press") { return "horizontalPush" }
        if value.contains("row") { return "horizontalPull" }
        if value.contains("overhead") || value.contains("shoulder press") || value.contains("military press") { return "verticalPush" }
        if value.contains("pull-up") || value.contains("chin-up") || value.contains("pulldown") { return "verticalPull" }
        if value.contains("lunge") || value.contains("split squat") || value.contains("step-up") { return "singleLeg" }
        if value.contains("carry") || value.contains("farmer") { return "carry" }
        if mappedMuscleGroup == .core { return "core" }
        return "isolation"
    }
}

struct ExerciseImageSet: Decodable, Hashable, Sendable {
    let flat: ExerciseFlatImages?
}

struct ExerciseFlatImages: Decodable, Hashable, Sendable {
    let start: String?
    let peak: String?
    let main: String?
}

enum ExerciseCatalogSource {
    static let supportedSchemaVersion = 3
    static let catalogURL = URL(string: "https://exercise-dataset.com/exercises.json")!
    static let mediaBaseURL = URL(string: "https://exercise-dataset.com/")!
    static let homepageURL = URL(string: "https://repdb.co")!
    static let licenseURL = URL(string: "https://github.com/RepDB/exercise-dataset/blob/main/LICENSE-DATA.md")!
    static let attribution = "Exercise data by RepDB (repdb.co)"
}

enum ExerciseCatalogDecoder {
    static func decode(_ data: Data) throws -> [ExerciseDefinition] {
        let envelope = try JSONDecoder().decode(ExerciseCatalogEnvelope.self, from: data)
        guard envelope.schemaVersion == ExerciseCatalogSource.supportedSchemaVersion else {
            throw ExerciseCatalogError.unsupportedSchema(envelope.schemaVersion)
        }
        guard envelope.count == envelope.exercises.count else {
            throw ExerciseCatalogError.countMismatch(expected: envelope.count, decoded: envelope.exercises.count)
        }
        let strength = envelope.exercises.filter { $0.category.lowercased() == "strength" }
        guard !strength.isEmpty else { throw ExerciseCatalogError.empty }
        let ids = Set(strength.map(\.id))
        guard ids.count == strength.count else { throw ExerciseCatalogError.duplicateIdentifiers }
        return strength.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

enum ExerciseCatalogError: LocalizedError {
    case empty
    case duplicateIdentifiers
    case invalidResponse
    case incomplete(Int)
    case unsupportedSchema(Int)
    case countMismatch(expected: Int, decoded: Int)

    var errorDescription: String? {
        switch self {
        case .empty: "The exercise catalog did not contain strength exercises."
        case .duplicateIdentifiers: "The exercise catalog contains duplicate identifiers."
        case .invalidResponse: "The exercise catalog server returned an invalid response."
        case .incomplete(let count): "Only \(count) exercises were returned; the catalog was not replaced."
        case .unsupportedSchema(let version): "Exercise catalog schema \(version) is not supported by this app version."
        case .countMismatch(let expected, let decoded): "The exercise catalog declared \(expected) exercises but supplied \(decoded)."
        }
    }
}

private extension String {
    var catalogTitle: String {
        replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
