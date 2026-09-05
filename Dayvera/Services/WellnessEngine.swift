import Foundation

protocol WellnessEvaluating: Sendable {
    func snapshot(from samples: [MetricSample], preferences: WellnessPreferences, now: Date) -> DailyHealthSnapshot
    func plan(snapshot: DailyHealthSnapshot, commitment: CalendarCommitment?, preferences: WellnessPreferences, now: Date) -> DailyPlan
}

private struct DailyValue: Sendable {
    let date: Date
    let value: Double
}

private struct SelectedDailySeries: Sendable {
    let sourceName: String?
    let sourceBundleIdentifier: String?
    let sourceHealth: MetricSourceHealth
    let values: [DailyValue]
}

private struct SelectedSourceSamples: Sendable {
    let samples: [MetricSample]
    let sourceName: String?
    let sourceBundleIdentifier: String?
    let sourceHealth: MetricSourceHealth
}

struct WellnessEngine: WellnessEvaluating {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func snapshot(from samples: [MetricSample], preferences: WellnessPreferences, now: Date = .now) -> DailyHealthSnapshot {
        let sleepPreference = preferences.decisionPreference(for: .sleep)
        let hrvPreference = preferences.decisionPreference(for: .heartRateVariability)
        let restingHeartRatePreference = preferences.decisionPreference(for: .restingHeartRate)
        let selectedSleep = selectedSourceSamples(
            kind: .sleep,
            samples: samples,
            preference: sleepPreference,
            preferredVendor: "eight",
            now: now
        )
        let sessions = reconstructSleepSessions(fromSelectedSamples: selectedSleep.samples)
        let latestSleep = sessions.filter {
            $0.endDate <= now.addingTimeInterval(4 * 3600)
                && $0.endDate >= now.addingTimeInterval(-36 * 3600)
        }.max { $0.endDate < $1.endDate }
        let recentSessions = Array(sessions.sorted { $0.endDate > $1.endDate }.prefix(14))
        let sleepDebt = calculateSleepDebt(sessions: recentSessions, needMinutes: preferences.sleepNeedMinutes)

        let hrvValues = selectedDailyValues(
            kind: .heartRateVariability,
            samples: samples,
            preference: hrvPreference,
            preferredVendor: "hume",
            now: now
        )
        let rhrValues = selectedDailyValues(
            kind: .restingHeartRate,
            samples: samples,
            preference: restingHeartRatePreference,
            preferredVendor: "hume",
            now: now
        )
        let baselineHRVValues = baselineValues(for: hrvValues.values, currentDate: hrvValues.values.first?.date)
        let baselineRHRValues = baselineValues(for: rhrValues.values, currentDate: rhrValues.values.first?.date)
        let baselineHRV = median(baselineHRVValues)
        let baselineRHR = median(baselineRHRValues)
        let latestHRV = recentValue(from: hrvValues.values, now: now)
        let latestRHR = recentValue(from: rhrValues.values, now: now)
        let trainingContext = trainingContext(from: samples, now: now)
        let previousEnergy = trainingContext.previousDayActiveEnergy
        let safetyGate = safetyGate(from: samples, sleepSessions: sessions, now: now)

        let sleepDailyValues = sessions
            .filter { $0.endDate <= now }
            .map { DailyValue(date: calendar.startOfDay(for: $0.endDate), value: $0.asleepMinutes) }
        let sleepTrend = makeSleepTrend(
            values: sleepDailyValues,
            sourceName: sessions.first?.sourceName,
            sourceBundleIdentifier: sessions.first?.sourceBundleIdentifier,
            sourceHealth: selectedSleep.sourceHealth,
            targetMinutes: preferences.sleepNeedMinutes,
            now: now
        )
        let hrvTrend = makeBiometricTrend(
            kind: .heartRateVariability,
            series: hrvValues,
            referenceValue: baselineHRV,
            baselineCount: baselineHRVValues.count,
            higherIsBetter: true,
            now: now
        )
        let restingHeartRateTrend = makeBiometricTrend(
            kind: .restingHeartRate,
            series: rhrValues,
            referenceValue: baselineRHR,
            baselineCount: baselineRHRValues.count,
            higherIsBetter: false,
            now: now
        )
        let timingVariability = sleepTimingVariability(sessions: sessions)

        var components: [(score: Double, weight: Double)] = []
        var reasons: [RecommendationReason] = []

        if sleepPreference.usedInRecommendation, let latestSleep {
            let sufficiency = latestSleep.asleepMinutes / preferences.sleepNeedMinutes
            components.append((min(max(sufficiency * 100, 0), 100), 0.45))
            reasons.append(.init(
                title: "Sleep \(Int(latestSleep.asleepMinutes / 60))h \(Int(latestSleep.asleepMinutes.truncatingRemainder(dividingBy: 60)))m",
                detail: "\(Int(sufficiency * 100))% of your \(Int(preferences.sleepNeedMinutes / 60))-hour target from \(latestSleep.sourceName).",
                isPositive: sufficiency >= 0.9
            ))
        }

        if hrvPreference.usedInRecommendation,
           let latestHRV,
           let baselineHRV,
           baselineHRV > 0 {
            let relative = latestHRV / baselineHRV
            components.append((clamp(50 + (relative - 1) * 125), 0.25))
            reasons.append(.init(
                title: "HRV \(Int(latestHRV)) ms",
                detail: relative >= 1 ? "At or above your recent same-source baseline." : "Below your recent same-source baseline of \(Int(baselineHRV)) ms.",
                isPositive: relative >= 0.95
            ))
        }

        if restingHeartRatePreference.usedInRecommendation,
           let latestRHR,
           let baselineRHR,
           baselineRHR > 0 {
            let relative = latestRHR / baselineRHR
            components.append((clamp(50 - (relative - 1) * 250), 0.2))
            reasons.append(.init(
                title: "Resting HR \(Int(latestRHR)) bpm",
                detail: relative <= 1 ? "At or below your recent same-source baseline." : "Above your recent same-source baseline of \(Int(baselineRHR)) bpm.",
                isPositive: relative <= 1.05
            ))
        }

