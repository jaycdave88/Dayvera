import Foundation

/// Converts HealthKit-derived features and durable local workout history into the
/// bounded state consumed by both the deterministic planner and optional AI layer.
struct DailyTrainingStateBuilder: Sendable {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func makeState(
        snapshot: DailyHealthSnapshot,
        sessions: [WorkoutSessionRecord],
        constraints: WorkoutConstraints,
        curatedPool: [CuratedExerciseDefinition],
        enabledRecoveryMetrics: Set<MetricKind> = Set(MetricKind.decisionMetrics),
        loadUnit: LoadUnit = .pounds,
        now: Date = .now
    ) -> DailyTrainingState {
        let training = trainingHistory(
            sessions: sessions,
            healthSamples: snapshot.samples,
            curatedPool: curatedPool,
            loadUnit: loadUnit,
            now: now
        )
        let supportedRecoveryMetrics = Set(MetricKind.decisionMetrics)
        let enabledMetrics = enabledRecoveryMetrics.intersection(supportedRecoveryMetrics)
        let enabledTrends = MetricKind.decisionMetrics.compactMap { metric in
            enabledMetrics.contains(metric) ? trend(for: metric, in: snapshot) : nil
        }
        let currentSignals = enabledTrends.filter {
            $0.currentValue != nil && $0.freshness != .stale
        }
        let readinessAvailable = !enabledMetrics.isEmpty && snapshot.readinessAvailable
        let quality = RecommendationDataQuality(
            availability: readinessAvailable
                ? (currentSignals.count == enabledTrends.count ? .available : .partial)
                : .unavailable,
            confidence: enabledMetrics.isEmpty ? .low : snapshot.confidence,
            currentSignalCount: currentSignals.count,
            baselineDayCount: enabledTrends.map(\.baselineDayCount).max() ?? 0,
            isStale: !enabledTrends.isEmpty && currentSignals.isEmpty
        )
        let recovery = RecoveryState(
            readinessScore: readinessAvailable ? snapshot.readinessScore : nil,
            readinessBand: readinessAvailable ? snapshot.readinessBand : .moderate,
            sleepMinutes: enabledMetrics.contains(.sleep)
                ? snapshot.latestSleep.map { Int($0.asleepMinutes.rounded()) }
                : nil,
            sleepTargetMinutes: enabledMetrics.contains(.sleep) ? snapshot.sleepTrend.referenceValue.flatMap {
                let minutes = Int($0.rounded())
                return minutes > 0 ? minutes : nil
            } : nil,
            sleepVsBaselineMinutes: enabledMetrics.contains(.sleep)
                ? sleepDifferenceFromRecentAverage(snapshot)
                : nil,
            heartRateVariabilityVsBaseline: enabledMetrics.contains(.heartRateVariability)
                ? proportionalDifference(snapshot.latestHRV, from: snapshot.baselineHRV)
                : nil,
            restingHeartRateDeltaBPM: enabledMetrics.contains(.restingHeartRate)
                ? difference(snapshot.latestRestingHeartRate, from: snapshot.baselineRestingHeartRate)
                : nil
        )

        return DailyTrainingState(
            generatedAt: now,
            recovery: recovery,
            training: training,
            constraints: constraints,
            dataQuality: quality,
            evidence: evidence(
                snapshot: snapshot,
                training: training,
                constraints: constraints,
                enabledRecoveryMetrics: enabledMetrics,
                readinessAvailable: readinessAvailable
            )
        )
    }

