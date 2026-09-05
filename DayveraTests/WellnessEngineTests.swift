import XCTest
@testable import Dayvera

final class WellnessEngineTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testLatestSourceWinsWhenCoverageTiesBeforeVendorPreference() {
        let engine = WellnessEngine(calendar: calendar)
        let day = date(2026, 9, 3, 0, 0)
        let samples = [
            sleep(start: day.addingTimeInterval(22 * 3600), minutes: 420, source: "Eight Sleep", bundle: "com.eightsleep.app"),
            sleep(start: day.addingTimeInterval(21 * 3600), minutes: 540, source: "Hume", bundle: "com.fittrack.hume")
        ]

        let sessions = engine.reconstructSleepSessions(from: samples)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.sourceName, "Hume")
        XCTAssertEqual(sessions.first?.asleepMinutes ?? 0, 540, accuracy: 0.01)
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

    func testAutomaticSourceUsesObservedDayCoverageBeforeVendorTieBreak() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 22, 9, 0)
        var samples = [
            metric(
                .heartRateVariability,
                value: 90,
                at: date(2026, 9, 22, 8, 0),
                source: "Hume",
                bundle: "com.fittrack.hume"
            ),
            metric(
                .heartRateVariability,
                value: 55,
                at: date(2026, 9, 22, 7, 0),
                source: "Apple Watch",
                bundle: "com.apple.health",
                productType: "Watch7,5"
            )
        ]
        for offset in 1...14 {
            samples.append(metric(
                .heartRateVariability,
                value: 50,
                at: calendar.date(byAdding: .day, value: -offset, to: date(2026, 9, 22, 7, 0))!,
                source: "Apple Watch",
                bundle: "com.apple.health",
                productType: "Watch7,5"
            ))
        }

        let snapshot = engine.snapshot(from: samples, preferences: .default, now: now)

        XCTAssertEqual(snapshot.hrvTrend.sourceBundleIdentifier, "com.apple.health")
        XCTAssertEqual(snapshot.latestHRV, 55)
        XCTAssertTrue(snapshot.hrvTrend.sourceHealth.reason.contains("15 observed days"))
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

    func testOneFreshSafetyOutlierPausesProgressionWithoutChangingCoreReadiness() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 22, 9, 0)
        var samples = safetyBaselineSamples(now: now, kinds: [.respiratoryRate])
        samples.append(metric(
            .respiratoryRate,
            value: 17,
            at: date(2026, 9, 22, 7, 0),
            source: "Apple Watch",
            bundle: "com.apple.health"
        ))

        let snapshot = engine.snapshot(from: samples, preferences: .default, now: now)
        let plan = engine.plan(snapshot: snapshot, commitment: nil, preferences: .default, now: now)

        XCTAssertEqual(snapshot.safetyGate.freshOutlierCount, 1)
        XCTAssertEqual(snapshot.coreReadinessScore, 100)
        XCTAssertEqual(snapshot.readinessScore, snapshot.coreReadinessScore)
        XCTAssertEqual(snapshot.readinessBand, .high)
        XCTAssertEqual(plan.workoutAdjustment.volumeMultiplier, 1, accuracy: 0.001)
        XCTAssertFalse(plan.workoutAdjustment.allowProgression)
        XCTAssertTrue(plan.workoutAdjustment.detail.contains("Core readiness"))
    }

    func testTwoFreshSafetyOutliersCapReadinessAndReducePreGateVolumeTenPercent() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 22, 9, 0)
        var samples = safetyBaselineSamples(
            now: now,
            kinds: [.respiratoryRate, .oxygenSaturation]
        )
        samples.append(contentsOf: [
            metric(
                .respiratoryRate,
                value: 17,
                at: date(2026, 9, 22, 7, 0),
                source: "Apple Watch",
                bundle: "com.apple.health"
            ),
            metric(
                .oxygenSaturation,
                value: 94,
                at: date(2026, 9, 22, 7, 0),
                source: "Apple Watch",
                bundle: "com.apple.health"
            )
        ])

        let snapshot = engine.snapshot(from: samples, preferences: .default, now: now)
        let plan = engine.plan(snapshot: snapshot, commitment: nil, preferences: .default, now: now)

        XCTAssertEqual(snapshot.safetyGate.freshOutlierCount, 2)
        XCTAssertEqual(snapshot.coreReadinessScore, 100)
        XCTAssertEqual(snapshot.coreReadinessBand, .high)
        XCTAssertEqual(snapshot.readinessScore, 69)
        XCTAssertEqual(snapshot.readinessBand, .moderate)
        XCTAssertEqual(plan.readiness, .moderate)
        XCTAssertEqual(plan.workoutAdjustment.volumeMultiplier, 0.9, accuracy: 0.001)
        XCTAssertFalse(plan.workoutAdjustment.allowProgression)
        XCTAssertTrue(plan.workoutAdjustment.detail.contains("reduced by 10%"))
    }

    func testSafetySignalWithFewerThanFourteenBaselineNightsIsNeutral() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 22, 9, 0)
        var samples = safetyBaselineSamples(
            now: now,
            kinds: [.bodyTemperature],
            baselineNightCount: 13
        )
        samples.append(metric(
            .bodyTemperature,
            value: 39,
            at: date(2026, 9, 22, 7, 0),
            source: "Thermometer",
            bundle: "com.example.thermometer"
        ))

        let snapshot = engine.snapshot(from: samples, preferences: .default, now: now)
        let signal = snapshot.safetyGate.signals.first { $0.kind == .bodyTemperature }

        XCTAssertEqual(signal?.state, .buildingBaseline)
        XCTAssertEqual(signal?.baselineNightCount, 13)
        XCTAssertEqual(snapshot.safetyGate.freshOutlierCount, 0)
    }

    func testStaleSafetyOutlierIsNeutral() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 22, 9, 0)
        var samples: [MetricSample] = []
        for offset in 5...19 {
            let wake = calendar.date(byAdding: .day, value: -offset, to: date(2026, 9, 22, 7, 0))!
            samples.append(sleep(
                start: wake.addingTimeInterval(-480 * 60),
                minutes: 480,
                source: "Eight Sleep",
                bundle: "com.eightsleep.app"
            ))
            samples.append(metric(
                .respiratoryRate,
                value: offset == 5 ? 18 : 15,
                at: wake,
                source: "Apple Watch",
                bundle: "com.apple.health"
            ))
        }

        let snapshot = engine.snapshot(from: samples, preferences: .default, now: now)
        let signal = snapshot.safetyGate.signals.first { $0.kind == .respiratoryRate }

        XCTAssertEqual(signal?.state, .stale)
        XCTAssertEqual(snapshot.safetyGate.freshOutlierCount, 0)
    }

    func testOvernightHeartRateUsesThreeBeatFloorWhenMADIsZero() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 22, 9, 0)
        var samples = safetyBaselineSamples(now: now, kinds: [.heartRate])
        samples.append(metric(
            .heartRate,
            value: 54,
            at: date(2026, 9, 22, 7, 0),
            source: "Apple Watch",
            bundle: "com.apple.health"
        ))

        let signal = engine.snapshot(from: samples, preferences: .default, now: now)
            .safetyGate.signals.first { $0.kind == .heartRate }

        XCTAssertEqual(signal?.outlierThreshold, 3)
        XCTAssertEqual(signal?.state, .withinRange)
    }

    func testUserEnteredSamplesStayVisibleButDoNotDriveCoreOrSafetyGuidance() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 22, 9, 0)
        let manualSleep = MetricSample(
            kind: .sleep,
            startDate: date(2026, 9, 21, 23, 0),
            endDate: date(2026, 9, 22, 7, 0),
            sleepStage: .asleep,
            sourceName: "Health",
            sourceBundleIdentifier: "com.apple.health",
            wasUserEntered: true
        )
        var samples = safetyBaselineSamples(now: now, kinds: [.bodyTemperature])
            .filter { $0.kind != .sleep }
        samples.append(contentsOf: [
            manualSleep,
            MetricSample(
                kind: .bodyTemperature,
                startDate: date(2026, 9, 22, 7, 0),
                endDate: date(2026, 9, 22, 7, 0),
                value: 40,
                sourceName: "Thermometer",
                sourceBundleIdentifier: "com.example.thermometer",
                wasUserEntered: true
            )
        ])

        let snapshot = engine.snapshot(from: samples, preferences: .default, now: now)
        let temperature = snapshot.safetyGate.signals.first { $0.kind == .bodyTemperature }

        XCTAssertTrue(snapshot.samples.contains(where: \.wasUserEntered))
        XCTAssertFalse(snapshot.readinessAvailable)
        XCTAssertNotEqual(temperature?.state, .outlier)
        XCTAssertEqual(snapshot.safetyGate.freshOutlierCount, 0)
    }

    func testCoreBiometricsUseNightlyMedianRatherThanMean() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 22, 9, 0)
        var preferences = WellnessPreferences.default
        updatePreference(.sleep, in: &preferences) { $0.usedInRecommendation = false }
        updatePreference(.restingHeartRate, in: &preferences) { $0.usedInRecommendation = false }
        var samples = [40.0, 60, 200].map { value in
            metric(
                .heartRateVariability,
                value: value,
                at: date(2026, 9, 22, 7, Int(value) % 10),
                source: "Hume",
                bundle: "com.fittrack.hume"
            )
        }
        for offset in 1...14 {
            samples.append(metric(
                .heartRateVariability,
                value: 50,
                at: calendar.date(byAdding: .day, value: -offset, to: date(2026, 9, 22, 7, 0))!,
                source: "Hume",
                bundle: "com.fittrack.hume"
            ))
        }

        let snapshot = engine.snapshot(from: samples, preferences: preferences, now: now)

        XCTAssertEqual(snapshot.latestHRV, 60)
        XCTAssertEqual(snapshot.baselineHRV, 50)
    }

    func testTrainingContextUsesObservedActivityAndWorkoutSamples() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 22, 9, 0)
        let yesterday = date(2026, 9, 21, 12, 0)
        let samples = [
            metric(.activeEnergy, value: 100, at: yesterday, source: "Apple Watch", bundle: "com.apple.health"),
            metric(.activeEnergy, value: 200, at: yesterday.addingTimeInterval(3600), source: "Apple Watch", bundle: "com.apple.health"),
            metric(.activeEnergy, value: 1_000, at: yesterday, source: "Phone", bundle: "com.example.phone"),
            metric(.exerciseMinutes, value: 35, at: yesterday, source: "Apple Watch", bundle: "com.apple.health"),
            metric(.steps, value: 6_200, at: yesterday, source: "Apple Watch", bundle: "com.apple.health"),
            metric(.workout, value: 45, at: yesterday, source: "Apple Watch", bundle: "com.apple.health"),
            metric(.workout, value: 30, at: date(2026, 9, 18, 12, 0), source: "Dayvera", bundle: "com.dayvera")
        ]

        let context = engine.snapshot(from: samples, preferences: .default, now: now).trainingContext

        XCTAssertEqual(context.previousDayActiveEnergy, 300)
        XCTAssertEqual(context.previousDayExerciseMinutes, 35)
        XCTAssertEqual(context.previousDaySteps, 6_200)
        XCTAssertEqual(context.workoutsLastSevenDays, 2)
        XCTAssertEqual(context.workoutMinutesLastSevenDays, 75)
    }

    func testTrainingContextDeduplicatesWorkoutSyncRevisions() {
        let engine = WellnessEngine(calendar: calendar)
        let now = date(2026, 9, 22, 9, 0)
        let workoutDate = date(2026, 9, 21, 12, 0)
        let samples = [
            MetricSample(
                kind: .workout,
                startDate: workoutDate,
                endDate: workoutDate.addingTimeInterval(30 * 60),
                value: 30,
                sourceName: "Dayvera",
                sourceBundleIdentifier: "com.dayvera",
                workoutSyncIdentifier: "session-1",
                workoutSyncVersion: 1
            ),
            MetricSample(
                kind: .workout,
                startDate: workoutDate,
                endDate: workoutDate.addingTimeInterval(40 * 60),
                value: 40,
                sourceName: "Dayvera",
                sourceBundleIdentifier: "com.dayvera",
                workoutSyncIdentifier: "session-1",
                workoutSyncVersion: 2
            ),
            MetricSample(
                kind: .workout,
                startDate: workoutDate,
                endDate: workoutDate.addingTimeInterval(90 * 60),
                value: 90,
                sourceName: "Health",
                sourceBundleIdentifier: "com.apple.health",
                wasUserEntered: true
            )
        ]

        let context = engine.snapshot(from: samples, preferences: .default, now: now).trainingContext

        XCTAssertEqual(context.workoutsLastSevenDays, 1)
        XCTAssertEqual(context.workoutMinutesLastSevenDays, 40)
        XCTAssertEqual(context.latestWorkoutDate, workoutDate.addingTimeInterval(40 * 60))
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
        bundle: String,
        productType: String? = nil
    ) -> MetricSample {
        MetricSample(
            kind: kind,
            startDate: date,
            endDate: date,
            value: value,
            sourceName: source,
            sourceBundleIdentifier: bundle,
            sourceProductType: productType
        )
    }

    private func safetyBaselineSamples(
        now: Date,
        kinds: [MetricKind],
        baselineNightCount: Int = 14
    ) -> [MetricSample] {
        var samples: [MetricSample] = []
        let currentWake = calendar.date(
            bySettingHour: 7,
            minute: 0,
            second: 0,
            of: now
        )!
        for offset in 0...baselineNightCount {
            let wake = calendar.date(byAdding: .day, value: -offset, to: currentWake)!
            samples.append(sleep(
                start: wake.addingTimeInterval(-480 * 60),
                minutes: 480,
                source: "Eight Sleep",
                bundle: "com.eightsleep.app"
            ))
            guard offset > 0 else { continue }
            for kind in kinds {
                let value: Double = switch kind {
                case .respiratoryRate: 15
                case .oxygenSaturation: 97
                case .sleepingWristTemperature: 36
                case .bodyTemperature: 36.8
                case .heartRate: 52
                default: 0
                }
                samples.append(metric(
                    kind,
                    value: value,
                    at: wake,
                    source: kind == .bodyTemperature ? "Thermometer" : "Apple Watch",
                    bundle: kind == .bodyTemperature ? "com.example.thermometer" : "com.apple.health"
                ))
            }
        }
        return samples
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