        let consistency = sleepConsistency(sessions: Array(recentSessions.prefix(7)))
        if sleepPreference.usedInRecommendation, recentSessions.count >= 2 {
            components.append((consistency, 0.1))
            reasons.append(.init(
                title: "Sleep consistency \(Int(consistency))%",
                detail: "Based on the timing of your last \(recentSessions.count) recorded nights.",
                isPositive: consistency >= 70
            ))
        }

        let availableWeight = components.reduce(0) { $0 + $1.weight }
        let configuredWeight = (sleepPreference.usedInRecommendation ? 0.55 : 0)
            + (hrvPreference.usedInRecommendation ? 0.25 : 0)
            + (restingHeartRatePreference.usedInRecommendation ? 0.2 : 0)
        let coverage = configuredWeight > 0 ? availableWeight / configuredWeight : 0
        var score = availableWeight > 0
            ? components.reduce(0) { $0 + $1.score * $1.weight } / availableWeight
            : 0

        if sleepPreference.usedInRecommendation, let latestSleep {
            let sufficiency = latestSleep.asleepMinutes / preferences.sleepNeedMinutes
            if sufficiency < 0.75 { score = min(score, 39) }
            else if sufficiency < 0.9 { score = min(score, 69) }
        }

        let coreRoundedScore = Int(clamp(score).rounded())
        let coreBand: ReadinessBand = coreRoundedScore >= 70 ? .high : (coreRoundedScore >= 45 ? .moderate : .low)
        let roundedScore = safetyGate.capsReadinessAtModerate && coreBand == .high
            ? min(coreRoundedScore, 69)
            : coreRoundedScore
        let band: ReadinessBand = safetyGate.capsReadinessAtModerate && coreBand == .high
            ? .moderate
            : coreBand
        let biometricHistoryCounts = [
            hrvPreference.usedInRecommendation ? baselineHRVValues.count : nil,
            restingHeartRatePreference.usedInRecommendation ? baselineRHRValues.count : nil
        ].compactMap { $0 }
        let highHistoryReady = sleepPreference.usedInRecommendation
            ? recentSessions.count >= 7
            : (!biometricHistoryCounts.isEmpty && biometricHistoryCounts.allSatisfy { $0 >= 7 })
        let mediumHistoryReady = sleepPreference.usedInRecommendation
            ? recentSessions.count >= 3
            : (!biometricHistoryCounts.isEmpty && biometricHistoryCounts.allSatisfy { $0 >= 3 })
        let confidence: DataConfidence = coverage >= 0.8 && highHistoryReady
            ? .high
            : (coverage >= 0.45 && mediumHistoryReady ? .medium : .low)

        let biometricRecommendationAvailable =
            (hrvPreference.usedInRecommendation && latestHRV != nil && baselineHRV != nil)
            || (restingHeartRatePreference.usedInRecommendation && latestRHR != nil && baselineRHR != nil)
        let readinessAvailable = sleepPreference.usedInRecommendation
            ? latestSleep != nil
            : biometricRecommendationAvailable

        if sleepPreference.usedInRecommendation, latestSleep == nil {
            reasons.append(.init(
                title: "No recent overnight sleep",
                detail: "A recent overnight sleep session is required before Dayvera adjusts training.",
                isPositive: false
            ))
        }

        if safetyGate.blocksProgression {
            let names = safetyGate.freshOutliers.map { $0.kind.title }.joined(separator: ", ")
            reasons.append(.init(
                title: safetyGate.capsReadinessAtModerate
                    ? "Multiple overnight signals outside range"
                    : "Overnight signal outside range",
                detail: "\(names) differed from your 21-day same-source range. This safety check can only make today’s training more conservative.",
                isPositive: false
            ))
        }

        let recoveryTakeaway = recoveryTakeaway(
            readinessAvailable: readinessAvailable,
            confidence: confidence,
            sleep: sleepTrend,
            hrv: hrvTrend,
            restingHeartRate: restingHeartRateTrend,
            usedMetrics: Set(preferences.decisionMetricPreferences.filter(\.usedInRecommendation).map(\.metric)),
            safetyGate: safetyGate
        )

        return DailyHealthSnapshot(
            generatedAt: now,
            samples: samples,
            sleepSessions: sessions,
            latestSleep: latestSleep,
            readinessAvailable: readinessAvailable,
            sleepDebtMinutes: sleepDebt,
            readinessScore: roundedScore,
            readinessBand: band,
            confidence: confidence,
            reasons: reasons,
            latestHRV: latestHRV,
            baselineHRV: baselineHRV,
            latestRestingHeartRate: latestRHR,
            baselineRestingHeartRate: baselineRHR,
            previousDayActiveEnergy: previousEnergy,
            sleepTrend: sleepTrend,
            hrvTrend: hrvTrend,
            restingHeartRateTrend: restingHeartRateTrend,
            todaySignalOrder: preferences.orderedTodayMetrics,
            sleepTimingVariability: timingVariability,
            recoveryTakeaway: recoveryTakeaway,
            coreReadinessScore: coreRoundedScore,
            coreReadinessBand: coreBand,
            safetyGate: safetyGate,
            trainingContext: trainingContext
        )
    }

