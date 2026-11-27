import SwiftUI
import SwiftData

@main
struct VitalFlowApp: App {
    @State private var model = AppModel()
    private let container = LocalStore.makeContainer()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Brand.emerald)
                .onAppear { model.start() }
                .onChange(of: phase) { _, p in
                    // Refresh when returning to the foreground: covers Watch→iPhone sync delays.
                    if p == .active { Task { await model.refresh() } }
                }
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.settings.onboarded {
            TabView {
                DashboardView().tabItem { Label("Today", systemImage: "circle.hexagongrid.fill") }
                SleepView().tabItem { Label("Sleep", systemImage: "moon.zzz.fill") }
                TrendsView().tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                AssistantView().tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right.fill") }
                GardenView().tabItem { Label("Garden", systemImage: "leaf.fill") }
            }
        } else {
            OnboardingView()
        }
    }
}
