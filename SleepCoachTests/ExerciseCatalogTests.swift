import XCTest
@testable import SleepCoach

final class ExerciseCatalogTests: XCTestCase {
    func testCatalogDecodesSearchesAndBuildsTemplateExercise() throws {
        let exercise = try XCTUnwrap(ExerciseCatalogDecoder.decode(fixture()).first)

        XCTAssertEqual(exercise.name, "Fixture Goblet Squat")
        XCTAssertEqual(exercise.equipmentTitle, "Kettlebell")
        XCTAssertEqual(exercise.imagePaths, ["images/flat/fixture-start.webp", "images/flat/fixture-peak.webp"])
        XCTAssertTrue(exercise.matches(query: "quadriceps", equipment: "Kettlebell", muscle: nil, difficulty: "Beginner"))
        XCTAssertTrue(exercise.matches(query: "whole foot planted", equipment: nil, muscle: nil, difficulty: nil))
        XCTAssertFalse(exercise.matches(query: "bench", equipment: nil, muscle: nil, difficulty: nil))
        XCTAssertEqual(exercise.imageURL(for: exercise.imagePaths[0])?.host, "exercise-dataset.com")
        XCTAssertNil(exercise.imageURL(for: "https://example.com/untrusted.webp"))

        let workoutExercise = exercise.workoutExercise()
        XCTAssertEqual(workoutExercise.catalogID, "fixture-goblet-squat")
        XCTAssertEqual(workoutExercise.muscleGroup, .quads)
        XCTAssertEqual(workoutExercise.workingSets, 3)
        XCTAssertEqual(workoutExercise.targetWeight, 0, "Catalog exercises must not invent a personal training load")
    }

    func testCatalogRejectsDuplicateIdentifiers() {
        var object = try! JSONSerialization.jsonObject(with: fixture()) as! [String: Any]
        let item = (object["exercises"] as! [[String: Any]])[0]
        object["exercises"] = [item, item]
        object["count"] = 2
        let data = try! JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try ExerciseCatalogDecoder.decode(data)) { error in
            guard case ExerciseCatalogError.duplicateIdentifiers = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testCatalogRejectsUnsupportedSchemaAndCountMismatch() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        object["schema_version"] = 99
        var data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try ExerciseCatalogDecoder.decode(data)) { error in
            guard case ExerciseCatalogError.unsupportedSchema(99) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        object["schema_version"] = ExerciseCatalogSource.supportedSchemaVersion
        object["count"] = 2
        data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try ExerciseCatalogDecoder.decode(data)) { error in
            guard case ExerciseCatalogError.countMismatch(expected: 2, decoded: 1) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testWorkoutExerciseDecodesOlderTemplateWithoutCatalogIdentifier() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "name": "Custom Squat",
          "muscleGroup": "quads",
          "workingSets": 3,
          "targetReps": 8,
          "targetWeight": 95,
          "targetRPE": 7,
          "restSeconds": 90,
          "supersetGroup": null
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WorkoutExercise.self, from: json)

        XCTAssertNil(decoded.catalogID)
        XCTAssertEqual(decoded.name, "Custom Squat")
    }

    private func fixture() -> Data {
        """
        {
          "name": "Fixture catalog",
          "homepage": "https://example.com",
          "schema_version": 3,
          "count": 1,
          "exercises": [{
            "id": "fixture-goblet-squat",
            "name_en": "Fixture Goblet Squat",
            "description_en": "A controlled squat holding one kettlebell.",
            "category": "strength",
            "force_type": "push",
            "mechanic": "compound",
            "difficulty": "beginner",
            "equipment": "kettlebell",
            "body_part": "upper_legs",
            "primary_muscles": ["quadriceps", "gluteus_maximus"],
            "secondary_muscles": ["hamstrings"],
            "goals": ["strength"],
            "tags": ["squat"],
            "is_unilateral": false,
            "is_bodyweight": false,
            "instructions_en": ["Brace the trunk.", "Sit between the hips."],
            "tips_en": ["Keep the whole foot planted."],
            "images": {"flat": {
              "start": "images/flat/fixture-start.webp",
              "peak": "images/flat/fixture-peak.webp"
            }}
          }]
        }
        """.data(using: .utf8)!
    }
}
