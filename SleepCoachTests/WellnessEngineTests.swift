import XCTest
@testable import SleepCoach

final class WellnessEngineTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testEightSleepWinsOverLongerHumeSession() {
        let engine = WellnessEngine(calendar: calendar)
        let day = date(2026, 9, 3, 0, 0)
        let samples = [
            sleep(start: day.addingTimeInterval(22 * 3600), minutes: 420, source: "Eight Sleep", bundle: "com.eightsleep.app"),
            sleep(start: day.addingTimeInterval(21 * 3600), minutes: 540, source: "Hume", bundle: "com.fittrack.hume")
        ]

        let sessions = engine.reconstructSleepSessions(from: samples)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.sourceName, "Eight Sleep")
        XCTAssertEqual(sessions.first?.asleepMinutes ?? 0, 420, accuracy: 0.01)
    }

    func testOverlappingSleepStagesAreNotDoubleCounted() {
        let engine = WellnessEngine(calendar: calendar)
        let start = date(2026, 9, 3, 23, 0)
        let samples = [
            sleep(start: start, minutes: 480, source: "Eight Sleep", bundle: "com.eightsleep.app", stage: .asleep),
            sleep(start: start.addingTimeInterval(60 * 60), minutes: 90, source: "Eight Sleep", bundle: "com.eightsleep.app", stage: .deep),
            sleep(start: start.addingTimeInterval(5 * 3600), minutes: 100, source: "Eight Sleep", bundle: "com.eightsleep.app", stage: .rem)
        ]

        let session = engine.reconstructSleepSessions(from: samples).first

        XCTAssertEqual(session?.asleepMinutes ?? 0, 480, accuracy: 0.01)
        XCTAssertEqual(session?.deepMinutes ?? 0, 90, accuracy: 0.01)
        XCTAssertEqual(session?.remMinutes ?? 0, 100, accuracy: 0.01)
    }

    func testSevereSleepShortfallCapsReadinessAtLow() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 4, 9, 0)
        let sample = sleep(start: date(2026, 9, 4, 2, 0), minutes: 300, source: "Eight Sleep", bundle: "com.eightsleep.app")

        let snapshot = engine.snapshot(from: [sample], preferences: .default, now: now)

        XCTAssertEqual(snapshot.readinessBand, .low)
        XCTAssertLessThan(snapshot.readinessScore, 45)
    }

    func testNoDataDoesNotCreateTrainingReadiness() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 4, 9, 0)

        let snapshot = engine.snapshot(from: [], preferences: .default, now: now)
        let plan = engine.plan(snapshot: snapshot, commitment: nil, preferences: .default, now: now)

        XCTAssertFalse(snapshot.readinessAvailable)
        XCTAssertEqual(snapshot.readinessScore, 0)
        XCTAssertFalse(plan.workoutAdjustment.allowProgression)
        XCTAssertEqual(plan.workoutAdjustment.title, "No adjustment yet")
    }

    func testNapIsNotPromotedToOvernightSleep() {
        let engine = WellnessEngine(calendar: calendar)
        let nap = sleep(
            start: date(2026, 9, 4, 14, 0),
            minutes: 45,
            source: "Eight Sleep",
            bundle: "com.eightsleep.app"
        )

        XCTAssertTrue(engine.reconstructSleepSessions(from: [nap]).isEmpty)
    }

    func testFreshNonEightSleepWinsOverStaleEightSleep() {
        let engine = WellnessEngine(calendar: calendar)
        let samples = [
            sleep(start: date(2026, 8, 24, 23, 0), minutes: 450, source: "Eight Sleep", bundle: "com.eightsleep.app"),
            sleep(start: date(2026, 9, 3, 23, 0), minutes: 440, source: "Apple Watch", bundle: "com.apple.health.watch")
        ]

        let session = engine.reconstructSleepSessions(from: samples).first

        XCTAssertEqual(session?.sourceName, "Apple Watch")
    }

    func testOnePositiveNightDoesNotAllowProgression() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 4, 9, 0)
        let sample = sleep(start: date(2026, 9, 3, 23, 0), minutes: 480, source: "Eight Sleep", bundle: "com.eightsleep.app")

        let snapshot = engine.snapshot(from: [sample], preferences: .default, now: now)
        let plan = engine.plan(snapshot: snapshot, commitment: nil, preferences: .default, now: now)

        XCTAssertEqual(snapshot.confidence, .low)
        XCTAssertFalse(plan.workoutAdjustment.allowProgression)
        XCTAssertEqual(plan.workoutAdjustment.title, "Conservative baseline")
    }

    func testPlanWorksBackwardFromCommitment() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 4, 18, 0)
        let commitment = CalendarCommitment(
            id: "meeting",
            title: "First meeting",
            startDate: date(2026, 9, 5, 9, 0),
            endDate: date(2026, 9, 5, 10, 0),
            location: nil
        )
        var preferences = WellnessPreferences.default
        preferences.gymDurationMinutes = 60
        preferences.travelToGymMinutes = 15
        preferences.postWorkoutMinutes = 30
        preferences.commitmentBufferMinutes = 10

        let plan = engine.plan(snapshot: .empty, commitment: commitment, preferences: preferences, now: now)

        XCTAssertEqual(plan.gymEnd, date(2026, 9, 5, 8, 5))
        XCTAssertEqual(plan.gymStart, date(2026, 9, 5, 7, 5))
        XCTAssertEqual(plan.wakeTime, date(2026, 9, 5, 6, 45))
        XCTAssertEqual(plan.bedtime, date(2026, 9, 4, 22, 15))
    }

    func testSleepTrendKeepsCalendarGapsAndUsesOneSource() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 4, 9, 0)
        let samples = [
            sleep(start: date(2026, 9, 3, 23, 0), minutes: 480, source: "Eight Sleep", bundle: "com.eightsleep.app"),
            sleep(start: date(2026, 9, 1, 23, 0), minutes: 420, source: "Eight Sleep", bundle: "com.eightsleep.app"),
            sleep(start: date(2026, 9, 2, 22, 0), minutes: 600, source: "Apple Watch", bundle: "com.apple.health.watch")
        ]

        let trend = engine.snapshot(from: samples, preferences: .default, now: now).sleepTrend
        let recent = Array(trend.points.suffix(7))

        XCTAssertEqual(trend.points.count, 28)
        XCTAssertEqual(trend.sourceBundleIdentifier, "com.eightsleep.app")
        XCTAssertEqual(trend.sevenDaySummary.recordedDays, 2)
        XCTAssertEqual(trend.sevenDaySummary.expectedDays, 7)
        XCTAssertEqual(trend.sevenDaySummary.average ?? 0, 450, accuracy: 0.01)
        XCTAssertEqual(trend.sevenDaySummary.deltaFromReference ?? 0, -30, accuracy: 0.01)

        let missingDay = recent.first { calendar.isDate($0.date, inSameDayAs: date(2026, 9, 3, 0, 0)) }
        let earlierNight = recent.first { calendar.isDate($0.date, inSameDayAs: date(2026, 9, 2, 0, 0)) }
        let latestNight = recent.first { calendar.isDate($0.date, inSameDayAs: date(2026, 9, 4, 0, 0)) }
        XCTAssertNil(missingDay?.value)
        XCTAssertNotEqual(earlierNight?.segmentID, latestNight?.segmentID)
    }

    func testSleepTrendCallsAThirtyThreeMinuteShortfallNearTarget() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 4, 9, 0)
        let samples = [
            sleep(
                start: date(2026, 9, 3, 23, 0),
                minutes: 447,
                source: "Eight Sleep",
                bundle: "com.eightsleep.app"
            )
        ]

        let trend = engine.snapshot(from: samples, preferences: .default, now: now).sleepTrend

        XCTAssertEqual(trend.status, .nearTarget)
        XCTAssertEqual(trend.statusText, "33m below target")
    }

    func testSleepTrendThresholdsKeepStatusAndCopyConsistent() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 4, 9, 0)
        let cases: [(minutes: Double, status: MetricSignalStatus, text: String)] = [
            (468, .onTarget, "12m below target"),
            (467, .nearTarget, "13m below target"),
            (432, .nearTarget, "48m below target"),
            (431, .needsAttention, "49m below target")
        ]

        for item in cases {
            let trend = engine.snapshot(
                from: [sleep(
                    start: date(2026, 9, 3, 23, 0),
                    minutes: item.minutes,
                    source: "Eight Sleep",
                    bundle: "com.eightsleep.app"
                )],
                preferences: .default,
                now: now
            ).sleepTrend

            XCTAssertEqual(trend.status, item.status, "Unexpected status at \(item.minutes) minutes")
            XCTAssertEqual(trend.statusText, item.text, "Unexpected copy at \(item.minutes) minutes")
        }
    }

    func testHRVCurrentAndMedianStayOnSelectedSource() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 4, 9, 0)
        var samples: [MetricSample] = [
            metric(.heartRateVariability, value: 60, at: date(2026, 9, 4, 7, 0), source: "Hume", bundle: "com.fittrack.hume"),
            metric(.heartRateVariability, value: 500, at: date(2026, 9, 4, 8, 0), source: "Apple Watch", bundle: "com.apple.health.watch")
        ]
        for (offset, value) in [40.0, 50, 60, 70, 80, 90, 100].enumerated() {
            let sampleDate = calendar.date(
                byAdding: .day,
                value: -(offset + 1),
                to: date(2026, 9, 4, 7, 0)
            )!
            samples.append(metric(
                .heartRateVariability,
                value: value,
                at: sampleDate,
                source: "Hume",
                bundle: "com.fittrack.hume"
            ))
        }

        let snapshot = engine.snapshot(from: samples, preferences: .default, now: now)

        XCTAssertEqual(snapshot.hrvTrend.sourceBundleIdentifier, "com.fittrack.hume")
        XCTAssertEqual(snapshot.hrvTrend.currentValue ?? 0, 60, accuracy: 0.01)
        XCTAssertEqual(snapshot.hrvTrend.referenceValue ?? 0, 70, accuracy: 0.01)
        XCTAssertEqual(snapshot.baselineHRV ?? 0, 70, accuracy: 0.01)
        XCTAssertEqual(snapshot.hrvTrend.status, .nearTarget)
        XCTAssertEqual(snapshot.hrvTrend.points.last?.deviationPercentage ?? 0, -14.2857, accuracy: 0.001)
    }

    func testSleepTimingVariabilityIsPreprocessedFromSameSourceNights() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 4, 9, 0)
        let samples = [
            sleep(start: date(2026, 9, 3, 23, 0), minutes: 480, source: "Eight Sleep", bundle: "com.eightsleep.app"),
            sleep(start: date(2026, 9, 2, 23, 30), minutes: 450, source: "Eight Sleep", bundle: "com.eightsleep.app"),
            sleep(start: date(2026, 9, 2, 0, 0), minutes: 420, source: "Eight Sleep", bundle: "com.eightsleep.app")
        ]

        let variability = engine.snapshot(from: samples, preferences: .default, now: now).sleepTimingVariability

        XCTAssertEqual(variability.sourceBundleIdentifier, "com.eightsleep.app")
        XCTAssertEqual(variability.recordedNights, 3)
        XCTAssertEqual(variability.bedtimeMinutes ?? 0, 30, accuracy: 0.01)
        XCTAssertEqual(variability.wakeTimeMinutes ?? 0, 0, accuracy: 0.01)
    }

    func testLegacyPreferencesDecodeWithCurrentSignalDefaults() throws {
        let data = Data("""
        {
          "sleepNeedMinutes": 510,
          "gymDurationMinutes": 75,
          "travelToGymMinutes": 20,
          "postWorkoutMinutes": 25,
          "commitmentBufferMinutes": 15,
          "fallbackCommitmentHour": 8
        }
        """.utf8)

        let preferences = try JSONDecoder().decode(WellnessPreferences.self, from: data)

        XCTAssertEqual(preferences.sleepNeedMinutes, 510)
        XCTAssertEqual(preferences.signalOrder, MetricKind.decisionMetrics)
        XCTAssertEqual(preferences.decisionMetricPreferences.map(\.metric), MetricKind.decisionMetrics)
        XCTAssertTrue(preferences.decisionMetricPreferences.allSatisfy { $0.shownOnToday })
        XCTAssertTrue(preferences.decisionMetricPreferences.allSatisfy { $0.usedInRecommendation })
        XCTAssertTrue(preferences.decisionMetricPreferences.allSatisfy { $0.sourceMode == .automatic })
        XCTAssertTrue(preferences.decisionMetricPreferences.allSatisfy { $0.allowAutomaticFallback })
    }

    func testTodaySignalsRespectVisibilityAndOrder() {
        let engine = WellnessEngine(calendar: calendar)
        var preferences = WellnessPreferences.default
        preferences.signalOrder = [.restingHeartRate, .sleep, .heartRateVariability]
        updatePreference(.sleep, in: &preferences) { $0.shownOnToday = false }

        let snapshot = engine.snapshot(
            from: [],
            preferences: preferences,
            now: date(2026, 9, 4, 9, 0)
        )

        XCTAssertEqual(snapshot.signalTrends.map(\.kind), [.restingHeartRate, .heartRateVariability])
        XCTAssertEqual(snapshot.recoverySignals.map(\.kind), snapshot.signalTrends.map(\.kind))
    }

    func testSignalsExcludedFromRecommendationDoNotCreateReadiness() {
        let engine = WellnessEngine(calendar: calendar)
        var preferences = WellnessPreferences.default
        for metric in MetricKind.decisionMetrics {
            updatePreference(metric, in: &preferences) { $0.usedInRecommendation = false }
        }
        let sample = sleep(
            start: date(2026, 9, 3, 23, 0),
            minutes: 480,
            source: "Eight Sleep",
            bundle: "com.eightsleep.app"
        )

        let snapshot = engine.snapshot(
            from: [sample],
            preferences: preferences,
            now: date(2026, 9, 4, 9, 0)
        )

        XCTAssertFalse(snapshot.readinessAvailable)
        XCTAssertEqual(snapshot.readinessScore, 0)
        XCTAssertEqual(snapshot.confidence, .low)
        XCTAssertTrue(snapshot.reasons.isEmpty)
        XCTAssertEqual(snapshot.sleepTrend.currentValue, 480)
    }

    func testBiometricOnlyRecommendationDoesNotRequireSleepWhenSleepIsExcluded() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 4, 9, 0)
        var preferences = WellnessPreferences.default
        updatePreference(.sleep, in: &preferences) { $0.usedInRecommendation = false }
        updatePreference(.restingHeartRate, in: &preferences) { $0.usedInRecommendation = false }
        var samples = [
            metric(
                .heartRateVariability,
                value: 70,
                at: date(2026, 9, 4, 7, 0),
                source: "Hume",
                bundle: "com.fittrack.hume"
            )
        ]
        for offset in 1...7 {
            samples.append(metric(
                .heartRateVariability,
                value: 60,
                at: calendar.date(byAdding: .day, value: -offset, to: date(2026, 9, 4, 7, 0))!,
                source: "Hume",
                bundle: "com.fittrack.hume"
            ))
        }

        let snapshot = engine.snapshot(from: samples, preferences: preferences, now: now)

        XCTAssertTrue(snapshot.readinessAvailable)
        XCTAssertEqual(snapshot.confidence, .high)
        XCTAssertEqual(snapshot.readinessBand, .high)
        XCTAssertEqual(snapshot.reasons.map(\.title), ["HRV 70 ms"])
        XCTAssertEqual(snapshot.hrvTrend.baselineDayCount, 7)
    }

    func testManualMetricSourceUsesRequestedBundleAndExplainsSelection() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 4, 9, 0)
        let watchBundle = "com.apple.health.watch"
        var preferences = WellnessPreferences.default
        updatePreference(.heartRateVariability, in: &preferences) {
            $0.sourceMode = .manual
            $0.manualSourceBundleIdentifier = watchBundle
            $0.allowAutomaticFallback = false
        }
        let samples = [
            metric(.heartRateVariability, value: 60, at: date(2026, 9, 4, 7, 0), source: "Hume", bundle: "com.fittrack.hume"),
            metric(.heartRateVariability, value: 51, at: date(2026, 9, 4, 8, 0), source: "Apple Watch", bundle: watchBundle),
            metric(.heartRateVariability, value: 48, at: date(2026, 9, 3, 8, 0), source: "Apple Watch", bundle: watchBundle)
        ]

        let trend = engine.snapshot(from: samples, preferences: preferences, now: now).hrvTrend

        XCTAssertEqual(trend.sourceBundleIdentifier, watchBundle)
        XCTAssertEqual(trend.currentValue, 51)
        XCTAssertEqual(trend.sourceHealth.state, .manual)
        XCTAssertEqual(trend.sourceHealth.requestedBundleIdentifier, watchBundle)
        XCTAssertFalse(trend.sourceHealth.usedAutomaticFallback)
        XCTAssertTrue(trend.sourceHealth.reason.contains("Apple Watch"))
        XCTAssertEqual(trend.baselineDayCount, 1)
    }

    func testStaleManualMetricSourceFallsBackWhenAllowed() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 4, 9, 0)
        let humeBundle = "com.fittrack.hume"
        let watchBundle = "com.apple.health.watch"
        var preferences = WellnessPreferences.default
        updatePreference(.heartRateVariability, in: &preferences) {
            $0.sourceMode = .manual
            $0.manualSourceBundleIdentifier = humeBundle
            $0.allowAutomaticFallback = true
        }
        let samples = [
            metric(.heartRateVariability, value: 60, at: date(2026, 8, 30, 7, 0), source: "Hume", bundle: humeBundle),
            metric(.heartRateVariability, value: 52, at: date(2026, 9, 4, 8, 0), source: "Apple Watch", bundle: watchBundle)
        ]

        let trend = engine.snapshot(from: samples, preferences: preferences, now: now).hrvTrend

        XCTAssertEqual(trend.sourceBundleIdentifier, watchBundle)
        XCTAssertEqual(trend.sourceHealth.state, .fallback)
        XCTAssertTrue(trend.sourceHealth.usedAutomaticFallback)
        XCTAssertTrue(trend.sourceHealth.reason.contains("automatic fallback is on"))
    }

    func testMissingManualSleepSourceWithoutFallbackIsUnavailable() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 4, 9, 0)
        let requestedBundle = "com.example.missing-sleep"
        var preferences = WellnessPreferences.default
        updatePreference(.sleep, in: &preferences) {
            $0.sourceMode = .manual
            $0.manualSourceBundleIdentifier = requestedBundle
            $0.allowAutomaticFallback = false
        }
        let samples = [
            sleep(
                start: date(2026, 9, 3, 23, 0),
                minutes: 480,
                source: "Eight Sleep",
                bundle: "com.eightsleep.app"
            )
        ]

        let snapshot = engine.snapshot(from: samples, preferences: preferences, now: now)

        XCTAssertNil(snapshot.sleepTrend.sourceBundleIdentifier)
        XCTAssertEqual(snapshot.sleepTrend.sourceHealth.state, .unavailable)
        XCTAssertEqual(snapshot.sleepTrend.sourceHealth.requestedBundleIdentifier, requestedBundle)
        XCTAssertFalse(snapshot.readinessAvailable)
        XCTAssertTrue(snapshot.sleepTrend.sourceHealth.reason.contains(requestedBundle))
    }

    func testAppleWatchDiagnosticIsNotCollapsedIntoGenericAppleHealth() {
        let diagnostic = SourceDiagnostic(
            sourceName: "Apple Watch",
            bundleIdentifier: "com.apple.health",
            kind: .heartRateVariability,
            sampleCount: 1,
            latestSample: .now
        )

        XCTAssertEqual(diagnostic.vendorLabel, "Apple Watch")
    }

    private func sleep(
        start: Date,
        minutes: Double,
        source: String,
        bundle: String,
        stage: SleepStage = .asleep
    ) -> MetricSample {
        MetricSample(
            kind: .sleep,
            startDate: start,
            endDate: start.addingTimeInterval(minutes * 60),
            sleepStage: stage,
            sourceName: source,
            sourceBundleIdentifier: bundle
        )
    }

    private func metric(
        _ kind: MetricKind,
        value: Double,
        at date: Date,
        source: String,
        bundle: String
    ) -> MetricSample {
        MetricSample(
            kind: kind,
            startDate: date,
            endDate: date,
            value: value,
            sourceName: source,
            sourceBundleIdentifier: bundle
        )
    }

    private func updatePreference(
        _ metric: MetricKind,
        in preferences: inout WellnessPreferences,
        update: (inout DecisionMetricPreference) -> Void
    ) {
        guard let index = preferences.decisionMetricPreferences.firstIndex(where: { $0.metric == metric }) else {
            XCTFail("Missing preference for \(metric)")
            return
        }
        update(&preferences.decisionMetricPreferences[index])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
