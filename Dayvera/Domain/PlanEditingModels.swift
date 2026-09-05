import Foundation

struct PlanDraft: Equatable, Sendable {
    var bedtime: Date
    var wakeTime: Date
    var gymStart: Date
    var gymEnd: Date

    init(bedtime: Date, wakeTime: Date, gymStart: Date, gymEnd: Date) {
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.gymStart = gymStart
        self.gymEnd = gymEnd
    }

    init(plan: DailyPlan) {
        self.init(
            bedtime: plan.bedtime,
            wakeTime: plan.wakeTime,
            gymStart: plan.gymStart,
            gymEnd: plan.gymEnd
        )
    }

    var sleepOpportunityMinutes: Int {
        Int(wakeTime.timeIntervalSince(bedtime) / 60)
    }

    var workoutMinutes: Int {
        Int(gymEnd.timeIntervalSince(gymStart) / 60)
    }

    func applicationRequest(basedOn request: PlanApplicationRequest) -> PlanApplicationRequest {
        PlanApplicationRequest(
            wakeTime: wakeTime,
            gymStart: gymStart,
            gymEnd: gymEnd,
            workoutTitle: request.workoutTitle,
            readinessScore: request.readinessScore,
            confidence: request.confidence,
            includesCalendarEvent: request.includesCalendarEvent,
            calendarDestinations: request.calendarDestinations
        )
    }
}

struct PlanDraftValidationContext: Equatable, Sendable {
    let now: Date
    let readyBy: Date

    init(now: Date = .now, readyBy: Date) {
        self.now = now
        self.readyBy = readyBy
    }
}

enum PlanDraftValidationIssue: Hashable, Sendable {
    case wakeMustBeFuture
    case bedtimeMustPrecedeWake
    case sleepOpportunityTooShort
    case sleepOpportunityTooLong
    case trainingMustFollowWake
    case workoutDurationOutOfRange
    case trainingEndsAfterReadyTime

    var message: String {
        switch self {
        case .wakeMustBeFuture:
            "Wake time must still be in the future."
        case .bedtimeMustPrecedeWake:
            "Bedtime must come before wake time."
        case .sleepOpportunityTooShort:
            "Keep at least 7 hours between bedtime and wake time."
        case .sleepOpportunityTooLong:
            "Choose a sleep window of 12 hours or less."
        case .trainingMustFollowWake:
            "Training must start after wake time."
        case .workoutDurationOutOfRange:
            "Keep the workout between 20 and 180 minutes."
        case .trainingEndsAfterReadyTime:
            "Training must end by the planned ready time."
        }
    }
}

enum PlanDraftValidator {
    static func issues(
        for draft: PlanDraft,
        context: PlanDraftValidationContext
    ) -> [PlanDraftValidationIssue] {
        var issues: [PlanDraftValidationIssue] = []
        if draft.wakeTime <= context.now { issues.append(.wakeMustBeFuture) }
        if draft.bedtime >= draft.wakeTime {
            issues.append(.bedtimeMustPrecedeWake)
        } else if draft.sleepOpportunityMinutes < 7 * 60 {
            issues.append(.sleepOpportunityTooShort)
        } else if draft.sleepOpportunityMinutes > 12 * 60 {
            issues.append(.sleepOpportunityTooLong)
        }
        if draft.gymStart <= draft.wakeTime { issues.append(.trainingMustFollowWake) }
        if !(20...180).contains(draft.workoutMinutes) {
            issues.append(.workoutDurationOutOfRange)
        }
        if draft.gymEnd > context.readyBy { issues.append(.trainingEndsAfterReadyTime) }
        return issues
    }
}

struct PlanSuggestedChanges: Equatable, Sendable {
    let bedtimeShiftMinutes: Int
    let wakeShiftMinutes: Int
    let trainingStartShiftMinutes: Int
    let workoutDurationMinutes: Int
    let rationale: String
}

struct PlanDraftProposal: Equatable, Sendable {
    let current: PlanDraft
    let proposed: PlanDraft
    let rationale: String
}

enum PlanProposalError: LocalizedError, Equatable, Sendable {
    case unavailable(String)
    case emptyRequest
    case requestTooLong
    case invalidSuggestion
    case unsafeSuggestion([PlanDraftValidationIssue])
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .emptyRequest: "Describe the timing change you want to explore."
        case .requestTooLong: "Keep the plan request under 500 characters."
        case .invalidSuggestion: "The suggested change was outside Dayvera’s planning limits. Your current draft was not changed."
        case .unsafeSuggestion(let issues):
            issues.first?.message ?? "The suggested plan did not pass validation. Your current draft was not changed."
        case .generationFailed: "A plan suggestion could not be created. You can still edit every time manually."
        }
    }
}

enum PlanProposalEngine {
    static func proposal(
        from current: PlanDraft,
        changes: PlanSuggestedChanges,
        context: PlanDraftValidationContext,
        calendar: Calendar = .current
    ) throws -> PlanDraftProposal {
        let shifts = [
            changes.bedtimeShiftMinutes,
            changes.wakeShiftMinutes,
            changes.trainingStartShiftMinutes
        ]
        guard shifts.allSatisfy({ (-120...120).contains($0) && $0.isMultiple(of: 5) }),
              (20...180).contains(changes.workoutDurationMinutes),
              changes.workoutDurationMinutes.isMultiple(of: 5),
              !changes.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              changes.rationale.count <= 240,
              let bedtime = calendar.date(byAdding: .minute, value: changes.bedtimeShiftMinutes, to: current.bedtime),
              let wake = calendar.date(byAdding: .minute, value: changes.wakeShiftMinutes, to: current.wakeTime),
              let start = calendar.date(byAdding: .minute, value: changes.trainingStartShiftMinutes, to: current.gymStart),
              let end = calendar.date(byAdding: .minute, value: changes.workoutDurationMinutes, to: start) else {
            throw PlanProposalError.invalidSuggestion
        }
        let proposed = PlanDraft(
            bedtime: bedtime,
            wakeTime: wake,
            gymStart: start,
            gymEnd: end
        )
        let issues = PlanDraftValidator.issues(for: proposed, context: context)
        guard issues.isEmpty else { throw PlanProposalError.unsafeSuggestion(issues) }
        return PlanDraftProposal(
            current: current,
            proposed: proposed,
            rationale: changes.rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
