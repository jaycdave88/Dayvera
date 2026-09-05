import XCTest
@testable import Dayvera

final class PlanEditingTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testValidManualDraftCanBecomeApplicationRequestWithoutChangingDestinations() {
        let draft = validDraft()
        let destinations = CalendarEventDestinations(
            detailedCalendarIdentifier: "personal",
            busyCalendarIdentifiers: ["work"]
        )
        let base = PlanApplicationRequest(
            wakeTime: date(2026, 9, 6, 6, 30),
            gymStart: date(2026, 9, 6, 7, 0),
            gymEnd: date(2026, 9, 6, 8, 0),
            workoutTitle: "Lower Body Strength",
            readinessScore: 72,
            confidence: .medium,
            includesCalendarEvent: true,
            calendarDestinations: destinations
        )

        let request = draft.applicationRequest(basedOn: base)

        XCTAssertEqual(request.wakeTime, draft.wakeTime)
        XCTAssertEqual(request.gymStart, draft.gymStart)
        XCTAssertEqual(request.gymEnd, draft.gymEnd)
        XCTAssertEqual(request.calendarDestinations, destinations)
        XCTAssertEqual(request.workoutTitle, base.workoutTitle)
    }

    func testValidatorRejectsShortSleepTrainingBeforeWakeAndLateFinish() {
        let draft = PlanDraft(
            bedtime: date(2026, 9, 6, 0, 30),
            wakeTime: date(2026, 9, 6, 6, 30),
            gymStart: date(2026, 9, 6, 6, 0),
            gymEnd: date(2026, 9, 6, 9, 0)
        )
        let issues = PlanDraftValidator.issues(
            for: draft,
            context: .init(now: date(2026, 9, 5, 12, 0), readyBy: date(2026, 9, 6, 8, 30))
        )

        XCTAssertTrue(issues.contains(.sleepOpportunityTooShort))
        XCTAssertTrue(issues.contains(.trainingMustFollowWake))
        XCTAssertTrue(issues.contains(.trainingEndsAfterReadyTime))
    }

    func testProposalAppliesBoundedShiftsAndPassesDeterministicValidation() throws {
        let current = validDraft()
        let context = PlanDraftValidationContext(
            now: date(2026, 9, 5, 12, 0),
            readyBy: date(2026, 9, 6, 9, 0)
        )
        let proposal = try PlanProposalEngine.proposal(
            from: current,
            changes: PlanSuggestedChanges(
                bedtimeShiftMinutes: 30,
                wakeShiftMinutes: 30,
                trainingStartShiftMinutes: 30,
                workoutDurationMinutes: 45,
                rationale: "Moves the morning later while preserving the sleep window and ready deadline."
            ),
            context: context,
            calendar: calendar
        )

        XCTAssertEqual(proposal.proposed.bedtime, date(2026, 9, 5, 23, 0))
        XCTAssertEqual(proposal.proposed.wakeTime, date(2026, 9, 6, 6, 45))
        XCTAssertEqual(proposal.proposed.gymStart, date(2026, 9, 6, 7, 15))
        XCTAssertEqual(proposal.proposed.gymEnd, date(2026, 9, 6, 8, 0))
        XCTAssertTrue(PlanDraftValidator.issues(for: proposal.proposed, context: context).isEmpty)
    }

    func testProposalRejectsNonIncrementalOrUnsafeModelOutput() {
        let current = validDraft()
        let context = PlanDraftValidationContext(
            now: date(2026, 9, 5, 12, 0),
            readyBy: date(2026, 9, 6, 8, 30)
        )

        XCTAssertThrowsError(try PlanProposalEngine.proposal(
            from: current,
            changes: PlanSuggestedChanges(
                bedtimeShiftMinutes: 0,
                wakeShiftMinutes: 7,
                trainingStartShiftMinutes: 0,
                workoutDurationMinutes: 60,
                rationale: "Invalid increment."
            ),
            context: context,
            calendar: calendar
        )) { error in
            XCTAssertEqual(error as? PlanProposalError, .invalidSuggestion)
        }

        XCTAssertThrowsError(try PlanProposalEngine.proposal(
            from: current,
            changes: PlanSuggestedChanges(
                bedtimeShiftMinutes: 120,
                wakeShiftMinutes: -120,
                trainingStartShiftMinutes: 0,
                workoutDurationMinutes: 60,
                rationale: "Would cut the sleep window below the minimum."
            ),
            context: context,
            calendar: calendar
        )) { error in
            guard case .unsafeSuggestion(let issues) = error as? PlanProposalError else {
                return XCTFail("Expected deterministic validation failure")
            }
            XCTAssertTrue(issues.contains(.sleepOpportunityTooShort))
        }
    }

    private func validDraft() -> PlanDraft {
        PlanDraft(
            bedtime: date(2026, 9, 5, 22, 30),
            wakeTime: date(2026, 9, 6, 6, 15),
            gymStart: date(2026, 9, 6, 6, 45),
            gymEnd: date(2026, 9, 6, 7, 45)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
