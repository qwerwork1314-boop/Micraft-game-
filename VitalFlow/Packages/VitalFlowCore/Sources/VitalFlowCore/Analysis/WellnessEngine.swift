import Foundation

/// Intraday raw data for "today", needed for stress and Body Battery.
public struct IntradayData: Codable, Hashable, Sendable {
    public var heartRate: [QuantitySample]
    public var hrv: [QuantitySample]
    public var steps: [QuantitySample]
    public var activeEnergy: [QuantitySample]
    public var workouts: [WorkoutRecord]

    public init(heartRate: [QuantitySample] = [], hrv: [QuantitySample] = [], steps: [QuantitySample] = [],
                activeEnergy: [QuantitySample] = [], workouts: [WorkoutRecord] = []) {
        self.heartRate = heartRate
        self.hrv = hrv
        self.steps = steps
        self.activeEnergy = activeEnergy
        self.workouts = workouts
    }
}

/// Everything VitalFlow knows about one day. Serialisable for widgets and the watch.
public struct DailyAssessment: Codable, Hashable, Sendable {
    public var day: DayKey
    public var generatedAt: Date
    public var metrics: DailyMetrics
    public var recovery: ScoreResult
    public var sleepScore: ScoreResult
    public var sleepConsistency: ScoreResult
    public var stress: StressReport
    public var bodyBattery: BodyBatteryReport
    public var readiness: TrainingReadiness
    public var activityLoad: Int
    public var balance: ActivityRecoveryBalance?
    public var trends: [MetricTrend]
    public var latestHeartRate: Double?
    public var isDemo: Bool
}

public struct WellnessEngine: Sendable {
    public var calendar: Calendar
    public var profile: ScoringProfile

    public init(calendar: Calendar, profile: ScoringProfile) {
        self.calendar = calendar
        self.profile = profile
    }

    public func assess(day: DayKey, history: [DailyMetrics], intraday: IntradayData,
                       now: Date, isDemo: Bool) -> DailyAssessment {
        let today = history.first { $0.day == day } ?? DailyMetrics(day: day)
        let analyzer = SleepAnalyzer(calendar: calendar)
        let recentNights = history
            .filter { $0.day <= day && $0.day > day.adding(days: -7, calendar: calendar) }
            .compactMap(\.sleep)
        let consistency = analyzer.consistency(of: recentNights)
        let sleep = SleepScorer.score(today.sleep, consistency: consistency.score, profile: profile)
        let recovery = RecoveryScorer.score(day: day, history: history, sleepScore: sleep.score, calendar: calendar)
        let stress = StressEstimator.estimate(day: day, heartRate: intraday.heartRate, hrv: intraday.hrv,
                                              steps: intraday.steps, workouts: intraday.workouts,
                                              history: history, profile: profile, calendar: calendar, now: now)
        let hourly = hourlyTotals(intraday.activeEnergy, day: day)
        let hourlySteps = hourlyTotals(intraday.steps, day: day)
        let battery = BodyBatteryEstimator.estimate(recovery: recovery.score, sleepScore: sleep.score,
                                                    wakeTime: today.sleep?.end, hourlyActiveEnergy: hourly,
                                                    hourlyStress: stress.hourly, hourlySteps: hourlySteps,
                                                    now: now, calendar: calendar)
        let readiness = ReadinessCalculator.readiness(day: day, recovery: recovery, history: history, calendar: calendar)
        let load = BalanceCalculator.activityLoadScore(todayLoad: today.trainingLoad ?? 0, chronic: readiness.chronicLoad)
        let latestHR = Deduplicator.dedupeDiscrete(intraday.heartRate).max { $0.start < $1.start }?.value
        return DailyAssessment(day: day, generatedAt: now, metrics: today, recovery: recovery, sleepScore: sleep,
                               sleepConsistency: consistency, stress: stress, bodyBattery: battery,
                               readiness: readiness, activityLoad: load,
                               balance: BalanceCalculator.balance(recovery: recovery.score, activityLoad: load),
                               trends: TrendAnalyzer.weekly(day: day, history: history, calendar: calendar),
                               latestHeartRate: latestHR, isDemo: isDemo)
    }

    func hourlyTotals(_ samples: [QuantitySample], day: DayKey) -> [(Date, Double)] {
        let start = day.startDate(in: calendar)
        return (0..<24).compactMap { h in
            guard let a = calendar.date(byAdding: .hour, value: h, to: start),
                  let b = calendar.date(byAdding: .hour, value: h + 1, to: start) else { return nil }
            let v = Deduplicator.mergedCumulativeTotal(samples, start: a, end: b)
            return v > 0 ? (a, v) : nil
        }
    }
}
