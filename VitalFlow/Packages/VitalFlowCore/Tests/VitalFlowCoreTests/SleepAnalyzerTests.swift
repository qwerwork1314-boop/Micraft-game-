import XCTest
@testable import VitalFlowCore

final class SleepAnalyzerTests: XCTestCase {
    let cal = TestCal.calendar()
    let wakeDay = DayKey(year: 2026, month: 3, day: 11)
    func d(_ h: Int, _ m: Int = 0, day: Int = 11) -> Date { TestCal.date(2026, 3, day, h, m) }

    func testStageTotalsAndInterruptions() {
        let samples = [
            SleepSample(stage: .inBed, start: d(22, 45, day: 10), end: d(7, 10), sourceID: "w", isFromWatch: true),
            SleepSample(stage: .core, start: d(23, day: 10), end: d(1), sourceID: "w", isFromWatch: true),
            SleepSample(stage: .awake, start: d(1), end: d(1, 10), sourceID: "w", isFromWatch: true),
            SleepSample(stage: .deep, start: d(1, 10), end: d(2, 10), sourceID: "w", isFromWatch: true),
            SleepSample(stage: .rem, start: d(2, 10), end: d(3, 10), sourceID: "w", isFromWatch: true),
            SleepSample(stage: .core, start: d(3, 10), end: d(7), sourceID: "w", isFromWatch: true),
            SleepSample(stage: .awake, start: d(7), end: d(7, 10), sourceID: "w", isFromWatch: true), // trailing, not an interruption
        ]
        let n = SleepAnalyzer(calendar: cal).night(for: wakeDay, samples: samples)!
        XCTAssertEqual(n.deep, 3600)
        XCTAssertEqual(n.rem, 3600)
        XCTAssertEqual(n.core, TimeInterval(21_000))
        XCTAssertEqual(n.asleep, TimeInterval(28_200))
        XCTAssertEqual(n.interruptions, 1)
        XCTAssertEqual(n.awake, 600)
        XCTAssertTrue(n.hasStageData)
        XCTAssertEqual(n.start, d(23, day: 10))
        XCTAssertEqual(n.end, d(7))
    }

    func testOverlappingSourcesNotDoubleCounted() {
        // Watch has stages; a third-party app wrote a single "asleep" block over the same night.
        let watch = [
            SleepSample(stage: .core, start: d(23, day: 10), end: d(3), sourceID: "watch", isFromWatch: true),
            SleepSample(stage: .deep, start: d(3), end: d(4), sourceID: "watch", isFromWatch: true),
            SleepSample(stage: .rem, start: d(4), end: d(6), sourceID: "watch", isFromWatch: true),
        ]
        let other = [SleepSample(stage: .asleepUnspecified, start: d(22, 30, day: 10), end: d(6, 30), sourceID: "com.other")]
        let n = SleepAnalyzer(calendar: cal).night(for: wakeDay, samples: watch + other)!
        // Watch covers 23:00–06:00 = 7 h; the other source only fills 22:30–23:00 and 06:00–06:30.
        XCTAssertEqual(n.asleep, 8 * 3600, accuracy: 1)
        XCTAssertEqual(n.deep, 3600)
        XCTAssertEqual(n.primarySourceID, "watch")
    }

    func testDuplicateSamplesIgnored() {
        let s = SleepSample(id: "dup", stage: .core, start: d(0), end: d(6), sourceID: "w")
        let n = SleepAnalyzer(calendar: cal).night(for: wakeDay, samples: [s, s, s])!
        XCTAssertEqual(n.asleep, 6 * 3600)
    }

    func testOverlappingSameSourceAwakeWins() {
        let samples = [
            SleepSample(stage: .asleepUnspecified, start: d(0), end: d(6), sourceID: "a"),
            SleepSample(stage: .awake, start: d(2), end: d(2, 30), sourceID: "a"),
        ]
        let n = SleepAnalyzer(calendar: cal).night(for: wakeDay, samples: samples)!
        XCTAssertEqual(n.asleep, 5.5 * 3600)
        XCTAssertEqual(n.interruptions, 1)
        XCTAssertFalse(n.hasStageData)
    }

    func testNapIsSeparatedFromMainSleep() {
        let samples = [
            SleepSample(stage: .core, start: d(0), end: d(6), sourceID: "a"),
            SleepSample(stage: .core, start: d(14), end: d(14, 40), sourceID: "a"),
        ]
        let n = SleepAnalyzer(calendar: cal).night(for: wakeDay, samples: samples)!
        XCTAssertEqual(n.asleep, 6 * 3600)
        XCTAssertEqual(n.napDuration, 40 * 60)
    }

    func testInBedOnlyIsNotSleep() {
        let s = SleepSample(stage: .inBed, start: d(0), end: d(7), sourceID: "phone")
        XCTAssertNil(SleepAnalyzer(calendar: cal).night(for: wakeDay, samples: [s]))
    }

    func testNoSamplesGivesNil() {
        XCTAssertNil(SleepAnalyzer(calendar: cal).night(for: wakeDay, samples: []))
    }

    func testConsistencyNeedsFourNights() {
        let h = makeHistory(end: wakeDay, days: 3, cal: cal)
        XCTAssertNil(SleepAnalyzer(calendar: cal).consistency(of: h.compactMap(\.sleep)).score)
        let h7 = makeHistory(end: wakeDay, days: 7, cal: cal)
        XCTAssertEqual(SleepAnalyzer(calendar: cal).consistency(of: h7.compactMap(\.sleep)).score, 100)
    }

    func testConsistencyAcrossMidnightWrap() {
        // Mid-sleep alternating 23:50 and 00:10 → σ ≈ 10 min, should be 100, not penalised by wrap.
        let nights: [SleepNight] = (0..<6).map { i in
            let mid = i % 2 == 0 ? TestCal.date(2026, 3, 10 + i, 23, 50) : TestCal.date(2026, 3, 11 + i, 0, 10)
            return SleepNight(wakeDay: wakeDay, segments: [], start: mid.addingTimeInterval(-3600), end: mid.addingTimeInterval(3600),
                              asleep: 7200, awake: 0, deep: 0, rem: 0, core: 7200, unspecified: 0, interruptions: 0,
                              napDuration: 0, hasStageData: true, primarySourceID: nil)
        }
        XCTAssertEqual(SleepAnalyzer(calendar: cal).consistency(of: nights).score, 100)
    }

    func testSleepScoreMissingData() {
        XCTAssertEqual(SleepScorer.score(nil, consistency: nil, profile: ScoringProfile()).missing, [.sleepLastNight])
    }

    func testSleepScoreGoodNightIsHigh() {
        let n = makeHistory(end: wakeDay, days: 1, cal: cal, sleepHours: 8).last!.sleep!
        let r = SleepScorer.score(n, consistency: 90, profile: ScoringProfile())
        XCTAssertGreaterThanOrEqual(r.score ?? 0, 90)
        XCTAssertEqual(r.confidence, .high)
    }

    func testSleepScoreShortNightIsLow() {
        let n = makeHistory(end: wakeDay, days: 1, cal: cal, sleepHours: 4.5).last!.sleep!
        XCTAssertLessThan(SleepScorer.score(n, consistency: nil, profile: ScoringProfile()).score ?? 100, 70)
    }
}
