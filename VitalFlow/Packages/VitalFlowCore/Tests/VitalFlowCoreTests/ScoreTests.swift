import XCTest
@testable import VitalFlowCore

final class ScoreTests: XCTestCase {
    let cal = TestCal.calendar()
    let today = DayKey(year: 2026, month: 4, day: 15)

    // MARK: Recovery

    func testRecoveryNotEnoughDataWithEmptyHistory() {
        let r = RecoveryScorer.score(day: today, history: [], sleepScore: 80, calendar: cal)
        XCTAssertNil(r.score)
        XCTAssertTrue(r.missing.contains(.hrvToday))
        XCTAssertTrue(r.missing.contains(.hrvBaseline))
    }

    func testRecoveryNotEnoughDataWithThreeDaysOfBaseline() {
        let h = makeHistory(end: today, days: 4, cal: cal) // 3 prior days < minimum 4
        XCTAssertNil(RecoveryScorer.score(day: today, history: h, sleepScore: 80, calendar: cal).score)
    }

    func testRecoveryNeutralDayIsMidRange() {
        let h = makeHistory(end: today, days: 30, cal: cal, jitter: false)
        let r = RecoveryScorer.score(day: today, history: h, sleepScore: 70, calendar: cal)
        XCTAssertEqual(r.score ?? 0, 62, accuracy: 2)
        XCTAssertEqual(r.confidence, .high)
    }

    func testRecoveryDropsWithLowHRVAndHighRHR() {
        var h = makeHistory(end: today, days: 30, cal: cal)
        let neutral = RecoveryScorer.score(day: today, history: h, sleepScore: 75, calendar: cal).score!
        h[h.count - 1].hrv = 32
        h[h.count - 1].restingHeartRate = 63
        let bad = RecoveryScorer.score(day: today, history: h, sleepScore: 55, calendar: cal)
        XCTAssertLessThan(bad.score!, neutral - 25)
        let hrv = bad.components.first { $0.key == "hrv" }!
        XCTAssertLessThan(hrv.effect, 0)
    }

    func testRecoveryRisesWithHighHRV() {
        var h = makeHistory(end: today, days: 30, cal: cal)
        h[h.count - 1].hrv = 70
        h[h.count - 1].restingHeartRate = 52
        XCTAssertGreaterThan(RecoveryScorer.score(day: today, history: h, sleepScore: 90, calendar: cal).score!, 85)
    }

