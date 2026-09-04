import SwiftData
import SwiftUI

@main
struct SleepCoachApp: App {
    @StateObject private var appModel: AppModel

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-data") {
            _appModel = StateObject(wrappedValue: AppModel(
                health: DemoHealthService(),
                calendar: DemoCalendarService(),
                alarms: DemoAlarmService(),
                demoMode: true
            ))
        } else {
            _appModel = StateObject(wrappedValue: AppModel())
        }
        #else
        _appModel = StateObject(wrappedValue: AppModel())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
        }
        .modelContainer(for: [WorkoutTemplateRecord.self, WorkoutSessionRecord.self])
    }
}
