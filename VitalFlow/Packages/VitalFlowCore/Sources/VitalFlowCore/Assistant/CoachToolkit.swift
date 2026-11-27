import Foundation

/// Compact, factual text summaries of the user's own data for an AI coach.
///
/// These strings are what a language model (Apple Intelligence on-device, or an opted-in
/// external provider) receives through tool calls. They contain only the numbers the user
/// already sees in the app, are kept short to fit small context windows, and always say
/// "not enough data" instead of inventing values.
public struct CoachToolkit: Sendable {
    public var assessment: DailyAssessment?
    public var history: [DailyMetrics]
    public var workouts: [WorkoutRecord]
    public var goals: GoalSet
    public var calendar: Calendar
    public var isDemo: Bool

    public init(assessment: DailyAssessment?, history: [DailyMetrics], workouts: [WorkoutRecord],
                goals: GoalSet, calendar: Calendar, isDemo: Bool) {
        self.assessment = assessment
        self.history = history.sorted { $0.day < $1.day }
        self.workouts = workouts
        self.goals = goals
        self.calendar = calendar
        self.isDemo = isDemo
    }

    /// Metric names accepted by `trendSummary`.
    public static let metrics = ["hrv", "restingHeartRate", "sleepHours", "steps", "activeEnergy", "exerciseMinutes",
                                 "respiratoryRate", "oxygenSaturation", "vo2Max", "bodyMass", "daylightMinutes",
                                 "waterML", "averageHeartRate"]

    var today: DayKey { assessment?.day ?? history.last?.day ?? DayKey(Date(), calendar: calendar) }

    private func f(_ v: Double?, _ digits: Int = 0) -> String {
        guard let v, v.isFinite else { return "n/a" }
        return String(format: "%.\(digits)f", v)
    }

    private func score(_ name: String, _ r: ScoreResult) -> String {
        if let s = r.score { return "\(name): \(s)/100 (confidence \(r.confidence?.rawValue ?? "low"))" }
        let missing = r.missing.map(\.rawValue).joined(separator: ", ")
        return "\(name): not enough data" + (missing.isEmpty ? "" : " (missing: \(missing))")
    }

    private var demoNote: String { isDemo ? "NOTE: this is synthetic DEMO data, not the user's real data.\n" : "" }

    // MARK: Tools

    public func todaySummary(details: Bool = true) -> String {
        guard let a = assessment else { return demoNote + "No data is available for today yet." }
        var lines = [demoNote + "Date: \(a.day)"]
        lines.append(score("Recovery", a.recovery))
        if details {
            for c in a.recovery.components {
                var t = "  - \(c.key): \(f(c.value, c.key == "wristTemperature" || c.key == "respiratoryRate" ? 1 : 0))"
                if let b = c.baseline { t += " (personal baseline \(f(b, c.key == "wristTemperature" || c.key == "respiratoryRate" ? 1 : 0)))" }
                t += c.effect > 0.3 ? ", better than usual" : c.effect < -0.3 ? ", worse than usual" : ", near usual"
                lines.append(t)
            }
        }
        lines.append(score("Sleep score", a.sleepScore))
        lines.append(score("Stress (daytime estimate)", a.stress.result))
        lines.append(score("Body Battery", a.bodyBattery.result))
        lines.append(score("Training readiness", a.readiness.result) + (a.readiness.level.map { ", level \($0.rawValue)" } ?? ""))
        if let b = a.balance { lines.append("Activity/recovery balance: \(b.rawValue), activity load \(a.activityLoad)/100") }
        if let r = a.readiness.acwr { lines.append("7-day/28-day training load ratio: \(f(r, 2))") }
        let m = a.metrics
        lines.append("Today so far: steps \(f(m.steps)), active energy \(f(m.activeEnergy)) kcal, exercise \(f(m.exerciseMinutes)) min, daylight \(f(m.daylightMinutes)) min, water \(f(m.waterML)) ml (goal \(f(goals.target(for: .waterML))) ml)")
        lines.append("Heart: latest \(f(a.latestHeartRate)) bpm, resting \(f(m.restingHeartRate)) bpm, HRV \(f(m.hrv)) ms")
        return lines.joined(separator: "\n")
    }

    /// `nightsAgo` 0 = the night that ended this morning.
    public func sleepSummary(nightsAgo: Int) -> String {
        let day = today.adding(days: -max(0, nightsAgo), calendar: calendar)
        guard let n = history.first(where: { $0.day == day })?.sleep else {
            return demoNote + "No sleep data recorded for the night ending \(day)."
        }
        func h(_ s: TimeInterval) -> String { String(format: "%.1f h", s / 3600) }
        var t = demoNote + "Night ending \(day): asleep \(h(n.asleep)), in bed \(h(n.timeInBed)), efficiency \(f(n.efficiency * 100))%, wake-ups \(n.interruptions), awake \(f(n.awake / 60)) min"
        if n.hasStageData { t += ", deep \(h(n.deep)), REM \(h(n.rem)), core \(h(n.core))" } else { t += ", no sleep-stage data" }
        if n.napDuration > 0 { t += ", naps \(f(n.napDuration / 60)) min" }
        let recent = history.filter { $0.day <= day && $0.day > day.adding(days: -7, calendar: calendar) }.compactMap(\.sleep)
        if let avg = Math.mean(recent.map(\.asleep)) { t += "\n7-night average asleep: \(h(avg)) over \(recent.count) nights" }
        t += "\nSleep need setting: \(f(goals.target(for: .sleepHours), 1)) h"
        return t
    }