    func testRecoveryWeightsNormalised() {
        let h = makeHistory(end: today, days: 30, cal: cal)
        let r = RecoveryScorer.score(day: today, history: h, sleepScore: 75, calendar: cal)
        XCTAssertEqual(r.components.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
    }

    func testRecoveryWithoutHRVUsesRHRButNeedsEnoughWeight() {
        let h = makeHistory(end: today, days: 30, cal: cal, hrv: nil)
        // RHR (0.25) + sleep (0.20) = 0.45 → allowed, low confidence.
        let r = RecoveryScorer.score(day: today, history: h, sleepScore: 75, calendar: cal)
        XCTAssertNotNil(r.score)
        XCTAssertEqual(r.confidence, .low)
        // RHR alone = 0.25 → not enough.
        XCTAssertNil(RecoveryScorer.score(day: today, history: h, sleepScore: nil, calendar: cal).score)
    }

    func testRecoveryIsClampedForExtremes() {
        var h = makeHistory(end: today, days: 30, cal: cal)
        h[h.count - 1].hrv = 5
        h[h.count - 1].restingHeartRate = 110
        let s = RecoveryScorer.score(day: today, history: h, sleepScore: 0, calendar: cal).score!
        XCTAssertTrue((0...100).contains(s))
    }

    func testRecoveryLowConfidenceWithShortBaseline() {
        let h = makeHistory(end: today, days: 8, cal: cal)
        XCTAssertEqual(RecoveryScorer.score(day: today, history: h, sleepScore: 75, calendar: cal).confidence, .low)
    }

    // MARK: Stress

    func hrSamples(_ bpm: Double, hours: Range<Int>) -> [QuantitySample] {
        hours.flatMap { h in (0..<6).map { m in
            QuantitySample(kind: .heartRate, value: bpm, start: TestCal.date(2026, 4, 15, h, m * 10))
        } }
    }

    func testStressNotEnoughWithoutBaseline() {
        let r = StressEstimator.estimate(day: today, heartRate: hrSamples(70, hours: 8..<12), hrv: [], steps: [], workouts: [],
                                         history: [], profile: ScoringProfile(), calendar: cal, now: TestCal.date(2026, 4, 15, 20))
        XCTAssertEqual(r.result.missing, [.restingHeartRateBaseline])
    }

    func testStressCalmVsElevated() {
        let h = makeHistory(end: today, days: 20, cal: cal, jitter: false)
        let now = TestCal.date(2026, 4, 15, 20)
        let calm = StressEstimator.estimate(day: today, heartRate: hrSamples(57, hours: 8..<14), hrv: [], steps: [], workouts: [],
                                            history: h, profile: ScoringProfile(age: 35), calendar: cal, now: now)
        let tense = StressEstimator.estimate(day: today, heartRate: hrSamples(90, hours: 8..<14), hrv: [], steps: [], workouts: [],
                                             history: h, profile: ScoringProfile(age: 35), calendar: cal, now: now)
        XCTAssertLessThan(calm.result.score!, 15)
        XCTAssertGreaterThan(tense.result.score!, 60)
        XCTAssertEqual(calm.hourly.count, 6)
    }

    func testStressExcludesWorkoutAndActiveHours() {
        let h = makeHistory(end: today, days: 20, cal: cal, jitter: false)
        let w = WorkoutRecord(activity: .running, start: TestCal.date(2026, 4, 15, 9), end: TestCal.date(2026, 4, 15, 10))
        let steps = [QuantitySample(kind: .stepCount, value: 3000, start: TestCal.date(2026, 4, 15, 11), end: TestCal.date(2026, 4, 15, 12))]
        let r = StressEstimator.estimate(day: today, heartRate: hrSamples(70, hours: 8..<14), hrv: [], steps: steps, workouts: [w],
                                         history: h, profile: ScoringProfile(), calendar: cal, now: TestCal.date(2026, 4, 15, 20))
        XCTAssertEqual(r.hourly.count, 4) // 8, 10, 12, 13
    }

    func testStressIgnoresFutureHours() {
        let h = makeHistory(end: today, days: 20, cal: cal)
        let r = StressEstimator.estimate(day: today, heartRate: hrSamples(70, hours: 8..<20), hrv: [], steps: [], workouts: [],
                                         history: h, profile: ScoringProfile(), calendar: cal, now: TestCal.date(2026, 4, 15, 10, 30))
        XCTAssertEqual(r.hourly.count, 2)
        XCTAssertNil(r.result.score) // < 3 valid hours
    }

    // MARK: Body Battery

    func testBodyBatteryNotEnoughData() {
        let r = BodyBatteryEstimator.estimate(recovery: nil, sleepScore: nil, wakeTime: nil, hourlyActiveEnergy: [], hourlyStress: [],
                                              hourlySteps: [], now: Date(), calendar: cal)
        XCTAssertNil(r.result.score)
    }

    func testBodyBatteryDrainsOverDay() {
        let wake = TestCal.date(2026, 4, 15, 7)
        let energy = [(TestCal.date(2026, 4, 15, 9), 400.0)]
        let r = BodyBatteryEstimator.estimate(recovery: 80, sleepScore: 80, wakeTime: wake, hourlyActiveEnergy: energy, hourlyStress: [],
                                              hourlySteps: [], now: TestCal.date(2026, 4, 15, 17), calendar: cal)
        XCTAssertEqual(r.morningLevel, 80)
        // 10 h × 2 + 400 × 0.04 = 36 → 44
        XCTAssertEqual(r.result.score, 44)
        XCTAssertEqual(r.timeline.first?.level, 80)
    }

    func testBodyBatteryNeverNegative() {
        let r = BodyBatteryEstimator.estimate(recovery: 10, sleepScore: nil, wakeTime: TestCal.date(2026, 4, 15, 5),
                                              hourlyActiveEnergy: [(TestCal.date(2026, 4, 15, 8), 3000)], hourlyStress: [],
                                              hourlySteps: [], now: TestCal.date(2026, 4, 15, 23), calendar: cal)
        XCTAssertEqual(r.result.score, 0)
    }

    // MARK: Training

    func testTRIMPIncreasesWithIntensity() {
        let s = TestCal.date(2026, 4, 15, 8)
        let easy = WorkoutRecord(activity: .running, start: s, end: s.addingTimeInterval(3600), averageHeartRate: 120)
        let hard = WorkoutRecord(activity: .running, start: s, end: s.addingTimeInterval(3600), averageHeartRate: 165)
        let p = ScoringProfile(age: 30)
        XCTAssertGreaterThan(TrainingLoad.load(of: hard, restingHR: 55, profile: p), TrainingLoad.load(of: easy, restingHR: 55, profile: p) * 1.5)
    }

    func testDuplicateWorkoutsCountedOnce() {
        let s = TestCal.date(2026, 4, 15, 8)
        let w = WorkoutRecord(id: "w1", activity: .cycling, start: s, end: s.addingTimeInterval(1800), activeEnergy: 240)
        XCTAssertEqual(TrainingLoad.dailyLoad(day: today, workouts: [w, w], restingHR: nil, profile: ScoringProfile(), calendar: cal), 30)
    }

    func testACWRNeedsTwoWeeks() {
        let h = makeHistory(end: today, days: 10, cal: cal)
        XCTAssertNil(ReadinessCalculator.acwr(day: today, history: h, calendar: cal))
        let h2 = makeHistory(end: today, days: 28, cal: cal, jitter: false)
        XCTAssertEqual(ReadinessCalculator.acwr(day: today, history: h2, calendar: cal)!.acwr, 1, accuracy: 1e-9)
    }

    func testReadinessLevels() {
        let h = makeHistory(end: today, days: 28, cal: cal, jitter: false)
        let r = ReadinessCalculator.readiness(day: today, recovery: .value(90, confidence: .high, components: []), history: h, calendar: cal)
        XCTAssertEqual(r.level, .prime)
        XCTAssertEqual(r.zone, .optimal)
        let low = ReadinessCalculator.readiness(day: today, recovery: .value(10, confidence: .high, components: []), history: h, calendar: cal)
        XCTAssertEqual(low.level, .easy) // 0.65·10 + 0.35·100 = 41.5
        XCTAssertNil(ReadinessCalculator.readiness(day: today, recovery: .notEnoughData(missing: []), history: h, calendar: cal).result.score)
    }

    func testACWRZones() {
        XCTAssertEqual(ReadinessCalculator.zone(0.5), .underTraining)
        XCTAssertEqual(ReadinessCalculator.zone(1.0), .optimal)
        XCTAssertEqual(ReadinessCalculator.zone(1.4), .high)
        XCTAssertEqual(ReadinessCalculator.zone(1.9), .veryHigh)
    }

    func testBalance() {
        XCTAssertEqual(BalanceCalculator.balance(recovery: 30, activityLoad: 80), .overreaching)
        XCTAssertEqual(BalanceCalculator.balance(recovery: 30, activityLoad: 20), .restDay)
        XCTAssertEqual(BalanceCalculator.balance(recovery: 90, activityLoad: 20), .roomToPush)
        XCTAssertEqual(BalanceCalculator.balance(recovery: 60, activityLoad: 55), .balanced)
        XCTAssertNil(BalanceCalculator.balance(recovery: nil, activityLoad: 50))
    }

    // MARK: Trends

    func testTrendDirectionRespectsMetricSemantics() {
        var h = makeHistory(end: today, days: 14, cal: cal, jitter: false)
        for i in 7..<14 { h[i].restingHeartRate = 60 } // RHR rose → declining
        let t = TrendAnalyzer.trend(metric: "restingHeartRate", day: today, period: 7, history: h, value: { $0.restingHeartRate }, calendar: cal)
        XCTAssertEqual(t.direction, .declining)
        let s = TrendAnalyzer.trend(metric: "steps", day: today, period: 7, history: h, value: { $0.steps }, calendar: cal)
        XCTAssertEqual(s.direction, .stable)
    }

    func testTrendInsufficient() {
        let h = makeHistory(end: today, days: 5, cal: cal)
        XCTAssertEqual(TrendAnalyzer.trend(metric: "hrv", day: today, period: 7, history: h, value: { $0.hrv }, calendar: cal).direction, .insufficient)
    }
}