    func plan(
        snapshot: DailyHealthSnapshot,
        commitment: CalendarCommitment?,
        preferences: WellnessPreferences,
        now: Date = .now
    ) -> DailyPlan {
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let fallbackCommitment = calendar.date(bySettingHour: preferences.fallbackCommitmentHour, minute: 0, second: 0, of: tomorrowStart)!
        let commitmentStart = commitment?.startDate ?? fallbackCommitment
        let gymEnd = calendar.date(byAdding: .minute, value: -(preferences.travelToGymMinutes + preferences.postWorkoutMinutes + preferences.commitmentBufferMinutes), to: commitmentStart)!
        let gymStart = calendar.date(byAdding: .minute, value: -preferences.gymDurationMinutes, to: gymEnd)!
        let wake = calendar.date(byAdding: .minute, value: -20, to: gymStart)!

        let efficiencyBuffer = snapshot.latestSleep.map {
            Int(max(30, min(75, preferences.sleepNeedMinutes * (1 - $0.efficiency))))
        } ?? 30
        let bedtime = calendar.date(byAdding: .minute, value: -(Int(preferences.sleepNeedMinutes) + efficiencyBuffer), to: wake)!
        let adjustment = workoutAdjustment(for: snapshot)

        var warnings: [String] = []
        if bedtime <= now {
            warnings.append("The ideal bedtime has passed. Shorten or move the workout instead of cutting more sleep.")
        }
        if commitment == nil {
            warnings.append("No calendar commitment was found; the plan uses your \(preferences.fallbackCommitmentHour):00 AM fallback.")
        }
        if snapshot.confidence == .low {
            warnings.append("Low confidence: connect vendor sources and collect at least seven nights before relying on trends.")
        }

        let windows = energyWindows(wakeTime: wake, bedtime: bedtime)
        return DailyPlan(
            generatedAt: now,
            bedtime: bedtime,
            wakeTime: wake,
            gymStart: gymStart,
            gymEnd: gymEnd,
            firstCommitment: commitment,
            readiness: snapshot.readinessBand,
            confidence: snapshot.confidence,
            workoutAdjustment: adjustment,
            energyWindows: windows,
            warnings: warnings
        )
    }

    func reconstructSleepSessions(from samples: [MetricSample]) -> [SleepSession] {
        let latestEnd = samples.filter { $0.kind == .sleep }.map(\.endDate).max() ?? .now
        let selection = selectedSourceSamples(
            kind: .sleep,
            samples: samples,
            preference: .defaultValue(for: .sleep),
            preferredVendor: "eight",
            now: latestEnd
        )
        return reconstructSleepSessions(fromSelectedSamples: selection.samples)
    }

    private func reconstructSleepSessions(fromSelectedSamples selected: [MetricSample]) -> [SleepSession] {
        guard let selectedBundleIdentifier = selected.first?.sourceBundleIdentifier else { return [] }
        let sorted = selected.sorted { $0.startDate < $1.startDate }
        var groups: [[MetricSample]] = []
        for sample in sorted {
            if let lastEnd = groups.last?.map(\.endDate).max(), sample.startDate.timeIntervalSince(lastEnd) <= 90 * 60 {
                groups[groups.count - 1].append(sample)
            } else {
                groups.append([sample])
            }
        }

        return groups.compactMap { group in
            let asleep = mergeIntervals(group.filter { $0.sleepStage?.countsAsSleep == true })
            guard !asleep.isEmpty else { return nil }
            let all = mergeIntervals(group.filter { $0.sleepStage != .awake })
            let asleepMinutes = intervalMinutes(asleep)
            guard asleepMinutes >= 180 else { return nil }
            let explicitInBed = mergeIntervals(group.filter { $0.sleepStage == .inBed })
            let observedSpan = group.map(\.endDate).max()!.timeIntervalSince(group.map(\.startDate).min()!) / 60
            let inBedMinutes = max(
                asleepMinutes,
                max(explicitInBed.isEmpty ? observedSpan : intervalMinutes(explicitInBed), intervalMinutes(all))
            )
            let deep = intervalMinutes(mergeIntervals(group.filter { $0.sleepStage == .deep }))
            let rem = intervalMinutes(mergeIntervals(group.filter { $0.sleepStage == .rem }))
            return SleepSession(
                id: UUID(),
                startDate: asleep.map(\.0).min()!,
                endDate: asleep.map(\.1).max()!,
                asleepMinutes: asleepMinutes,
                inBedMinutes: inBedMinutes,
                deepMinutes: deep,
                remMinutes: rem,
                sourceName: group[0].sourceName,
                sourceBundleIdentifier: selectedBundleIdentifier
            )
        }.sorted { $0.endDate > $1.endDate }
    }

    private func selectedDailyValues(
        kind: MetricKind,
        samples: [MetricSample],
        preference: DecisionMetricPreference,
        preferredVendor: String,
        now: Date
    ) -> SelectedDailySeries {
        let selection = selectedSourceSamples(
            kind: kind,
            samples: samples.filter { $0.value != nil },
            preference: preference,
            preferredVendor: preferredVendor,
            now: now
        )
        let selected = selection.samples
        let days = Dictionary(grouping: selected) { calendar.startOfDay(for: $0.endDate) }
        let values = days.compactMap { day, values -> DailyValue? in
            let numbers = values.compactMap(\.value)
            guard let nightlyMedian = median(numbers) else { return nil }
            return DailyValue(date: day, value: nightlyMedian)
        }.sorted { $0.date > $1.date }
        let latestSample = selected.max { $0.endDate < $1.endDate }
        return SelectedDailySeries(
            sourceName: latestSample?.sourceName,
            sourceBundleIdentifier: selection.sourceBundleIdentifier,
            sourceHealth: selection.sourceHealth,
            values: values
        )
    }

