import Foundation
@testable import VitalFlowCore

enum TestCal {
    static func calendar(_ tz: String = "Asia/Shanghai") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz)!
        return c
    }

    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, cal: Calendar = calendar()) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }
}

/// Builds a simple history of `days` days ending on `end` with stable values.
func makeHistory(end: DayKey, days: Int, cal: Calendar,
                 hrv: Double? = 50, rhr: Double? = 55, sleepHours: Double? = 7.5,
                 jitter: Bool = true) -> [DailyMetrics] {
    (0..<days).map { i -> DailyMetrics in
        let day = end.adding(days: -(days - 1 - i), calendar: cal)
        var m = DailyMetrics(day: day)
        let j = jitter ? Double((i * 7) % 5) - 2 : 0 // deterministic −2…+2
        m.hrv = hrv.map { $0 + j }
        m.restingHeartRate = rhr.map { $0 + j * 0.5 }
        if let sleepHours {
            let start = day.startDate(in: cal).addingTimeInterval(-3600)
            let asleep = sleepHours * 3600
            m.sleep = SleepNight(wakeDay: day, segments: [], start: start, end: start.addingTimeInterval(asleep + 1200),
                                 asleep: asleep, awake: 1200, deep: asleep * 0.18, rem: asleep * 0.22, core: asleep * 0.60,
                                 unspecified: 0, interruptions: 1, napDuration: 0, hasStageData: true, primarySourceID: "w")
        }
        m.steps = 9000 + j * 100
        m.trainingLoad = 40 + j * 5
        return m
    }
}
