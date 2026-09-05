import Foundation

/// Persisted identifiers are deliberately stable across the product rename.
/// Do not replace these strings: existing installs use them for safe Undo.
enum LegacyCompatibility {
    static let wakeAlarmID = "sleepCoachWakeAlarmID"
    static let wakeAlarmIDs = "sleepCoachWakeAlarmIDs"
    static let gymEventID = "sleepCoachGymEventID"
    static let gymEventReceipts = "sleepCoachGymEventReceipts"
    static let gymEventTitle = "Gym · Sleep Coach plan"
    static let calendarMarker = "Created by Sleep Coach."
    static let catalogDirectory = "SleepCoach"
}
