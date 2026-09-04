#if DEBUG
import Foundation
import SwiftData

final class DemoHealthService: HealthDataProviding {
    var isAvailable: Bool { true }

    func requestAuthorization() async throws {}

    func fetchSamples(since startDate: Date, through endDate: Date) async throws -> HealthSampleFetchResult {
        let simulatePartialFailure = ProcessInfo.processInfo.arguments.contains("--demo-health-partial")
        let samples = Self.samples(now: endDate)
            .filter { $0.endDate >= startDate && $0.startDate <= endDate }
            .filter { !simulatePartialFailure || $0.kind != .heartRateVariability }
        return HealthSampleFetchResult(
            samples: samples,
            queryFailures: simulatePartialFailure
                ? [HealthQueryFailure(
                    kind: .heartRateVariability,
                    typeIdentifier: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
                    message: "Simulator fixture: HRV query failed."
                )]
                : []
        )
    }

    func saveStrengthWorkout(
        sessionID: UUID,
        syncVersion: Int,
        start: Date,
        end: Date
    ) async throws {}
    @MainActor
    func configureBackgroundDelivery(
        onUpdate: @escaping @MainActor @Sendable (HealthBackgroundEvent) async -> Void
    ) async throws {}

    private static func samples(now: Date) -> [MetricSample] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var samples: [MetricSample] = []

        for offset in 0..<14 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let wake = calendar.date(bySettingHour: 6, minute: 35 + (offset % 3) * 5, second: 0, of: day)!
            let sleepMinutes = Double(455 - (offset % 4) * 8)
            let start = wake.addingTimeInterval(-sleepMinutes * 60)
            samples.append(.init(
                kind: .sleep,
                startDate: start.addingTimeInterval(-22 * 60),
                endDate: wake.addingTimeInterval(8 * 60),
                sleepStage: .inBed,
                sourceName: "Eight Sleep",
                sourceBundleIdentifier: "com.eightsleep.sleep"
            ))
            samples.append(.init(
                kind: .sleep,
                startDate: start,
                endDate: wake,
                sleepStage: .asleep,
                sourceName: "Eight Sleep",
                sourceBundleIdentifier: "com.eightsleep.sleep"
            ))
            samples.append(.init(
                kind: .sleep,
                startDate: start.addingTimeInterval(70 * 60),
                endDate: start.addingTimeInterval(155 * 60),
                sleepStage: .deep,
                sourceName: "Eight Sleep",
                sourceBundleIdentifier: "com.eightsleep.sleep"
            ))
            samples.append(.init(
                kind: .sleep,
                startDate: wake.addingTimeInterval(-105 * 60),
                endDate: wake.addingTimeInterval(-20 * 60),
                sleepStage: .rem,
                sourceName: "Eight Sleep",
                sourceBundleIdentifier: "com.eightsleep.sleep"
            ))

            samples.append(.init(
                kind: .heartRateVariability,
                startDate: wake,
                endDate: wake,
                value: 58 + Double((offset % 5) - 2),
                sourceName: "Hume Health",
                sourceBundleIdentifier: "com.fittrack.hume"
            ))
            samples.append(.init(
                kind: .restingHeartRate,
                startDate: wake,
                endDate: wake,
                value: 52 + Double(offset % 3),
                sourceName: "Hume Health",
                sourceBundleIdentifier: "com.fittrack.hume"
            ))

            // A second observed source makes the simulator useful for verifying
            // manual selection, automatic preference, and source attribution.
            if offset < 10 {
                let watchWake = wake.addingTimeInterval(5 * 60)
                samples.append(.init(
                    kind: .sleep,
                    startDate: watchWake.addingTimeInterval(-440 * 60),
                    endDate: watchWake,
                    sleepStage: .asleep,
                    sourceName: "Apple Watch",
                    sourceBundleIdentifier: "com.apple.health"
                ))
                samples.append(.init(
                    kind: .heartRateVariability,
                    startDate: watchWake,
                    endDate: watchWake,
                    value: 55 + Double(offset % 4),
                    sourceName: "Apple Watch",
                    sourceBundleIdentifier: "com.apple.health"
                ))
                samples.append(.init(
                    kind: .restingHeartRate,
                    startDate: watchWake,
                    endDate: watchWake,
                    value: 54 + Double(offset % 2),
                    sourceName: "Apple Watch",
                    sourceBundleIdentifier: "com.apple.health"
                ))
            }
        }

        return samples
    }
}

final class DemoCalendarService: CalendarProviding {
    var authorizationLabel: String { "Connected" }

    func requestAccess() async throws -> Bool { true }

    func firstCommitment(on date: Date) async throws -> CalendarCommitment? {
        let start = Calendar.current.date(bySettingHour: 9, minute: 15, second: 0, of: date)!
        return CalendarCommitment(
            id: "demo-commitment",
            title: "Team planning",
            startDate: start,
            endDate: start.addingTimeInterval(45 * 60),
            location: "Office"
        )
    }

    func createGymEvent(start: Date, end: Date, note: String) async throws {}
    func hasGymEvent(start: Date, end: Date) throws -> Bool { true }
}

final class DemoAlarmService: AlarmScheduling {
    var authorizationLabel: String { "Demo ready" }
    func scheduleWakeAlarm(at date: Date) async throws {}
    func hasWakeAlarm(scheduledAt date: Date) throws -> Bool { true }
    func cancelWakeAlarm() throws {}
}

enum DemoDataSeeder {
    @MainActor
    static func seedWorkouts(in context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<WorkoutTemplateRecord>()) == 0 else { return }

        let squat = WorkoutExercise(
            name: "Back Squat",
            muscleGroup: .quads,
            workingSets: 4,
            targetReps: 6,
            targetWeight: 225,
            targetRPE: 8,
            restSeconds: 150
        )
        let deadlift = WorkoutExercise(
            name: "Romanian Deadlift",
            muscleGroup: .hamstrings,
            workingSets: 3,
            targetReps: 8,
            targetWeight: 185,
            targetRPE: 8,
            restSeconds: 120
        )
        let lunge = WorkoutExercise(
            name: "Walking Lunge",
            muscleGroup: .glutes,
            workingSets: 3,
            targetReps: 10,
            targetWeight: 45,
            targetRPE: 7.5,
            restSeconds: 90
        )
        let template = WorkoutTemplateRecord(name: "Lower Strength", exercises: [squat, deadlift, lunge])
        context.insert(template)

        for dayOffset in [2, 6, 10] {
            let start = Calendar.current.date(byAdding: .day, value: -dayOffset, to: .now)!
            let sets = [
                CompletedSet(exerciseID: squat.id, exerciseName: squat.name, setNumber: 1, weight: 215 + Double(dayOffset), reps: 6, rpe: 8, isWarmup: false, completedAt: start),
                CompletedSet(exerciseID: squat.id, exerciseName: squat.name, setNumber: 2, weight: 215 + Double(dayOffset), reps: 6, rpe: 8.5, isWarmup: false, completedAt: start),
                CompletedSet(exerciseID: deadlift.id, exerciseName: deadlift.name, setNumber: 1, weight: 175, reps: 8, rpe: 8, isWarmup: false, completedAt: start)
            ]
            context.insert(WorkoutSessionRecord(
                templateID: template.id,
                templateName: template.name,
                startedAt: start,
                endedAt: start.addingTimeInterval(58 * 60),
                readiness: dayOffset == 6 ? .moderate : .high,
                readinessScore: dayOffset == 6 ? 64 : 82,
                sets: sets,
                notes: "Simulator design-review data",
                healthExportState: .exported
            ))
        }
        try context.save()
    }
}
#endif