    public func value(_ metric: String, _ m: DailyMetrics) -> Double? {
        switch metric {
        case "hrv": return m.hrv
        case "restingHeartRate": return m.restingHeartRate
        case "sleepHours": return m.sleep.map { $0.asleep / 3600 }
        case "steps": return m.steps
        case "activeEnergy": return m.activeEnergy
        case "exerciseMinutes": return m.exerciseMinutes
        case "respiratoryRate": return m.respiratoryRate
        case "oxygenSaturation": return m.oxygenSaturation.map { $0 * 100 }
        case "vo2Max": return m.vo2Max
        case "bodyMass": return m.bodyMass
        case "daylightMinutes": return m.daylightMinutes
        case "waterML": return m.waterML
        case "averageHeartRate": return m.averageHeartRate
        default: return nil
        }
    }

    public func trendSummary(metric: String, days: Int) -> String {
        guard Self.metrics.contains(metric) else {
            return "Unknown metric '\(metric)'. Use one of: \(Self.metrics.joined(separator: ", "))."
        }
        let n = Math.clamp(days, 7, 365)
        let start = today.adding(days: -(n - 1), calendar: calendar)
        let window = history.filter { $0.day >= start && $0.day <= today }
        let values = window.compactMap { m in value(metric, m).map { (m.day, $0) } }
        guard values.count >= 3 else {
            return demoNote + "\(metric): not enough data in the last \(n) days (\(values.count) days with a value)."
        }
        let v = values.map(\.1)
        let digits = ["respiratoryRate", "vo2Max", "bodyMass", "sleepHours", "oxygenSaturation"].contains(metric) ? 1 : 0
        let half = v.count / 2
        let first = Math.mean(Array(v.prefix(half))), second = Math.mean(Array(v.suffix(v.count - half)))
        var t = demoNote + "\(metric) over the last \(n) days (\(values.count) days with data): average \(f(Math.mean(v), digits)), min \(f(v.min(), digits)), max \(f(v.max(), digits))"
        if let a = first, let b = second, a != 0 {
            t += "\nFirst half average \(f(a, digits)) -> second half average \(f(b, digits)) (\(b >= a ? "+" : "")\(f((b - a) / abs(a) * 100, 1))%)"
        }
        let tr = TrendAnalyzer.trend(metric: metric == "sleepHours" ? "sleep" : metric, day: today, period: 7,
                                     history: history, value: { value(metric, $0) }, calendar: calendar)
        if tr.direction != .insufficient { t += "\nThis week vs last week: \(tr.direction.rawValue)" }
        let recent = values.suffix(7).map { "\($0.0): \(f($0.1, digits))" }.joined(separator: "; ")
        t += "\nMost recent values: \(recent)"
        if metric == "restingHeartRate" || metric == "respiratoryRate" { t += "\n(For this metric, lower is generally favourable for recovery.)" }
        return t
    }

    public func workoutsSummary(days: Int) -> String {
        let n = Math.clamp(days, 1, 90)
        let start = today.adding(days: -(n - 1), calendar: calendar).startDate(in: calendar)
        var seen = Set<String>()
        let list = workouts.filter { $0.start >= start && seen.insert($0.id).inserted }.sorted { $0.start > $1.start }
        guard !list.isEmpty else { return demoNote + "No workouts recorded in the last \(n) days." }
        let rows = list.prefix(12).map { w -> String in
            var s = "\(DayKey(w.start, calendar: calendar)) \(w.activity.rawValue) \(f(w.duration / 60)) min"
            if let e = w.activeEnergy { s += ", \(f(e)) kcal" }
            if let d = w.distance { s += ", \(f(d / 1000, 1)) km" }
            if let hr = w.averageHeartRate { s += ", avg HR \(f(hr))" }
            return s
        }
        return demoNote + "\(list.count) workouts in the last \(n) days (newest first):\n" + rows.joined(separator: "\n")
    }

    public func goalsSummary() -> String {
        let g = Garden.build(history: history, goals: goals)
        var lines = [demoNote + "Garden: \(g.plants.count) plants, total growth \(g.totalGrowth), current rhythm \(g.currentStreak) days, best \(g.bestStreak) days"]
        if let m = assessment?.metrics {
            for k in GoalKind.allCases where goals.enabled.contains(k) {
                lines.append("Goal \(k.rawValue): \(f(k.value(from: m), k == .sleepHours ? 1 : 0)) of \(f(goals.target(for: k), k == .sleepHours ? 1 : 0)) (\(f(goals.progress(k, metrics: m) * 100))%)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Everything a one-shot daily briefing needs, in one compact block.
    public func briefingContext() -> String {
        [todaySummary(details: true), sleepSummary(nightsAgo: 0), goalsSummary()].joined(separator: "\n\n")
    }

    /// True when there is at least some real measurement in the last 7 days.
    public var hasRecentData: Bool {
        history.suffix(7).contains {
            $0.steps != nil || $0.sleep != nil || $0.restingHeartRate != nil || $0.activeEnergy != nil || $0.averageHeartRate != nil
        }
    }
}
