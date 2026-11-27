import XCTest
@testable import VitalFlowCore

final class GamificationTests: XCTestCase {
    let cal = TestCal.calendar()
    let end = DayKey(year: 2026, month: 5, day: 31)

    func testGoalTargetsClampedToHealthyRange() {
        var g = GoalSet()
        g.setTarget(100_000, for: .steps)
        XCTAssertEqual(g.target(for: .steps), 20_000)
        g.setTarget(3, for: .sleepHours)
        XCTAssertEqual(g.target(for: .sleepHours), 6)
        g.setTarget(5000, for: .activeEnergy)
        XCTAssertEqual(g.target(for: .activeEnergy), 900)
    }

    func testMissingMetricIsNotCompleted() {
        let g = GoalSet()
        XCTAssertEqual(g.completed(metrics: DailyMetrics(day: end)), [])
    }

    func testGardenGrowsAndNeverShrinks() {
        let g = GoalSet(enabled: [.steps, .sleepHours])
        var h = makeHistory(end: end, days: 10, cal: cal, sleepHours: 8)
        let full = Garden.build(history: h, goals: g)
        XCTAssertEqual(full.totalGrowth, 20)
        XCTAssertEqual(full.currentStreak, 10)
        h[9].steps = 100; h[9].sleep = nil  // a missed day
        let after = Garden.build(history: h, goals: g)
        XCTAssertEqual(after.totalGrowth, 18)
        XCTAssertEqual(after.currentStreak, 0)
        XCTAssertEqual(after.bestStreak, 9)
        XCTAssertFalse(after.plants.isEmpty) // plants rest, they don't die
    }

    func testGardenPlantsMatureIntoTrees() {
        let g = GoalSet(enabled: [.steps])
        let h = makeHistory(end: end, days: 20, cal: cal)
        let s = Garden.build(history: h, goals: g)
        XCTAssertEqual(s.plants.count, 2) // 18 points → tree, then a new seed
        XCTAssertEqual(s.plants[0].stage, .tree)
        XCTAssertEqual(AchievementEvaluator.unlocked(history: h, goals: g).contains(.firstTree), true)
    }

    func testReport() {
        let h = makeHistory(end: end, days: 14, cal: cal, sleepHours: 7)
        let r = ReportBuilder.report(history: h, goals: GoalSet(), end: end, days: 7, calendar: cal)
        XCTAssertEqual(r.daysWithData, 7)
        XCTAssertEqual(r.averageSleepHours ?? 0, 7, accuracy: 0.001)
    }
}

final class AssistantTests: XCTestCase {
    let cal = TestCal.calendar()

    func testIntentClassificationEnglish() {
        XCTAssertEqual(WellnessAssistant.classify("Why is my recovery score lower today?"), .recoveryWhy)
        XCTAssertEqual(WellnessAssistant.classify("How well did I sleep last night?"), .sleepLastNight)
        XCTAssertEqual(WellnessAssistant.classify("How has my resting heart rate changed this month?"), .restingHRTrend)
        XCTAssertEqual(WellnessAssistant.classify("What is my current activity and recovery balance?"), .activityBalance)
    }

    func testIntentClassificationChinese() {
        XCTAssertEqual(WellnessAssistant.classify("为什么我今天的恢复分数较低？"), .recoveryWhy)
        XCTAssertEqual(WellnessAssistant.classify("我昨晚睡得怎麼樣？"), .sleepLastNight)
        XCTAssertEqual(WellnessAssistant.classify("這個月我的靜息心率有什麼變化？"), .restingHRTrend)
    }

    func testMedicalQuestionsAreDeclined() {
        XCTAssertEqual(WellnessAssistant.classify("Do I have a heart disease? What medication should I take?"), .medical)
        XCTAssertEqual(WellnessAssistant.classify("我需要吃什么药"), .medical)
        let a = WellnessAssistant(language: .english).answer("Can you diagnose me?", context: AssistantContext(today: nil, history: [], calendar: cal))
        XCTAssertTrue(a.contains("can't diagnose"))
    }