    private func selectedSourceSamples(
        kind: MetricKind,
        samples: [MetricSample],
        preference: DecisionMetricPreference,
        preferredVendor: String,
        now: Date
    ) -> SelectedSourceSamples {
        let matching = samples.filter {
            $0.kind == kind && $0.endDate <= now && !$0.wasUserEntered
        }
        // Product type is part of source identity so a Watch series is not
        // silently combined with phone/app values written under the same bundle.
        let groups = Dictionary(grouping: matching, by: \.sourceIdentity)
        let requestedBundle = preference.requestedBundleIdentifier

        guard !groups.isEmpty else {
            let reason = requestedBundle.map {
                "Your selected source \($0) has no readable \(kind.title.lowercased()) data."
            } ?? "No source has provided readable \(kind.title.lowercased()) data yet."
            return SelectedSourceSamples(
                samples: [],
                sourceName: nil,
                sourceBundleIdentifier: nil,
                sourceHealth: .unavailable(
                    requestedBundleIdentifier: requestedBundle,
                    reason: reason
                )
            )
        }

        func latestSample(for sourceIdentity: String) -> MetricSample? {
            groups[sourceIdentity]?.max(by: { $0.endDate < $1.endDate })
        }

        func latestDate(for sourceIdentity: String) -> Date {
            latestSample(for: sourceIdentity)?.endDate ?? .distantPast
        }

        func sourceName(for sourceIdentity: String) -> String {
            latestSample(for: sourceIdentity)?.sourceName ?? sourceIdentity
        }

        func bundleIdentifier(for sourceIdentity: String) -> String {
            latestSample(for: sourceIdentity)?.sourceBundleIdentifier ?? sourceIdentity
        }

        func freshnessBucket(for sourceIdentity: String) -> Int {
            let age = now.timeIntervalSince(latestDate(for: sourceIdentity))
            if age <= 36 * 3600 { return 2 }
            if age <= 72 * 3600 { return 1 }
            return 0
        }

        func observedDayCoverage(for sourceIdentity: String) -> Int {
            let today = calendar.startOfDay(for: now)
            let coverageStart = calendar.date(byAdding: .day, value: -20, to: today)!
            return Set((groups[sourceIdentity] ?? []).compactMap { sample -> Date? in
                let day = calendar.startOfDay(for: sample.endDate)
                return day >= coverageStart ? day : nil
            }).count
        }

        func isPreferredVendor(_ sourceIdentity: String) -> Bool {
            let latest = latestSample(for: sourceIdentity)
            let searchable = [
                latest?.sourceName,
                latest?.sourceBundleIdentifier,
                latest?.sourceProductType,
                latest?.device?.model
            ].compactMap { $0 }.joined(separator: " ").lowercased()
            return searchable.contains(preferredVendor)
        }

        /// Automatic choice is deterministic and evidence-led: freshness tier,
        /// observed-day coverage, exact recency, then vendor only as a tie-break.
        func ranksBefore(_ lhs: String, _ rhs: String) -> Bool {
            let lhsFreshness = freshnessBucket(for: lhs)
            let rhsFreshness = freshnessBucket(for: rhs)
            if lhsFreshness != rhsFreshness { return lhsFreshness > rhsFreshness }

            let lhsCoverage = observedDayCoverage(for: lhs)
            let rhsCoverage = observedDayCoverage(for: rhs)
            if lhsCoverage != rhsCoverage { return lhsCoverage > rhsCoverage }

            let lhsLatest = latestDate(for: lhs)
            let rhsLatest = latestDate(for: rhs)
            if lhsLatest != rhsLatest { return lhsLatest > rhsLatest }

            let lhsPreferred = isPreferredVendor(lhs)
            let rhsPreferred = isPreferredVendor(rhs)
            if lhsPreferred != rhsPreferred { return lhsPreferred }

            return lhs < rhs
        }

        func result(
            sourceIdentity: String,
            state: MetricSourceHealth.State,
            requestedBundleIdentifier: String?,
            reason: String
        ) -> SelectedSourceSamples {
            let bundleIdentifier = bundleIdentifier(for: sourceIdentity)
            return SelectedSourceSamples(
                samples: groups[sourceIdentity] ?? [],
                sourceName: sourceName(for: sourceIdentity),
                sourceBundleIdentifier: bundleIdentifier,
                sourceHealth: MetricSourceHealth(
                    state: state,
                    requestedBundleIdentifier: requestedBundleIdentifier,
                    selectedBundleIdentifier: bundleIdentifier,
                    reason: reason
                )
            )
        }

        let automaticSourceIdentity = groups.keys.sorted(by: ranksBefore).first

        func automaticReason(for sourceIdentity: String) -> String {
            let name = sourceName(for: sourceIdentity)
            let coverage = observedDayCoverage(for: sourceIdentity)
            let period = kind == .sleep ? "night" : "day"
            let coverageText = coverage == 1
                ? "1 observed \(period)"
                : "\(coverage) observed \(period)s"
            return "Automatically using \(name) based on usable freshness and \(coverageText)."
        }

        guard preference.sourceMode == .manual else {
            guard let automaticSourceIdentity else {
                return SelectedSourceSamples(
                    samples: [],
                    sourceName: nil,
                    sourceBundleIdentifier: nil,
                    sourceHealth: .unavailable()
                )
            }
            return result(
                sourceIdentity: automaticSourceIdentity,
                state: .automatic,
                requestedBundleIdentifier: nil,
                reason: automaticReason(for: automaticSourceIdentity)
            )
        }

        let requestedSourceIdentity = requestedBundle.flatMap { requestedBundle in
            groups.keys.filter { bundleIdentifier(for: $0) == requestedBundle }
                .sorted(by: ranksBefore)
                .first
        }
        if let requestedBundle, let requestedSourceIdentity {
            let requestedIsUsable = freshnessBucket(for: requestedSourceIdentity) > 0
            if requestedIsUsable || !preference.allowAutomaticFallback {
                let name = sourceName(for: requestedSourceIdentity)
                let reason = requestedIsUsable
                    ? "Using your selected source, \(name), for \(kind.title)."
                    : "Using your selected source, \(name), for \(kind.title). Its data is stale, but automatic fallback is off."
                return result(
                    sourceIdentity: requestedSourceIdentity,
                    state: .manual,
                    requestedBundleIdentifier: requestedBundle,
                    reason: reason
                )
            }
        }

        guard preference.allowAutomaticFallback, let automaticSourceIdentity else {
            let reason = requestedBundle.map {
                "\($0) has no usable \(kind.title.lowercased()) data, and automatic fallback is off."
            } ?? "No manual source is selected for \(kind.title), and automatic fallback is off."
            return SelectedSourceSamples(
                samples: [],
                sourceName: nil,
                sourceBundleIdentifier: nil,
                sourceHealth: .unavailable(
                    requestedBundleIdentifier: requestedBundle,
                    reason: reason
                )
            )
        }

        let selectedName = sourceName(for: automaticSourceIdentity)
        let requestedDescription = requestedBundle.map { bundleIdentifier in
            requestedSourceIdentity.map { sourceName(for: $0) } ?? bundleIdentifier
        }
        let fallbackCause = requestedDescription.map {
            "\($0) has no usable \(kind.title.lowercased()) data."
        } ?? "No manual source is selected."
        return result(
            sourceIdentity: automaticSourceIdentity,
            state: .fallback,
            requestedBundleIdentifier: requestedBundle,
            reason: "\(fallbackCause) Using \(selectedName) because automatic fallback is on."
        )
    }

