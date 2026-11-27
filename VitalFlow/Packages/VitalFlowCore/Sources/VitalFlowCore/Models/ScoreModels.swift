import Foundation

public enum Confidence: String, Codable, Comparable, Sendable {
    case low, medium, high

    private var rank: Int {
        switch self { case .low: 0; case .medium: 1; case .high: 2 }
    }
    public static func < (a: Confidence, b: Confidence) -> Bool { a.rank < b.rank }
}

/// What a score still needs before it can be computed. Shown to the user next to "Not enough data".
public enum DataRequirement: String, Codable, Hashable, Sendable, CaseIterable {
    case hrvToday, hrvBaseline, restingHeartRateToday, restingHeartRateBaseline
    case sleepLastNight, heartRateToday, trainingHistory, recoveryScore, sleepHistory
}

/// One explainable input of a score.
public struct ScoreComponent: Codable, Hashable, Sendable, Identifiable {
    public var id: String { key }
    /// Stable key (e.g. "hrv"), localised by the UI.
    public var key: String
    /// Measured value for today, in the metric's natural unit.
    public var value: Double?
    /// Personal baseline (median) when relevant.
    public var baseline: Double?
    /// Standardised deviation; positive is always "better for recovery".
    public var effect: Double
    /// Relative weight used in the final score (sums to 1 across used components).
    public var weight: Double

    public init(key: String, value: Double?, baseline: Double?, effect: Double, weight: Double) {
        self.key = key
        self.value = value
        self.baseline = baseline
        self.effect = effect
        self.weight = weight
    }
}

/// The result of every VitalFlow wellness estimate.
public enum ScoreResult: Codable, Hashable, Sendable {
    case value(Int, confidence: Confidence, components: [ScoreComponent])
    case notEnoughData(missing: [DataRequirement])

    public var score: Int? {
        if case let .value(v, _, _) = self { return v }
        return nil
    }

    public var confidence: Confidence? {
        if case let .value(_, c, _) = self { return c }
        return nil
    }

    public var components: [ScoreComponent] {
        if case let .value(_, _, c) = self { return c }
        return []
    }

    public var missing: [DataRequirement] {
        if case let .notEnoughData(m) = self { return m }
        return []
    }
}

public enum Math {
    public static func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let m = s.count / 2
        return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
    }

    public static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    public static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count > 1, let m = mean(values) else { return nil }
        let v = values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count - 1)
        return v.squareRoot()
    }

    /// Median absolute deviation scaled to be comparable with a standard deviation.
    public static func robustSD(_ values: [Double]) -> Double? {
        guard let m = median(values) else { return nil }
        guard let mad = median(values.map { abs($0 - m) }) else { return nil }
        return 1.4826 * mad
    }

    public static func logistic(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    /// Least-squares slope per index step.
    public static func slope(_ values: [Double]) -> Double? {
        guard values.count >= 3 else { return nil }
        let n = Double(values.count)
        let xs = (0..<values.count).map(Double.init)
        let mx = xs.reduce(0, +) / n
        let my = values.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, y) in zip(xs, values) {
            num += (x - mx) * (y - my)
            den += (x - mx) * (x - mx)
        }
        return den == 0 ? nil : num / den
    }

    /// Linear interpolation of `x` from [x0,x1] to [y0,y1], clamped.
    public static func ramp(_ x: Double, from x0: Double, _ x1: Double, to y0: Double, _ y1: Double) -> Double {
        guard x1 != x0 else { return y1 }
        let t = clamp((x - x0) / (x1 - x0), 0, 1)
        return y0 + t * (y1 - y0)
    }
}