    func testNotEnoughDataAnswer() {
        let a = WellnessAssistant(language: .simplifiedChinese).answer("恢复", context: AssistantContext(today: nil, history: [], calendar: cal))
        XCTAssertTrue(a.contains("数据还不够"))
    }

    func testLanguageMapping() {
        XCTAssertEqual(AssistantLanguage.from(localeIdentifier: "zh-Hant-TW"), .traditionalChinese)
        XCTAssertEqual(AssistantLanguage.from(localeIdentifier: "zh_HK"), .traditionalChinese)
        XCTAssertEqual(AssistantLanguage.from(localeIdentifier: "zh-Hans-CN"), .simplifiedChinese)
        XCTAssertEqual(AssistantLanguage.from(localeIdentifier: "en-GB"), .english)
    }

    func testEndToEndWithDemoData() {
        let now = TestCal.date(2026, 6, 1, 18)
        let ds = DemoDataGenerator.generate(days: 45, endingAt: now, calendar: cal)
        let today = DayKey(now, calendar: cal)
        let days = (0..<45).map { today.adding(days: -44 + $0, calendar: cal) }
        let profile = ScoringProfile(age: 32)
        let history = DailyAggregator(calendar: cal).aggregate(days: days, quantities: ds.quantities, sleep: ds.sleep, workouts: ds.workouts, profile: profile)
        let start = today.startDate(in: cal)
        let intraday = IntradayData(heartRate: ds.quantities.filter { $0.kind == .heartRate && $0.start >= start },
                                    hrv: ds.quantities.filter { $0.kind == .hrvSDNN && $0.start >= start },
                                    steps: ds.quantities.filter { $0.kind == .stepCount && $0.start >= start },
                                    activeEnergy: ds.quantities.filter { $0.kind == .activeEnergy && $0.start >= start },
                                    workouts: ds.workouts.filter { $0.start >= start })
        let a = WellnessEngine(calendar: cal, profile: profile).assess(day: today, history: history, intraday: intraday, now: now, isDemo: true)
        XCTAssertNotNil(a.recovery.score)
        XCTAssertNotNil(a.sleepScore.score)
        XCTAssertNotNil(a.stress.result.score)
        XCTAssertNotNil(a.bodyBattery.result.score)
        XCTAssertNotNil(a.readiness.result.score)
        XCTAssertTrue(a.isDemo)
        for q in ["Why is my recovery score lower today?", "How well did I sleep last night?",
                  "How has my resting heart rate changed this month?", "What is my current activity and recovery balance?"] {
            let ans = WellnessAssistant(language: .english).answer(q, context: AssistantContext(today: a, history: history, calendar: cal))
            XCTAssertFalse(ans.contains("Not enough data"), q + " → " + ans)
        }
        // The minimized external payload must not contain raw timestamps or identifiers.
        let json = String(data: try! JSONEncoder().encode(MinimizedHealthSummary.from(a)), encoding: .utf8)!
        XCTAssertFalse(json.contains(DemoDataGenerator.sourceID))
        XCTAssertFalse(json.contains("2026"))
    }

    func testDemoDataIsDeterministic() {
        let now = TestCal.date(2026, 6, 1, 18)
        let a = DemoDataGenerator.generate(days: 5, endingAt: now, calendar: cal, seed: 7)
        let b = DemoDataGenerator.generate(days: 5, endingAt: now, calendar: cal, seed: 7)
        XCTAssertEqual(a.quantities.map(\.value), b.quantities.map(\.value))
        XCTAssertTrue(a.quantities.allSatisfy { $0.start <= now })
    }
}

