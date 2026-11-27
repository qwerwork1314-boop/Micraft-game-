import Foundation
import SwiftUI
import SwiftData
import WidgetKit
import UIKit
import VitalFlowCore

/// User preferences (not health data). Stored in UserDefaults.
struct UserSettings: Codable, Equatable {
    var onboarded = false
    var demoMode = false
    var goals = GoalSet()
    var sleepNeedHours: Double = 8
    var hydrationReminders = false
    var bedtimeReminder = false
    var bedtimeHour = 22
    var bedtimeMinute = 30
    var externalAssistantEnabled = false
    var externalConsentVersion: Int?
    var externalConsentDate: Date?
    /// nil/false = the Apple Intelligence coach is used when available (optional so older
    /// saved settings still decode).
    var appleIntelligenceCoachDisabled: Bool?

    var useAppleIntelligence: Bool { appleIntelligenceCoachDisabled != true }

    static let currentConsentVersion = 1
    static let key = "vf.settings.v1"

    static func load() -> UserSettings {
        guard let d = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(UserSettings.self, from: d) else { return UserSettings() }
        return s
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    var hasValidExternalConsent: Bool {
        externalAssistantEnabled && externalConsentVersion == Self.currentConsentVersion
    }
}

@MainActor
@Observable
final class AppModel {
    var settings = UserSettings.load() { didSet { settings.save() } }
    var bundle: HealthDataBundle?
    var assessment: DailyAssessment?
    var isLoading = false
    var lastError: String?
    var healthAvailable = HealthKitService.shared.isAvailable
    var age: Int?
    /// Error from the last HealthKit authorization request (e.g. missing entitlement on a
    /// sideloaded build). Shown on the Health connection screen.
    var healthAuthError: String?
    var selectedTab: AppTab = .today
    /// A question another screen asked the Coach to answer (e.g. "Ask Coach" on a score).
    var pendingCoachQuestion: String?
    var aiBriefing: String?
    var aiBriefingLoading = false
    private var aiBriefingKey: String?

    let calendar = Calendar.current
    let historyDays = 365

