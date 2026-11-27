import SwiftUI
import WatchKit
import HealthKit

/// Receives workouts and heart-rate checks started from the iPhone app
/// (`HKHealthStore.startWatchApp(with:)`), so the user never has to open the watch app.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await WorkoutManager.shared.start(configuration: workoutConfiguration)
        }
    }
}

@main
struct VitalFlowWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    @State private var model = WatchModel()
    @State private var workout = WorkoutManager.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .environment(workout)
                .onAppear {
                    model.start()
                    workout.onFinished = { [model] in
                        model.notifyPhone("workout")
                        Task { await model.refresh() }
                    }
                }
                .onChange(of: phase) { _, p in
                    if p == .active { Task { await model.refresh() } }
                }
        }
    }
}