final class PerformanceTests: XCTestCase {
    /// The app aggregates a full year (365 days) on refresh; keep it fast.
    func testYearOfDemoDataAggregatesQuickly() {
        let cal = TestCal.calendar()
        let now = TestCal.date(2026, 6, 1, 18)
        let ds = DemoDataGenerator.generate(days: 366, endingAt: now, calendar: cal)
        let today = DayKey(now, calendar: cal)
        let days = (0..<365).map { today.adding(days: -364 + $0, calendar: cal) }
        let start = Date()
        let h = DailyAggregator(calendar: cal).aggregate(days: days, quantities: ds.quantities, sleep: ds.sleep,
                                                         workouts: ds.workouts, profile: ScoringProfile())
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(h.count, 365)
        XCTAssertGreaterThan(h.compactMap(\.sleep).count, 350)
        XCTAssertLessThan(elapsed, 20, "debug build aggregation took \(elapsed)s")
        print("Aggregated 365 days in \(elapsed)s")
    }
}

final class CoachToolkitTests: XCTestCase {
    let cal = TestCal.calendar()

    func makeToolkit(demo: Bool = true) -> CoachToolkit {
        let now = TestCal.date(2026, 6, 1, 18)
        let ds = DemoDataGenerator.generate(days: 61, endingAt: now, calendar: cal)
        let today = DayKey(now, calendar: cal)
        let days = (0..<60).map { today.adding(days: -59 + $0, calendar: cal) }
        let history = DailyAggregator(calendar: cal).aggregate(days: days, quantities: ds.quantities, sleep: ds.sleep,
                                                               workouts: ds.workouts, profile: ScoringProfile())
        let start = today.startDate(in: cal)
        let intraday = IntradayData(heartRate: ds.quantities.filter { $0.kind == .heartRate && $0.start >= start },
                                    steps: ds.quantities.filter { $0.kind == .stepCount && $0.start >= start },
                                    workouts: ds.workouts.filter { $0.start >= start })
        let a = WellnessEngine(calendar: cal, profile: ScoringProfile()).assess(day: today, history: history, intraday: intraday, now: now, isDemo: demo)
        return CoachToolkit(assessment: a, history: history, workouts: ds.workouts, goals: GoalSet(), calendar: cal, isDemo: demo)
    }

    func testTodaySummaryContainsScoresAndDemoNote() {
        let t = makeToolkit().todaySummary()
        XCTAssertTrue(t.contains("DEMO"))
        XCTAssertTrue(t.contains("Recovery: "))
        XCTAssertTrue(t.contains("/100"))
        XCTAssertTrue(t.contains("personal baseline"))
    }

    func testRealDataHasNoDemoNote() {
        XCTAssertFalse(makeToolkit(demo: false).todaySummary().contains("DEMO"))
    }

    func testSleepAndTrendAndWorkouts() {
        let k = makeToolkit()
        XCTAssertTrue(k.sleepSummary(nightsAgo: 0).contains("asleep"))
        XCTAssertTrue(k.sleepSummary(nightsAgo: 500).contains("No sleep data"))
        let tr = k.trendSummary(metric: "restingHeartRate", days: 30)
        XCTAssertTrue(tr.contains("average"))
        XCTAssertTrue(tr.contains("lower is generally favourable"))
        XCTAssertTrue(k.trendSummary(metric: "nonsense", days: 30).contains("Unknown metric"))
        XCTAssertTrue(k.workoutsSummary(days: 30).contains("workouts in the last"))
        XCTAssertTrue(k.goalsSummary().contains("Garden"))
        XCTAssertTrue(k.hasRecentData)
    }

    func testEmptyDataSaysNotEnough() {
        let k = CoachToolkit(assessment: nil, history: [], workouts: [], goals: GoalSet(), calendar: cal, isDemo: false)
        XCTAssertTrue(k.todaySummary().contains("No data"))
        XCTAssertTrue(k.trendSummary(metric: "hrv", days: 30).contains("not enough data"))
        XCTAssertTrue(k.workoutsSummary(days: 7).contains("No workouts"))
        XCTAssertFalse(k.hasRecentData)
    }

    func testBriefingContextIsCompact() {
        // Must fit comfortably in a small on-device context window (~4k tokens).
        XCTAssertLessThan(makeToolkit().briefingContext().count, 3_000)
    }
}
