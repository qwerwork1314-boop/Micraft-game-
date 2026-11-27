import XCTest
@testable import VitalFlowCore

final class DateBoundaryTests: XCTestCase {
    func testCumulativeSampleSplitAcrossMidnight() {
        let cal = TestCal.calendar()
        let s = QuantitySample(kind: .stepCount, value: 600, start: TestCal.date(2026, 3, 10, 23, 30), end: TestCal.date(2026, 3, 11, 0, 30))
        let d1 = DayKey(year: 2026, month: 3, day: 10), d2 = DayKey(year: 2026, month: 3, day: 11)
        let totals = DailyAggregator(calendar: cal).cumulativeTotals([s], days: [d1, d2])
        XCTAssertEqual(totals[d1] ?? 0, 300, accuracy: 0.001)
        XCTAssertEqual(totals[d2] ?? 0, 300, accuracy: 0.001)
    }

    func testDSTSpringForwardDayIs23Hours() {
        let cal = TestCal.calendar("America/New_York")
        let day = DayKey(year: 2026, month: 3, day: 8) // US DST starts
        let len = day.endDate(in: cal).timeIntervalSince(day.startDate(in: cal))
        XCTAssertEqual(len, 23 * 3600)
        XCTAssertEqual(day.adding(days: 1, calendar: cal), DayKey(year: 2026, month: 3, day: 9))
    }

    func testDSTFallBackDayIs25Hours() {
        let cal = TestCal.calendar("America/New_York")
        let day = DayKey(year: 2026, month: 11, day: 1)
        XCTAssertEqual(day.endDate(in: cal).timeIntervalSince(day.startDate(in: cal)), 25 * 3600)
    }

    func testDayKeyAddingAcrossMonthAndYear() {
        let cal = TestCal.calendar()
        XCTAssertEqual(DayKey(year: 2026, month: 12, day: 31).adding(days: 1, calendar: cal), DayKey(year: 2027, month: 1, day: 1))
        XCTAssertEqual(DayKey(year: 2028, month: 3, day: 1).adding(days: -1, calendar: cal), DayKey(year: 2028, month: 2, day: 29))
    }

    func testSleepAttributedToWakeDay() {
        let cal = TestCal.calendar()
        let s = SleepSample(stage: .core, start: TestCal.date(2026, 3, 10, 23), end: TestCal.date(2026, 3, 11, 7))
        let a = SleepAnalyzer(calendar: cal)
        XCTAssertNotNil(a.night(for: DayKey(year: 2026, month: 3, day: 11), samples: [s]))
        XCTAssertNil(a.night(for: DayKey(year: 2026, month: 3, day: 10), samples: [s]))
    }

    func testBaselineExcludesToday() {
        let cal = TestCal.calendar()
        let end = DayKey(year: 2026, month: 3, day: 20)
        var h = makeHistory(end: end, days: 10, cal: cal, jitter: false)
        h[h.count - 1].restingHeartRate = 90 // today's outlier must not shift the baseline
        let b = BaselineCalculator.restingHR(for: end, history: h, calendar: cal)
        XCTAssertEqual(b?.median ?? 0, 55, accuracy: 0.001)
        XCTAssertEqual(b?.sampleDays, 9)
    }

    func testBaselineWindowIs28Days() {
        let cal = TestCal.calendar()
        let end = DayKey(year: 2026, month: 3, day: 31)
        let h = makeHistory(end: end, days: 60, cal: cal)
        XCTAssertEqual(BaselineCalculator.restingHR(for: end, history: h, calendar: cal)?.sampleDays, 28)
    }
}
