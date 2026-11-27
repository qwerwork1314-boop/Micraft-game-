import Foundation

public enum TrendDirection: String, Codable, Sendable {
    case improving, stable, declining, insufficient
}

public struct MetricTrend: Codable, Hashable, Sendable {
    public var metric: String
    public var currentAverage: Double?
    public var previousAverage: Double?
    public var changePercent: Double?
    public var direction: TrendDirection
}

public enum TrendAnalyzer {
    /// Whether a higher value of the metric is generally favourable for wellness.
    public static func higherIsBetter(_ metric: String) -> Bool {
        switch metric {
        case "restingHeartRate", "respiratoryRate", "stress": return false
        default: return true
        }
    }

    /// Compares the mean of the last `period` days ending on `day` with the preceding period.
    /// Each period needs ≥ ceil(period/2) values. A change < 3 % is "stable".
    public static func trend(metric: String, day: DayKey, period: Int, history: [DailyMetrics],
                             value: (DailyMetrics) -> Double?, calendar: Calendar) -> MetricTrend {
        let curStart = day.adding(days: -(period - 1), calendar: calendar)
        let prevStart = curStart.adding(days: -period, calendar: calendar)
        let cur = history.filter { $0.day >= curStart && $0.day <= day }.compactMap(value)
        let prev = history.filter { $0.day >= prevStart && $0.day < curStart }.compactMap(value)
        let need = (period + 1) / 2
        guard cur.count >= need, prev.count >= need, let c = Math.mean(cur), let p = Math.mean(prev), p != 0 else {
            return MetricTrend(metric: metric, currentAverage: Math.mean(cur), previousAverage: Math.mean(prev),
                               changePercent: nil, direction: .insufficient)
        }
        let change = (c - p) / abs(p) * 100
        let direction: TrendDirection
        if abs(change) < 3 { direction = .stable }
        else { direction = (change > 0) == higherIsBetter(metric) ? .improving : .declining }
        return MetricTrend(metric: metric, currentAverage: c, previousAverage: p, changePercent: change, direction: direction)
    }

    public static func weekly(day: DayKey, history: [DailyMetrics], calendar: Calendar) -> [MetricTrend] {
        [
            trend(metric: "hrv", day: day, period: 7, history: history, value: { $0.hrv }, calendar: calendar),
            trend(metric: "restingHeartRate", day: day, period: 7, history: history, value: { $0.restingHeartRate }, calendar: calendar),
            trend(metric: "sleep", day: day, period: 7, history: history, value: { $0.sleep?.asleep }, calendar: calendar),
            trend(metric: "steps", day: day, period: 7, history: history, value: { $0.steps }, calendar: calendar),
            trend(metric: "activeEnergy", day: day, period: 7, history: history, value: { $0.activeEnergy }, calendar: calendar),
            trend(metric: "daylight", day: day, period: 7, history: history, value: { $0.daylightMinutes }, calendar: calendar),
        ]
    }
}