    private func trainingHistory(
        sessions: [WorkoutSessionRecord],
        healthSamples: [MetricSample],
        curatedPool: [CuratedExerciseDefinition],
        loadUnit: LoadUnit,
        now: Date
    ) -> TrainingHistoryState {
        let poolByID = Dictionary(uniqueKeysWithValues: curatedPool.map { ($0.catalogID, $0) })
        let startOfToday = calendar.startOfDay(for: now)
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let twentyEightDayStart = calendar.date(byAdding: .day, value: -34, to: startOfToday) ?? startOfToday
        let recent = sessions.filter { $0.startedAt >= sevenDayStart && $0.startedAt <= now }
        let baseline = sessions.filter { $0.startedAt >= twentyEightDayStart && $0.startedAt < sevenDayStart }
        let importedWorkoutCount = importedHealthWorkoutCount(
            in: healthSamples,
            excluding: sessions,
            from: sevenDayStart,
            through: now
        )

        let recentEffort = effort(in: recent)
        let baselineWeekly = effort(in: baseline) / 4
        let loadRatio = baselineWeekly > 0 ? recentEffort / baselineWeekly : nil

        var muscleLatest: [MuscleGroup: Date] = [:]
        var movementSetCounts: [MovementPattern: Int] = [:]
        var setsByExercise: [String: [(sessionID: UUID, date: Date, set: CompletedSet)]] = [:]

        for session in sessions where session.startedAt <= now {
            for set in session.sets where !set.isWarmup {
                let catalogDefinition = set.catalogID.flatMap { poolByID[$0] }
                if let muscle = set.muscleGroup ?? catalogDefinition?.primaryMuscleGroup {
                    muscleLatest[muscle] = max(muscleLatest[muscle] ?? .distantPast, session.startedAt)
                }
                if session.startedAt >= sevenDayStart,
                   let pattern = set.movementPattern.flatMap(MovementPattern.init(rawValue:))
                    ?? catalogDefinition?.movementPattern {
                    movementSetCounts[pattern, default: 0] += 1
                }
                if let catalogID = set.catalogID, poolByID[catalogID] != nil {
                    setsByExercise[catalogID, default: []].append((session.id, session.startedAt, set))
                }
            }
        }

        let recency = muscleLatest.map { muscle, date in
            MuscleTrainingRecency(
                muscleGroup: muscle,
                daysAgo: max(calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: startOfToday).day ?? 0, 0)
            )
        }.sorted { $0.muscleGroup.rawValue < $1.muscleGroup.rawValue }

        let movementLoads = MovementPattern.allCases.map { pattern in
            MovementTrainingLoad(
                movementPattern: pattern,
                workingSetsLast7Days: movementSetCounts[pattern, default: 0],
                targetWorkingSets: targetSets(for: pattern)
            )
        }

