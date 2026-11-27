import Foundation

/// Robust personal baseline for one metric.
public struct Baseline: Codable, Hashable, Sendable {
    public var median: Double
    /// Robust spread (1.4826 × MAD) floored by a metric-specific minimum so that a very
    /// stable history doesn't turn tiny changes into huge z-scores.
    public var spread: Double
    public var sampleDays: Int

    public init(median: Double, spread: Double, sampleDays: Int) {
        self.median = median
        self.spread = spread
        self.sampleDays = sampleDays
    }

    public func z(_ value: Double) -> Double { (value - median) / spread }

    public var confidence: Confidence {
        switch sampleDays {
        case ..<14: return .low
        case 14..<21: return .medium
        default: return .high
        }
    }
}

public enum BaselineCalculator {
    /// Minimum number of days with a measurement before a baseline is considered valid.
    public static let minimumDays = 4
    /// Rolling window length in days (today excluded).
    public static let windowDays = 28

    /// Builds a baseline from the days strictly before `day` within the window.
    /// - Parameters:
    ///   - transform: applied before statistics (e.g. `log` for HRV, which is log-normal).
    ///   - minSpread: floor for the spread, in transformed units.
    public static func baseline(for day: DayKey,
                                history: [DailyMetrics],
                                value: (DailyMetrics) -> Double?,
                                transform: (Double) -> Double = { $0 },
                                minSpread: Double,
                                calendar: Calendar) -> Baseline? {
        let earliest = day.adding(days: -windowDays, calendar: calendar)
        let values = history
            .filter { $0.day < day && $0.day >= earliest }
            .compactMap(value)
            .filter { $0.isFinite && $0 > 0 }
            .map(transform)
        guard values.count >= minimumDays, let med = Math.median(values) else { return nil }
        let spread = max(Math.robustSD(values) ?? 0, minSpread)
        return Baseline(median: med, spread: spread, sampleDays: values.count)
    }

    public static func hrv(for day: DayKey, history: [DailyMetrics], calendar: Calendar) -> Baseline? {
        // log-space spread floor ≈ 6 %
        baseline(for: day, history: history, value: { $0.hrv }, transform: { log($0) }, minSpread: 0.06, calendar: calendar)
    }

    public static func restingHR(for day: DayKey, history: [DailyMetrics], calendar: Calendar) -> Baseline? {
        baseline(for: day, history: history, value: { $0.restingHeartRate }, minSpread: 1.5, calendar: calendar)
    }

    public static func respiratory(for day: DayKey, history: [DailyMetrics], calendar: Calendar) -> Baseline? {
        baseline(for: day, history: history, value: { $0.respiratoryRate }, minSpread: 0.5, calendar: calendar)
    }

    public static func wristTemperature(for day: DayKey, history: [DailyMetrics], calendar: Calendar) -> Baseline? {
        baseline(for: day, history: history, value: { $0.wristTemperature }, minSpread: 0.15, calendar: calendar)
    }

    public static func sleepDuration(for day: DayKey, history: [DailyMetrics], calendar: Calendar) -> Baseline? {
        baseline(for: day, history: history, value: { $0.sleep?.asleep }, minSpread: 1_200, calendar: calendar)
    }
}