    private func baselineValues(for values: [DailyValue], currentDate: Date?) -> [Double] {
        guard let currentDate else { return [] }
        let currentDay = calendar.startOfDay(for: currentDate)
        let start = calendar.date(byAdding: .day, value: -21, to: currentDay)!
        return values
            .filter { $0.date >= start && $0.date < currentDay }
            .map(\.value)
    }

    private func recentValue(from values: [DailyValue], now: Date) -> Double? {
        guard let latest = values.first else { return nil }
        let age = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: latest.date),
            to: calendar.startOfDay(for: now)
        ).day ?? Int.max
        return age <= 2 ? latest.value : nil
    }

    private func safetyGate(
        from samples: [MetricSample],
        sleepSessions: [SleepSession],
        now: Date
    ) -> SafetyGateEvaluation {
        SafetyGateEvaluation(signals: MetricKind.safetyMetrics.map { kind in
            safetySignal(
                kind: kind,
                samples: samples,
                sleepSessions: sleepSessions,
                now: now
            )
        })
    }

    private func safetySignal(
        kind: MetricKind,
        samples: [MetricSample],
        sleepSessions: [SleepSession],
        now: Date
    ) -> SafetySignalEvaluation {
        let selection = selectedSourceSamples(
            kind: kind,
            samples: samples.filter { $0.value != nil },
            preference: .defaultValue(for: kind),
            preferredVendor: "watch",
            now: now
        )
        let requiresSleepWindow = kind == .heartRate
            || kind == .respiratoryRate
            || kind == .oxygenSaturation
        let eligibleSamples = selection.samples.filter { sample in
            !requiresSleepWindow || associatedSleepSession(for: sample, in: sleepSessions) != nil
        }
        let samplesByNight = Dictionary(grouping: eligibleSamples) { sample in
            if let session = associatedSleepSession(for: sample, in: sleepSessions) {
                return calendar.startOfDay(for: session.endDate)
            }
            return calendar.startOfDay(for: sample.endDate)
        }
        let values = samplesByNight.compactMap { date, samples -> DailyValue? in
            guard let value = median(samples.compactMap(\.value)) else { return nil }
            return DailyValue(date: date, value: value)
        }.sorted { $0.date > $1.date }

        let current = values.first
        let freshness = freshness(for: current?.date, now: now)
        let baselineValues = baselineValues(for: values, currentDate: current?.date)
        let baseline = median(baselineValues)
        let deviation = current.flatMap { current in baseline.map { current.value - $0 } }
        let threshold = baseline.flatMap { baseline in
            outlierThreshold(kind: kind, baseline: baseline, values: baselineValues)
        }

        let state: SafetySignalState
        if current == nil {
            state = .noCurrentValue
        } else if freshness.value == .stale {
            state = .stale
        } else if baselineValues.count < SafetyGateEvaluation.minimumBaselineNights
                    || baseline == nil
                    || threshold == nil {
            state = .buildingBaseline
        } else if let currentValue = current?.value,
                  let baseline,
                  let threshold,
                  isOutlier(kind: kind, current: currentValue, baseline: baseline, threshold: threshold) {
            state = .outlier
        } else {
            state = .withinRange
        }

        return SafetySignalEvaluation(
            kind: kind,
            state: state,
            currentValue: current?.value,
            currentDate: current?.date,
            baselineMedian: baseline,
            baselineNightCount: baselineValues.count,
            deviation: deviation,
            outlierThreshold: threshold,
            sourceName: selection.sourceName,
            sourceBundleIdentifier: selection.sourceBundleIdentifier
        )
    }

    private func associatedSleepSession(
        for sample: MetricSample,
        in sessions: [SleepSession]
    ) -> SleepSession? {
        // Some writers timestamp a nightly summary at wake rather than inside
        // the sleep interval, so allow a narrow post-wake association window.
        sessions.first { session in
            sample.endDate >= session.startDate.addingTimeInterval(-30 * 60)
                && sample.startDate <= session.endDate.addingTimeInterval(2 * 3600)
        }
    }

    private func outlierThreshold(
        kind: MetricKind,
        baseline: Double,
        values: [Double]
    ) -> Double? {
        guard let medianAbsoluteDeviation = median(values.map { abs($0 - baseline) }) else {
            return nil
        }
        let robustThreshold = 2.5 * 1.4826 * medianAbsoluteDeviation
        let floor: Double = switch kind {
        case .respiratoryRate: 0.75
        case .oxygenSaturation: 1
        case .sleepingWristTemperature, .bodyTemperature: 0.2
        case .heartRate: 3
        default: 0
        }
        return max(robustThreshold, floor)
    }

    private func isOutlier(
        kind: MetricKind,
        current: Double,
        baseline: Double,
        threshold: Double
    ) -> Bool {
        let relevantDifference = kind == .oxygenSaturation
            ? baseline - current
            : abs(current - baseline)
        return relevantDifference > 0 && relevantDifference >= threshold
    }

    private func makeSleepTrend(
        values: [DailyValue],
        sourceName: String?,
        sourceBundleIdentifier: String?,
        sourceHealth: MetricSourceHealth,
        targetMinutes: Double,
        now: Date
    ) -> MetricTrendSeries {
        let ordered = values.sorted { $0.date > $1.date }
        let current = ordered.first
        let freshness = freshness(for: current?.date, now: now)
        let points = alignedTrendPoints(values: ordered, referenceValue: targetMinutes, now: now)
        let ratio = current.map { targetMinutes > 0 ? $0.value / targetMinutes : 0 }
        let status: MetricSignalStatus
        let statusText: String
        if current == nil {
            status = .unavailable
            statusText = "Unavailable"
        } else if freshness.value == .stale {
            status = .needsAttention
            statusText = "Stale signal"
        } else if (ratio ?? 0) >= 0.975 {
            status = .onTarget
            statusText = sleepDifferenceText(current: current?.value, target: targetMinutes)
        } else if (ratio ?? 0) >= 0.9 {
            status = .nearTarget
            statusText = sleepDifferenceText(current: current?.value, target: targetMinutes)
        } else {
            status = .needsAttention
            statusText = sleepDifferenceText(current: current?.value, target: targetMinutes)
        }
        return MetricTrendSeries(
            kind: .sleep,
            sourceName: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            currentValue: current?.value,
            currentDate: current?.date,
            referenceValue: targetMinutes,
            referenceLabel: "Sleep target",
            baselineDayCount: Set(ordered.map { calendar.startOfDay(for: $0.date) }).count,
            freshness: freshness.value,
            ageInDays: freshness.age,
            status: status,
            statusText: statusText,
            sourceHealth: sourceHealth,
            points: points,
            sevenDaySummary: trendSummary(points: Array(points.suffix(7)), referenceValue: targetMinutes),
            twentyEightDaySummary: trendSummary(points: points, referenceValue: targetMinutes)
        )
    }

    private func makeBiometricTrend(
        kind: MetricKind,
        series: SelectedDailySeries,
        referenceValue: Double?,
        baselineCount: Int,
        higherIsBetter: Bool,
        now: Date
    ) -> MetricTrendSeries {
        let current = series.values.first
        let freshness = freshness(for: current?.date, now: now)
        let points = alignedTrendPoints(values: series.values, referenceValue: referenceValue, now: now)
        let relative = current.flatMap { value in
            referenceValue.flatMap { $0 > 0 ? value.value / $0 : nil }
        }
        let status: MetricSignalStatus
        let statusText: String
        if current == nil {
            status = .unavailable
            statusText = "Unavailable"
        } else if freshness.value == .stale {
            status = .needsAttention
            statusText = "Stale signal"
        } else if referenceValue == nil || baselineCount < 7 {
            status = .buildingBaseline
            statusText = "Early estimate"
        } else if higherIsBetter {
            if (relative ?? 0) >= 0.95 {
                status = .onTarget
                statusText = "At baseline"
            } else if (relative ?? 0) >= 0.85 {
                status = .nearTarget
                statusText = "Near baseline"
            } else {
                status = .needsAttention
                statusText = "Below baseline"
            }
        } else if (relative ?? .infinity) <= 1.05 {
            status = .onTarget
            statusText = "At baseline"
        } else if (relative ?? .infinity) <= 1.1 {
            status = .nearTarget
            statusText = "Near baseline"
        } else {
            status = .needsAttention
            statusText = "Above baseline"
        }
        return MetricTrendSeries(
            kind: kind,
            sourceName: series.sourceName,
            sourceBundleIdentifier: series.sourceBundleIdentifier,
            currentValue: current?.value,
            currentDate: current?.date,
            referenceValue: referenceValue,
            referenceLabel: "Your 21-day baseline",
            baselineDayCount: baselineCount,
            freshness: freshness.value,
            ageInDays: freshness.age,
            status: status,
            statusText: statusText,
            sourceHealth: series.sourceHealth,
            points: points,
            sevenDaySummary: trendSummary(points: Array(points.suffix(7)), referenceValue: referenceValue),
            twentyEightDaySummary: trendSummary(points: points, referenceValue: referenceValue)
        )
    }

    private func alignedTrendPoints(
        values: [DailyValue],
        referenceValue: Double?,
        now: Date
    ) -> [MetricTrendPoint] {
        let today = calendar.startOfDay(for: now)
        var valuesByDay: [Date: Double] = [:]
        for item in values {
            let day = calendar.startOfDay(for: item.date)
            valuesByDay[day] = max(valuesByDay[day] ?? 0, item.value)
        }

        var segment = 0
        var isInsideRecordedSegment = false
        return (0..<TrendWindow.twentyEightDays.rawValue).map { index in
            let offset = index - (TrendWindow.twentyEightDays.rawValue - 1)
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let value = valuesByDay[day]
            let pointSegment: Int?
            if value != nil {
                if !isInsideRecordedSegment { segment += 1 }
                isInsideRecordedSegment = true
                pointSegment = segment
            } else {
                isInsideRecordedSegment = false
                pointSegment = nil
            }
            let deviation = value.flatMap { value in
                referenceValue.flatMap { reference in
                    reference > 0 ? ((value - reference) / reference) * 100 : nil
                }
            }
            return MetricTrendPoint(
                date: day,
                value: value,
                deviationPercentage: deviation,
                segmentID: pointSegment
            )
        }
    }

    private func trendSummary(
        points: [MetricTrendPoint],
        referenceValue: Double?
    ) -> MetricTrendSummary {
        let values = points.compactMap(\.value)
        let average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        return MetricTrendSummary(
            average: average,
            referenceValue: referenceValue,
            deltaFromReference: average.flatMap { average in referenceValue.map { average - $0 } },
            recordedDays: values.count,
            expectedDays: points.count
        )
    }

    private func freshness(for date: Date?, now: Date) -> (value: MetricFreshness, age: Int?) {
        guard let date else { return (.missing, nil) }
        let age = max(calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0, 0)
        if age == 0 { return (.current, age) }
        if age <= 2 { return (.recent, age) }
        return (.stale, age)
    }

    private func sleepDifferenceText(current: Double?, target: Double) -> String {
        guard let current else { return "Unavailable" }
        let delta = Int((current - target).rounded())
        if delta == 0 { return "On target" }
        let total = abs(delta)
        let duration = total < 60 ? "\(total)m" : "\(total / 60)h \(total % 60)m"
        return delta < 0 ? "\(duration) below target" : "\(duration) above target"
    }

    private func sleepTimingVariability(sessions: [SleepSession]) -> SleepTimingVariability {
        let recent = Array(sessions.sorted { $0.endDate > $1.endDate }.prefix(28))
        guard recent.count >= 2 else {
            return SleepTimingVariability(
                sourceName: recent.first?.sourceName,
                sourceBundleIdentifier: recent.first?.sourceBundleIdentifier,
                recordedNights: recent.count,
                bedtimeMinutes: nil,
                wakeTimeMinutes: nil
            )
        }
        return SleepTimingVariability(
            sourceName: recent.first?.sourceName,
            sourceBundleIdentifier: recent.first?.sourceBundleIdentifier,
            recordedNights: recent.count,
            bedtimeMinutes: standardDeviation(recent.map { localHour($0.startDate) }) * 60,
            wakeTimeMinutes: standardDeviation(recent.map { localHour($0.endDate) }) * 60
        )
    }

    private func recoveryTakeaway(
        readinessAvailable: Bool,
        confidence: DataConfidence,
        sleep: MetricTrendSeries,
        hrv: MetricTrendSeries,
        restingHeartRate: MetricTrendSeries,
        usedMetrics: Set<MetricKind>,
        safetyGate: SafetyGateEvaluation
    ) -> String {
        guard !usedMetrics.isEmpty else {
            return "No recovery signals are currently included in the recommendation."
        }
        guard readinessAvailable else {
            return usedMetrics.contains(.sleep)
                ? "No recent overnight sleep is available, so recovery guidance is not ready yet."
                : "No current selected recovery signal is available, so guidance is not ready yet."
        }
        let prefix = confidence == .low ? "Early estimate: " : ""
        if safetyGate.capsReadinessAtModerate {
            return prefix + "multiple fresh overnight signals are outside their same-source ranges, so today’s recommendation is capped and reduced."
        }
        if safetyGate.blocksProgression {
            return prefix + "one fresh overnight signal is outside its same-source range, so progression is paused while the core recommendation stays unchanged."
        }
        if usedMetrics.contains(.sleep), sleep.status == .needsAttention {
            return prefix + "sleep duration is the clearest recovery constraint relative to your target."
        }
        if (usedMetrics.contains(.heartRateVariability) && hrv.status == .needsAttention)
            || (usedMetrics.contains(.restingHeartRate) && restingHeartRate.status == .needsAttention) {
            return prefix + "one or more cardiovascular signals are away from their same-source median."
        }
        if (usedMetrics.contains(.heartRateVariability) && hrv.status == .buildingBaseline)
            || (usedMetrics.contains(.restingHeartRate) && restingHeartRate.status == .buildingBaseline) {
            if usedMetrics == Set(MetricKind.decisionMetrics) {
                return prefix + "sleep is available, while HRV and resting-heart-rate baselines are still developing."
            }
            return prefix + "one or more selected cardiovascular baselines are still developing."
        }
        if usedMetrics == Set(MetricKind.decisionMetrics) {
            return prefix + "sleep, HRV, and resting heart rate are broadly near their current references."
        }
        let names = MetricKind.decisionMetrics
            .filter(usedMetrics.contains)
            .map { $0.title.lowercased() }
            .joined(separator: ", ")
        return prefix + "the selected signals (\(names)) are broadly near their current references."
    }

    private func trainingContext(
        from samples: [MetricSample],
        now: Date
    ) -> TrainingContextSnapshot {
        let today = calendar.startOfDay(for: now)
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: today)!
        let workoutCandidates = samples.filter {
            $0.kind == .workout
                && !$0.wasUserEntered
                && $0.startDate >= sevenDayStart
                && $0.startDate <= now
        }
        var workoutsByIdentity: [String: MetricSample] = [:]
        for workout in workoutCandidates {
            let identity = workout.workoutSyncIdentifier.map {
                "sync:\(workout.sourceBundleIdentifier)|\($0)"
            } ?? "uuid:\(workout.id.uuidString)"
            guard let existing = workoutsByIdentity[identity] else {
                workoutsByIdentity[identity] = workout
                continue
            }
            let existingVersion = existing.workoutSyncVersion ?? 0
            let candidateVersion = workout.workoutSyncVersion ?? 0
            if candidateVersion > existingVersion
                || (candidateVersion == existingVersion && workout.endDate > existing.endDate) {
                workoutsByIdentity[identity] = workout
            }
        }
        let workouts = Array(workoutsByIdentity.values)
        let workoutMinutes = workouts.compactMap(\.value)
        return TrainingContextSnapshot(
            previousDayActiveEnergy: totalForPreviousDay(
                kind: .activeEnergy,
                samples: samples,
                now: now,
                preferredVendor: "watch"
            ),
            previousDayExerciseMinutes: totalForPreviousDay(
                kind: .exerciseMinutes,
                samples: samples,
                now: now,
                preferredVendor: "watch"
            ),
            previousDaySteps: totalForPreviousDay(
                kind: .steps,
                samples: samples,
                now: now,
                preferredVendor: "watch"
            ),
            workoutsLastSevenDays: workouts.count,
            workoutMinutesLastSevenDays: workoutMinutes.isEmpty
                ? nil
                : workoutMinutes.reduce(0, +),
            latestWorkoutDate: workouts.map(\.endDate).max()
        )
    }

    private func totalForPreviousDay(
        kind: MetricKind,
        samples: [MetricSample],
        now: Date,
        preferredVendor: String
    ) -> Double? {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let matching = samples.filter {
            $0.kind == kind
                && !$0.wasUserEntered
                && $0.startDate >= yesterday
                && $0.startDate < today
        }
        let sourceGroups = Dictionary(grouping: matching, by: \.sourceIdentity)
        let preferredGroups = sourceGroups.filter { _, group in
            group.contains {
                "\($0.sourceName) \($0.sourceBundleIdentifier)".lowercased().contains(preferredVendor)
            }
        }
        let selected = (preferredGroups.isEmpty ? sourceGroups : preferredGroups)
            .max { lhs, rhs in
                if lhs.value.count == rhs.value.count {
                    return (lhs.value.map(\.endDate).max() ?? .distantPast)
                        < (rhs.value.map(\.endDate).max() ?? .distantPast)
                }
                return lhs.value.count < rhs.value.count
            }?.value ?? []
        let values = selected.compactMap(\.value)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    private func calculateSleepDebt(sessions: [SleepSession], needMinutes: Double) -> Double {
        sessions.reduce(0) { debt, session in
            debt + max(0, needMinutes - session.asleepMinutes)
        }
    }

    private func sleepConsistency(sessions: [SleepSession]) -> Double {
        guard sessions.count >= 2 else { return 50 }
        let starts = sessions.map { localHour($0.startDate) }
        let wakes = sessions.map { localHour($0.endDate) }
        let variability = standardDeviation(starts) * 0.55 + standardDeviation(wakes) * 0.45
        return clamp(100 - variability * 18)
    }

    private func localHour(_ date: Date) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        var hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
        if hour < 12 { hour += 24 }
        return hour
    }

    private func energyWindows(wakeTime: Date, bedtime: Date) -> [EnergyWindow] {
        func offset(_ minutes: Int) -> Date { calendar.date(byAdding: .minute, value: minutes, to: wakeTime)! }
        return [
            .init(kind: .grogginess, title: "Wake-up ramp", startDate: wakeTime, endDate: offset(90)),
            .init(kind: .peak, title: "Morning performance", startDate: offset(150), endDate: offset(270)),
            .init(kind: .dip, title: "Midday dip", startDate: offset(390), endDate: offset(510)),
            .init(kind: .peak, title: "Second wind", startDate: offset(630), endDate: offset(750)),
            .init(kind: .windDown, title: "Wind-down", startDate: calendar.date(byAdding: .minute, value: -90, to: bedtime)!, endDate: bedtime)
        ]
    }

    private func workoutAdjustment(for snapshot: DailyHealthSnapshot) -> WorkoutAdjustment {
        guard snapshot.readinessAvailable else {
            return .init(
                title: "No adjustment yet",
                detail: "Keep your usual plan until a recent overnight sleep session is available.",
                volumeMultiplier: 1,
                rpeCap: nil,
                allowProgression: false
            )
        }

        let coreAdjustment: WorkoutAdjustment
        if snapshot.confidence == .low && snapshot.coreReadinessBand == .high {
            coreAdjustment = .init(
                title: "Conservative baseline",
                detail: "Early signals look positive, but keep one or two reps in reserve while your baseline develops.",
                volumeMultiplier: 0.85,
                rpeCap: 8,
                allowProgression: false
            )
        } else {
            coreAdjustment = switch snapshot.coreReadinessBand {
            case .high:
                .init(title: "Full performance session", detail: "Keep planned volume. Review your recent sets before choosing a load increase; Dayvera does not change weights automatically.", volumeMultiplier: 1, rpeCap: nil, allowProgression: true)
            case .moderate:
                .init(title: "Reduce volume 25%", detail: "Keep technique and normal working weight, remove accessory sets, and cap effort at RPE 8.", volumeMultiplier: 0.75, rpeCap: 8, allowProgression: false)
            case .low:
                .init(title: "Recovery or reschedule", detail: "Favor mobility or light zone-2 work. Avoid PR attempts and heavy compound volume.", volumeMultiplier: 0.35, rpeCap: 6, allowProgression: false)
            }
        }

        if snapshot.safetyGate.capsReadinessAtModerate {
            let signalNames = snapshot.safetyGate.freshOutliers.map { $0.kind.title.lowercased() }.joined(separator: ", ")
            return .init(
                title: "Safety check · reduce volume 10%",
                detail: "Multiple fresh signals (\(signalNames)) are outside their 21-day same-source ranges. The readiness band is capped at Moderate and the pre-check volume is reduced by 10%.",
                volumeMultiplier: coreAdjustment.volumeMultiplier * 0.9,
                rpeCap: coreAdjustment.rpeCap,
                allowProgression: false
            )
        }
        if snapshot.safetyGate.blocksProgression {
            let signalName = snapshot.safetyGate.freshOutliers.first?.kind.title.lowercased()
                ?? "overnight signal"
            return .init(
                title: "Safety check · hold progression",
                detail: "A fresh \(signalName) value is outside its 21-day same-source range. Core readiness and planned volume are unchanged, but progression is paused today.",
                volumeMultiplier: coreAdjustment.volumeMultiplier,
                rpeCap: coreAdjustment.rpeCap,
                allowProgression: false
            )
        }
        return coreAdjustment
    }

    private func asleepDuration(_ samples: [MetricSample]) -> TimeInterval {
        samples.filter { $0.sleepStage?.countsAsSleep == true }.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
    }

    private func mergeIntervals(_ samples: [MetricSample]) -> [(Date, Date)] {
        let intervals = samples.map { ($0.startDate, $0.endDate) }.sorted { $0.0 < $1.0 }
        var merged: [(Date, Date)] = []
        for interval in intervals {
            if let last = merged.last, interval.0 <= last.1 {
                merged[merged.count - 1] = (last.0, max(last.1, interval.1))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    private func intervalMinutes(_ intervals: [(Date, Date)]) -> Double {
        intervals.reduce(0) { $0 + $1.1.timeIntervalSince($1.0) / 60 }
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return sqrt(values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1))
    }

    private func clamp(_ value: Double, lower: Double = 0, upper: Double = 100) -> Double {
        min(max(value, lower), upper)
    }
}