        let histories = setsByExercise.compactMap { catalogID, values -> ExerciseTrainingHistory? in
            guard let latest = values.max(by: { lhs, rhs in
                if lhs.date == rhs.date { return lhs.set.completedAt < rhs.set.completedAt }
                return lhs.date < rhs.date
            }) else { return nil }
            let completedSessions = Set(values.map { $0.sessionID }).count
            let daysAgo = max(calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: latest.date),
                to: startOfToday
            ).day ?? 0, 0)
            return ExerciseTrainingHistory(
                catalogID: catalogID,
                completedSessions: completedSessions,
                lastPerformedDaysAgo: daysAgo,
                lastWorkingLoad: latest.set.resolvedLoadUnit.convert(
                    latest.set.weight,
                    to: loadUnit
                ),
                lastCompletedReps: latest.set.reps,
                lastRPE: latest.set.rpe,
                progressionEligible: completedSessions >= 2
            )
        }.sorted { $0.catalogID < $1.catalogID }

        return TrainingHistoryState(
            sessionsLast7Days: recent.count + importedWorkoutCount,
            weeklyTrainingEffort: recentEffort,
            loadVersus28DayAverage: loadRatio,
            muscleRecency: recency,
            movementLoads: movementLoads,
            exerciseHistory: histories,
            mostRecentFocus: mostRecentFocus(in: sessions, poolByID: poolByID)
        )
    }

    /// HealthKit workouts can include workouts recorded by Apple Watch and copies
    /// exported by Dayvera itself. Sync identifiers prevent the exported copy
    /// from inflating the planner's seven-day session count. HealthKit does not
    /// expose exercise-level strength sets, so imported workouts affect frequency
    /// only—not muscle recency, volume, or progression.
    private func importedHealthWorkoutCount(
        in samples: [MetricSample],
        excluding localSessions: [WorkoutSessionRecord],
        from startDate: Date,
        through endDate: Date
    ) -> Int {
        let localSessionIdentifiers = Set(
            localSessions.map { $0.id.uuidString.lowercased() }
        )
        var workoutsByIdentity: [String: MetricSample] = [:]

        for workout in samples where workout.kind == .workout
            && !workout.wasUserEntered
            && workout.startDate >= startDate
            && workout.startDate <= endDate {
            let syncIdentifier = workout.workoutSyncIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if let syncIdentifier,
               !syncIdentifier.isEmpty,
               localSessionIdentifiers.contains(syncIdentifier) {
                continue
            }

            let identity = if let syncIdentifier, !syncIdentifier.isEmpty {
                // HealthKit sync identifiers are scoped to the writing source.
                // Two unrelated workout apps may legitimately reuse a value.
                "sync:\(workout.sourceBundleIdentifier.lowercased())|\(syncIdentifier)"
            } else {
                "uuid:\(workout.id.uuidString.lowercased())"
            }
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

        return workoutsByIdentity.count
    }

    private func evidence(
        snapshot: DailyHealthSnapshot,
        training: TrainingHistoryState,
        constraints: WorkoutConstraints,
        enabledRecoveryMetrics: Set<MetricKind>,
        readinessAvailable: Bool
    ) -> [EvidenceItem] {
        var items: [EvidenceItem] = []
        if readinessAvailable {
            items.append(.init(
                id: "readiness",
                provenance: .calculated,
                metric: .readiness,
                title: "Readiness \(snapshot.readinessScore)",
                detail: snapshot.readinessBand.title,
                value: Double(snapshot.readinessScore),
                observedAt: snapshot.generatedAt
            ))
        }
        if enabledRecoveryMetrics.contains(.sleep), let sleep = snapshot.latestSleep {
            items.append(.init(
                id: "sleep",
                provenance: .measured,
                metric: .sleep,
                title: sleep.asleepMinutes.hoursMinutes,
                detail: "Last night’s sleep",
                value: sleep.asleepMinutes,
                unit: "minutes",
                observedAt: sleep.endDate
            ))
        }
        if training.sessionsLast7Days > 0 {
            items.append(.init(
                id: "recent-workouts",
                provenance: .calculated,
                metric: .trainingHistory,
                title: "\(training.sessionsLast7Days) workouts in 7 days",
                detail: "Combined logged and non-user-entered Apple Health workouts, with Dayvera exports deduplicated.",
                value: Double(training.sessionsLast7Days),
                unit: "workouts"
            ))
        }
        if let days = lowerBodyRecency(training) {
            items.append(.init(
                id: "lower-body-history",
                provenance: .calculated,
                metric: .trainingHistory,
                title: "Lower body \(days)d ago",
                detail: "Based on workouts logged in Dayvera",
                value: Double(days),
                unit: "days"
            ))
        }
        items.append(.init(
            id: "available-time",
            provenance: .userEntered,
            metric: .schedule,
            title: "\(constraints.availableMinutes) min available",
            detail: "Today’s workout limit",
            value: Double(constraints.availableMinutes),
            unit: "minutes"
        ))
        items.append(.init(
            id: "equipment",
            provenance: .userEntered,
            metric: .equipment,
            title: constraints.equipmentProfile.name,
            detail: "Selected equipment profile"
        ))
        return items
    }

    private func trend(
        for metric: MetricKind,
        in snapshot: DailyHealthSnapshot
    ) -> MetricTrendSeries? {
        switch metric {
        case .sleep:
            snapshot.sleepTrend
        case .heartRateVariability:
            snapshot.hrvTrend
        case .restingHeartRate:
            snapshot.restingHeartRateTrend
        default:
            nil
        }
    }

    private func lowerBodyRecency(_ training: TrainingHistoryState) -> Int? {
        [.quads, .hamstrings, .glutes, .calves]
            .compactMap { training.daysSinceTraining($0) }
            .min()
    }

    private func mostRecentFocus(
        in sessions: [WorkoutSessionRecord],
        poolByID: [String: CuratedExerciseDefinition]
    ) -> TrainingFocus? {
        guard let session = sessions.max(by: { $0.startedAt < $1.startedAt }) else { return nil }
        let muscles = session.sets.compactMap { set in
            set.muscleGroup ?? set.catalogID.flatMap { poolByID[$0]?.primaryMuscleGroup }
        }
        let upper = muscles.filter { TrainingFocus.upperBody.includes($0) && $0 != .core }.count
        let lower = muscles.filter { TrainingFocus.lowerBody.includes($0) && $0 != .core }.count
        if upper == 0 && lower == 0 { return nil }
        if upper == lower { return .fullBody }
        return upper > lower ? .upperBody : .lowerBody
    }

    private func effort(in sessions: [WorkoutSessionRecord]) -> Double {
        Double(sessions.flatMap(\.sets).filter { !$0.isWarmup }.count)
    }

    private func targetSets(for pattern: MovementPattern) -> Int {
        switch pattern {
        case .squat, .hinge, .horizontalPush, .horizontalPull, .verticalPush, .verticalPull: 6
        case .singleLeg, .elbowFlexion, .elbowExtension, .calfRaise: 4
        case .carry, .core, .isolation: 3
        }
    }

    private func proportionalDifference(_ value: Double?, from baseline: Double?) -> Double? {
        guard let value, let baseline, baseline != 0 else { return nil }
        return (value - baseline) / baseline
    }

    private func difference(_ value: Double?, from baseline: Double?) -> Double? {
        guard let value, let baseline else { return nil }
        return value - baseline
    }

    private func sleepDifferenceFromRecentAverage(_ snapshot: DailyHealthSnapshot) -> Int? {
        guard let current = snapshot.latestSleep?.asleepMinutes,
              let average = snapshot.sleepTrend.sevenDaySummary.average else { return nil }
        return Int((current - average).rounded())
    }
}
