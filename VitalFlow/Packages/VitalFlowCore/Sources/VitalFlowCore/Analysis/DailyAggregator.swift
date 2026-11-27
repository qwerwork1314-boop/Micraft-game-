import Foundation

/// Builds `DailyMetrics` from raw samples. Used for demo data, tests and for metrics the
/// app reads as raw samples (HRV, resting HR, respiratory rate …). Cumulative metrics in
/// production come from HealthKit statistics queries, which de-duplicate across sources.
public struct DailyAggregator: Sendable {
    public var calendar: Calendar
    public init(calendar: Calendar) { self.calendar = calendar }

    /// Splits a cumulative total across local days, proportionally to time (midnight-safe, DST-safe).
    public func cumulativeTotals(_ samples: [QuantitySample], days: [DayKey]) -> [DayKey: Double] {
        var out: [DayKey: Double] = [:]
        for d in days {
            let total = Deduplicator.mergedCumulativeTotal(samples, start: d.startDate(in: calendar), end: d.endDate(in: calendar))
            if total > 0 { out[d] = total }
        }
        return out
    }

    /// Nightly HRV: mean of SDNN samples during the main sleep; otherwise the day's median.
    public func nightlyHRV(_ samples: [QuantitySample], day: DayKey, sleep: SleepNight?) -> Double? {
        let all = Deduplicator.dedupeDiscrete(samples.filter { $0.kind == .hrvSDNN && $0.value > 0 })
        if let sleep {
            let inSleep = all.filter { $0.start >= sleep.start && $0.start <= sleep.end }.map(\.value)
            if let m = Math.mean(inSleep) { return m }
        }
        let dayValues = all.filter { DayKey($0.start, calendar: calendar) == day }.map(\.value)
        return Math.median(dayValues)
    }

    /// Mean of a discrete metric's samples whose start falls within the local day.
    public func dailyMean(_ samples: [QuantitySample], kind: MetricKind, day: DayKey) -> Double? {
        let v = Deduplicator.dedupeDiscrete(samples.filter { $0.kind == kind })
            .filter { DayKey($0.start, calendar: calendar) == day }.map(\.value)
        return Math.mean(v)
    }

    /// Latest value of a discrete metric on or before the end of the day.
    public func latest(_ samples: [QuantitySample], kind: MetricKind, onOrBefore day: DayKey) -> Double? {
        let end = day.endDate(in: calendar)
        return samples.filter { $0.kind == kind && $0.start < end }.max { $0.start < $1.start }?.value
    }

    /// Mean of a discrete metric during the main sleep (respiratory rate, sleeping temperature).
    public func duringSleep(_ samples: [QuantitySample], kind: MetricKind, sleep: SleepNight?) -> Double? {
        guard let sleep else { return nil }
        let v = Deduplicator.dedupeDiscrete(samples.filter { $0.kind == kind })
            .filter { $0.start >= sleep.start.addingTimeInterval(-1800) && $0.start <= sleep.end.addingTimeInterval(1800) }
            .map(\.value)
        return Math.mean(v)
    }

    /// Full aggregation for a list of days.
    public func aggregate(days: [DayKey], quantities: [QuantitySample], sleep: [SleepSample],
                          workouts: [WorkoutRecord], profile: ScoringProfile) -> [DailyMetrics] {
        let analyzer = SleepAnalyzer(calendar: calendar)
        let byKind = Dictionary(grouping: quantities, by: \.kind)
        var cumulative: [MetricKind: [DayKey: Double]] = [:]
        for kind in MetricKind.allCases where kind.isCumulative {
            cumulative[kind] = cumulativeTotals(byKind[kind] ?? [], days: days)
        }
        return days.map { day in
            var m = DailyMetrics(day: day)
            m.sleep = analyzer.night(for: day, samples: sleep)
            m.restingHeartRate = dailyMean(byKind[.restingHeartRate] ?? [], kind: .restingHeartRate, day: day)
            m.hrv = nightlyHRV(byKind[.hrvSDNN] ?? [], day: day, sleep: m.sleep)
            m.averageHeartRate = dailyMean(byKind[.heartRate] ?? [], kind: .heartRate, day: day)
            m.oxygenSaturation = dailyMean(byKind[.oxygenSaturation] ?? [], kind: .oxygenSaturation, day: day)
            m.respiratoryRate = duringSleep(byKind[.respiratoryRate] ?? [], kind: .respiratoryRate, sleep: m.sleep)
                ?? dailyMean(byKind[.respiratoryRate] ?? [], kind: .respiratoryRate, day: day)
            m.wristTemperature = dailyMean(byKind[.wristTemperature] ?? [], kind: .wristTemperature, day: day)
            m.steps = cumulative[.stepCount]?[day]
            m.distance = cumulative[.distanceWalkingRunning]?[day]
            m.activeEnergy = cumulative[.activeEnergy]?[day]
            m.basalEnergy = cumulative[.basalEnergy]?[day]
            m.exerciseMinutes = cumulative[.exerciseMinutes]?[day]
            m.daylightMinutes = cumulative[.timeInDaylight]?[day]
            m.waterML = cumulative[.dietaryWater]?[day]
            m.bodyMass = dailyMean(byKind[.bodyMass] ?? [], kind: .bodyMass, day: day)
            m.vo2Max = dailyMean(byKind[.vo2Max] ?? [], kind: .vo2Max, day: day)
            m.trainingLoad = TrainingLoad.dailyLoad(day: day, workouts: workouts, restingHR: m.restingHeartRate,
                                                    profile: profile, calendar: calendar)
            return m
        }
    }
}