    var profile: ScoringProfile { ScoringProfile(sleepNeed: settings.sleepNeedHours * 3600, age: age) }
    var history: [DailyMetrics] { bundle?.history ?? [] }
    var isDemo: Bool { bundle?.isDemo ?? settings.demoMode }
    /// Follows the language the app UI is actually shown in (including the per-app language
    /// chosen in iOS Settings), so Coach answers match the rest of the interface.
    var language: AssistantLanguage {
        AssistantLanguage.from(localeIdentifier: Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en")
    }

    private var provider: HealthDataProvider {
        settings.demoMode ? DemoDataProvider() : HealthKitDataProvider()
    }

    func start() {
        PhoneConnectivity.shared.activate(model: self)
        if !settings.demoMode {
            HealthKitService.shared.observeChanges { [weak self] in
                Task { @MainActor in await self?.refresh() }
            }
        }
        Task { await refresh() }
    }

    func requestHealthAccess() async {
        do {
            try await HealthKitService.shared.requestAuthorization()
            healthAuthError = nil
        } catch {
            healthAuthError = error.localizedDescription
            lastError = error.localizedDescription
        }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if !settings.demoMode { age = HealthKitService.shared.age() }
        let now = Date()
        let b = await provider.load(days: historyDays, now: now, calendar: calendar, profile: profile)
        bundle = b
        let a = WellnessEngine(calendar: calendar, profile: profile)
            .assess(day: DayKey(now, calendar: calendar), history: b.history, intraday: b.intraday, now: now, isDemo: b.isDemo)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { assessment = a }
        publishSnapshot()
        AICoach.shared.update(coachToolkit)
        Task { await refreshBriefing() }
    }

    // MARK: AI

    var coachToolkit: CoachToolkit {
        CoachToolkit(assessment: assessment, history: history, workouts: bundle?.workouts ?? [],
                     goals: settings.goals, calendar: calendar, isDemo: isDemo)
    }

    /// True when real (non-demo) Health data was found in the last 7 days.
    var hasRecentHealthData: Bool { coachToolkit.hasRecentData }

    var aiAvailable: Bool { settings.useAppleIntelligence && AICoach.shared.availability == .available }

    /// Generates the on-device AI briefing at most once per day per data state.
    func refreshBriefing(force: Bool = false) async {
        guard aiAvailable, let a = assessment, isDemo || hasRecentHealthData else { aiBriefing = nil; return }
        let key = "\(a.day)-\(a.recovery.score ?? -1)-\(a.sleepScore.score ?? -1)-\(isDemo)-\(language.rawValue)"
        guard force || key != aiBriefingKey, !aiBriefingLoading else { return }
        aiBriefingLoading = true
        defer { aiBriefingLoading = false }
        do {
            let text = try await AICoach.shared.briefing(toolkit: coachToolkit, language: language)
            withAnimation(.easeInOut) { aiBriefing = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            aiBriefingKey = key
        } catch {
            aiBriefing = nil
        }
    }

    func askCoach(_ question: String) {
        pendingCoachQuestion = question
        selectedTab = .coach
    }

    func setDemoMode(_ on: Bool) {
        settings.demoMode = on
        bundle = nil
        assessment = nil
        Task { await refresh() }
    }

    // MARK: Hydration

    func logWater(_ ml: Double) async {
        if settings.demoMode {
            // Demo only: adjust the in-memory value; never written to Health.
            if var b = bundle, let i = b.history.indices.last {
                b.history[i].waterML = (b.history[i].waterML ?? 0) + ml
                bundle = b
                assessment?.metrics.waterML = b.history[i].waterML
            }
        } else {
            do {
                try await HealthKitService.shared.logWater(milliliters: ml)
            } catch {
                lastError = String(localized: "Couldn't save to Health. Check VitalFlow's write permission in the Health app.")
                return
            }
            await refresh()
        }
        publishSnapshot()
    }

    // MARK: Goals / garden

    var garden: GardenState { Garden.build(history: history, goals: settings.goals) }
    var achievements: Set<Achievement> { AchievementEvaluator.unlocked(history: history, goals: settings.goals) }

    func persistDailyScores(context: ModelContext) {
        guard let a = assessment, UIApplication.shared.isProtectedDataAvailable else { return }
        let key = a.day.description
        let completed = settings.goals.completed(metrics: a.metrics).count
        let existing = try? context.fetch(FetchDescriptor<DailyScoreRecord>(predicate: #Predicate { $0.dayKey == key })).first
        if let r = existing {
            r.recovery = a.recovery.score; r.sleepScore = a.sleepScore.score; r.stress = a.stress.result.score
            r.bodyBattery = a.bodyBattery.result.score; r.readiness = a.readiness.result.score
            r.goalsCompleted = completed; r.isDemo = a.isDemo; r.updatedAt = Date()
        } else {
            context.insert(DailyScoreRecord(dayKey: key, recovery: a.recovery.score, sleepScore: a.sleepScore.score,
                                            stress: a.stress.result.score, bodyBattery: a.bodyBattery.result.score,
                                            readiness: a.readiness.result.score, goalsCompleted: completed, isDemo: a.isDemo))
        }
        let known = Set(((try? context.fetch(FetchDescriptor<AchievementRecord>())) ?? []).map(\.key))
        for ach in achievements where !known.contains(ach.rawValue) {
            context.insert(AchievementRecord(key: ach.rawValue))
        }
        try? context.save()
    }

    // MARK: Snapshot for widgets + watch

    func makeSnapshot() -> WidgetSnapshot {
        let g = settings.goals
        guard let a = assessment else { return .empty }
        return WidgetSnapshot(
            generatedAt: a.generatedAt, recovery: a.recovery.score, bodyBattery: a.bodyBattery.result.score,
            stress: a.stress.result.score, sleepScore: a.sleepScore.score,
            sleepMinutes: a.metrics.sleep.map { Int($0.asleep / 60) },
            restingHR: a.metrics.restingHeartRate.map { Int($0.rounded()) },
            latestHR: a.latestHeartRate.map { Int($0.rounded()) },
            steps: a.metrics.steps.map { Int($0) }, stepGoal: Int(g.target(for: .steps)),
            activeEnergy: a.metrics.activeEnergy.map { Int($0) }, energyGoal: Int(g.target(for: .activeEnergy)),
            exerciseMinutes: a.metrics.exerciseMinutes.map { Int($0) }, exerciseGoal: Int(g.target(for: .exerciseMinutes)),
            waterML: Int(a.metrics.waterML ?? 0), waterGoal: Int(g.target(for: .waterML)),
            readinessLevel: a.readiness.level?.rawValue, isDemo: a.isDemo)
    }

    func publishSnapshot() {
        let s = makeSnapshot()
        SnapshotStore.save(s)
        WidgetCenter.shared.reloadAllTimelines()
        PhoneConnectivity.shared.send(snapshot: s)
    }

    // MARK: Privacy

    func deleteAllLocalData(context: ModelContext) {
        LocalStore.deleteAll(in: context)
        SnapshotStore.clear()
        Keychain.delete(ExternalAssistant.keychainAccount)
        UserDefaults.standard.removeObject(forKey: UserSettings.key)
        ReminderScheduler.cancelAll()
        WidgetCenter.shared.reloadAllTimelines()
        PhoneConnectivity.shared.send(snapshot: .empty)
        settings = UserSettings()
        bundle = nil
        assessment = nil
    }
}
