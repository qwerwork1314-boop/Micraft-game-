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

enum AppTab: Hashable { case today, sleep, trends, coach, garden }

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if model.settings.onboarded {
            TabView(selection: $model.selectedTab) {
                DashboardView().tabItem { Label("Today", systemImage: "circle.hexagongrid.fill") }.tag(AppTab.today)
                SleepView().tabItem { Label("Sleep", systemImage: "moon.zzz.fill") }.tag(AppTab.sleep)
                TrendsView().tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }.tag(AppTab.trends)
                AssistantView().tabItem { Label("Coach", systemImage: "sparkles") }.tag(AppTab.coach)
                GardenView().tabItem { Label("Garden", systemImage: "leaf.fill") }.tag(AppTab.garden)
            }
        } else {
            OnboardingView()
        }
    }
}
