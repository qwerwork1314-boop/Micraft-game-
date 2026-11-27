import SwiftUI

@main
struct VitalFlowWatchApp: App {
    @State private var model = WatchModel()
    @State private var workout = WorkoutManager()
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
