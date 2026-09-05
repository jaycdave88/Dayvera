import SwiftData
import SwiftUI
import UIKit

@MainActor
final class DayveraAppDelegate: NSObject, UIApplicationDelegate {
    static weak var appModel: AppModel?
    static weak var healthService: HealthKitService?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard let appModel = Self.appModel,
              appModel.shouldPrepareHealthObservationAtLaunch,
              let healthService = Self.healthService else { return true }

        // Observer construction and store.execute happen synchronously inside
        // this delegate callback. Only enableBackgroundDelivery is asynchronous.
        _ = try? healthService.beginBackgroundDeliveryConfiguration { [weak appModel] event in
            await appModel?.handleHealthBackgroundEvent(event)
        }

        // Await the shared configuration task through AppModel so any failure is
        // surfaced consistently in the existing Apple Health status UI.
        Task { await appModel.prepareHealthObservationAtLaunch() }
        return true
    }
}

@main
struct DayveraApp: App {
    @UIApplicationDelegateAdaptor(DayveraAppDelegate.self) private var appDelegate
    @StateObject private var appModel: AppModel
    @StateObject private var nutrition = NutritionModel()

    init() {
        Self.preparePrivateLocalStorage()
        let appModel: AppModel
        let healthService: HealthKitService?
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-data") {
            healthService = nil
            appModel = AppModel(
                health: DemoHealthService(),
                calendar: DemoCalendarService(),
                alarms: DemoAlarmService(),
                demoMode: true
            )
        } else {
            let liveHealthService = HealthKitService()
            healthService = liveHealthService
            appModel = AppModel(health: liveHealthService)
        }
        #else
        let liveHealthService = HealthKitService()
        healthService = liveHealthService
        appModel = AppModel(health: liveHealthService)
        #endif
        _appModel = StateObject(wrappedValue: appModel)
        DayveraAppDelegate.appModel = appModel
        DayveraAppDelegate.healthService = healthService
    }

    private static func preparePrivateLocalStorage() {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        do {
            try FileManager.default.createDirectory(
                at: applicationSupport,
                withIntermediateDirectories: true
            )
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var protectedDirectory = applicationSupport
            try protectedDirectory.setResourceValues(resourceValues)
        } catch {
            // The app sandbox and the platform's default file protection still
            // apply. Avoid leaking a filesystem path into user-facing diagnostics.
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .environmentObject(nutrition)
        }
        .modelContainer(for: [WorkoutTemplateRecord.self, WorkoutSessionRecord.self, MealRecord.self, NutritionDayRecord.self, BodyMeasurementRecord.self, NutritionTargetRevision.self, NutritionAdjustmentRecord.self])
    }
}
