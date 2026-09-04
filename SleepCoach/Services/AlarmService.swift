import AlarmKit
import Foundation
import SwiftUI

struct WakeAlarmMetadata: AlarmMetadata {
    let planGeneratedAt: Date
}

protocol AlarmScheduling {
    var authorizationLabel: String { get }
    func scheduleWakeAlarm(at date: Date) async throws
    func hasWakeAlarm(scheduledAt date: Date) throws -> Bool
    func cancelWakeAlarm() throws
}

final class AlarmService: AlarmScheduling {
    private let manager: AlarmManager
    private let defaults: UserDefaults
    private let alarmIDKey = "sleepCoachWakeAlarmID"
    private let alarmIDsKey = "sleepCoachWakeAlarmIDs"

    init(manager: AlarmManager = .shared, defaults: UserDefaults = .standard) {
        self.manager = manager
        self.defaults = defaults
    }

    var authorizationLabel: String {
        switch manager.authorizationState {
        case .authorized: "Authorized"
        case .denied: "Denied"
        case .notDetermined: "Not connected"
        @unknown default: "Unknown"
        }
    }

    func scheduleWakeAlarm(at date: Date) async throws {
        guard date > .now else { throw AlarmServiceError.timeInPast }
        let state = manager.authorizationState == .notDetermined
            ? try await manager.requestAuthorization()
            : manager.authorizationState
        guard state == .authorized else { throw AlarmServiceError.authorizationDenied }

        let previousIDs = persistedAlarmIDs()
        let id = UUID()
        let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
        let alert = AlarmPresentation.Alert(title: "Wake for your plan", stopButton: stopButton)
        let presentation = AlarmPresentation(alert: alert)
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: WakeAlarmMetadata(planGeneratedAt: .now),
            tintColor: .indigo
        )
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(date),
            attributes: attributes
        )
        // Journal the new identifier before crossing the AlarmKit write boundary.
        // If the process exits after scheduling, Undo can still find every alarm.
        persistAlarmIDs(previousIDs + [id])
        do {
            _ = try await manager.schedule(id: id, configuration: configuration)
        } catch {
            persistAlarmIDs(previousIDs)
            throw error
        }

        let activeAlarmIDs: Set<UUID>
        do {
            activeAlarmIDs = Set(try manager.alarms.map(\.id))
        } catch {
            // schedule already returned successfully, so the new alarm may be
            // live even though AlarmKit could not enumerate it for replacement
            // cleanup. Keep every journaled identifier available to Undo.
            throw AlarmServiceError.postScheduleInspectionFailed(error.localizedDescription)
        }
        var retainedIDs = [id]
        var cleanupFailures: [String] = []
        for previousID in previousIDs where activeAlarmIDs.contains(previousID) {
            do {
                try manager.cancel(id: previousID)
            } catch {
                retainedIDs.append(previousID)
                cleanupFailures.append(error.localizedDescription)
            }
        }
        persistAlarmIDs(retainedIDs)
        if !cleanupFailures.isEmpty {
            // Prefer rolling back the new alarm when an old alarm cannot be
            // removed. This avoids knowingly leaving duplicate wake alarms.
            // Keep every identifier journaled if rollback also fails so Undo
            // can retry cleanup after permissions or system state recover.
            do {
                try manager.cancel(id: id)
                persistAlarmIDs(retainedIDs.filter { $0 != id })
                throw AlarmServiceError.replacementCleanupFailed(
                    cleanupFailures.joined(separator: " ")
                )
            } catch let serviceError as AlarmServiceError {
                throw serviceError
            } catch {
                persistAlarmIDs(retainedIDs)
                throw AlarmServiceError.replacementRollbackFailed(
                    cleanupFailures.joined(separator: " "),
                    error.localizedDescription
                )
            }
        }
    }

    func hasWakeAlarm(scheduledAt date: Date) throws -> Bool {
        let trackedIDs = persistedAlarmIDs()
        guard !trackedIDs.isEmpty else { return false }
        let alarmsByID = Dictionary(uniqueKeysWithValues: try manager.alarms.map { ($0.id, $0) })
        let survivingIDs = trackedIDs.filter { alarmsByID[$0] != nil }
        // AlarmKit removes one-shot alarms after they fire and stop. Clearing only
        // missing identifiers retains edited or duplicate app-owned alarms for Undo.
        persistAlarmIDs(survivingIDs)
        guard survivingIDs.count == 1 else { return false }
        return survivingIDs.contains { id in
            guard let alarm = alarmsByID[id],
                  case .fixed(let scheduledDate) = alarm.schedule else { return false }
            return abs(scheduledDate.timeIntervalSince(date)) < 1
        }
    }

    func cancelWakeAlarm() throws {
        let trackedIDs = persistedAlarmIDs()
        guard !trackedIDs.isEmpty else { return }
        let activeAlarmIDs = Set(try manager.alarms.map(\.id))
        var retainedIDs: [UUID] = []
        var failures: [String] = []
        for id in trackedIDs where activeAlarmIDs.contains(id) {
            do {
                try manager.cancel(id: id)
            } catch {
                retainedIDs.append(id)
                failures.append(error.localizedDescription)
            }
        }
        persistAlarmIDs(retainedIDs)
        if !failures.isEmpty {
            throw AlarmServiceError.cleanupFailed(failures.joined(separator: " "))
        }
    }

    private func persistedAlarmIDs() -> [UUID] {
        let stored = (defaults.stringArray(forKey: alarmIDsKey) ?? []).compactMap(UUID.init(uuidString:))
        let legacy = defaults.string(forKey: alarmIDKey).flatMap(UUID.init(uuidString:))
        var seen: Set<UUID> = []
        return (stored + [legacy].compactMap { $0 }).filter { seen.insert($0).inserted }
    }

    private func persistAlarmIDs(_ ids: [UUID]) {
        var seen: Set<UUID> = []
        let uniqueIDs = ids.filter { seen.insert($0).inserted }
        defaults.removeObject(forKey: alarmIDKey)
        if uniqueIDs.isEmpty {
            defaults.removeObject(forKey: alarmIDsKey)
        } else {
            defaults.set(uniqueIDs.map(\.uuidString), forKey: alarmIDsKey)
        }
    }
}

enum AlarmServiceError: LocalizedError {
    case authorizationDenied
    case timeInPast
    case postScheduleInspectionFailed(String)
    case replacementCleanupFailed(String)
    case replacementRollbackFailed(String, String)
    case cleanupFailed(String)

    var mayHaveTrackedAlarm: Bool {
        switch self {
        case .postScheduleInspectionFailed, .replacementCleanupFailed, .replacementRollbackFailed:
            true
        case .authorizationDenied, .timeInPast, .cleanupFailed:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .authorizationDenied: "Alarm permission was denied. Enable it in Settings to apply a wake alarm."
        case .timeInPast: "The proposed wake time has already passed. Refresh the plan first."
        case .postScheduleInspectionFailed(let detail):
            "The new alarm may have been created, but Sleep Coach could not verify replacement cleanup. Use Undo before applying again. \(detail)"
        case .replacementCleanupFailed(let detail):
            "An older Sleep Coach alarm could not be removed, so the new alarm was rolled back. Use Undo before applying again. \(detail)"
        case .replacementRollbackFailed(let cleanupDetail, let rollbackDetail):
            "An older Sleep Coach alarm and the new replacement could not both be removed. Use Undo before applying again. \(cleanupDetail) \(rollbackDetail)"
        case .cleanupFailed(let detail):
            "One or more Sleep Coach alarms could not be removed. Try Undo again. \(detail)"
        }
    }
}
