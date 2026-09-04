import AlarmKit
import Foundation
import SwiftUI

struct WakeAlarmMetadata: AlarmMetadata {
    let planGeneratedAt: Date
}

protocol AlarmScheduling {
    var authorizationLabel: String { get }
    func scheduleWakeAlarm(at date: Date) async throws
    func cancelWakeAlarm() throws
}

final class AlarmService: AlarmScheduling {
    private let manager: AlarmManager
    private let defaults: UserDefaults
    private let alarmIDKey = "sleepCoachWakeAlarmID"

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

        let previousID = defaults.string(forKey: alarmIDKey).flatMap(UUID.init(uuidString:))
        let activeAlarmIDs = Set(try manager.alarms.map(\.id))
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
        _ = try await manager.schedule(id: id, configuration: configuration)
        if let previousID, activeAlarmIDs.contains(previousID) {
            do {
                try manager.cancel(id: previousID)
            } catch {
                try? manager.cancel(id: id)
                throw error
            }
        }
        defaults.set(id.uuidString, forKey: alarmIDKey)
    }

    func cancelWakeAlarm() throws {
        guard let raw = defaults.string(forKey: alarmIDKey), let id = UUID(uuidString: raw) else { return }
        if try manager.alarms.contains(where: { $0.id == id }) {
            try manager.cancel(id: id)
        }
        defaults.removeObject(forKey: alarmIDKey)
    }
}

enum AlarmServiceError: LocalizedError {
    case authorizationDenied
    case timeInPast

    var errorDescription: String? {
        switch self {
        case .authorizationDenied: "Alarm permission was denied. Enable it in Settings to apply a wake alarm."
        case .timeInPast: "The proposed wake time has already passed. Refresh the plan first."
        }
    }
}
