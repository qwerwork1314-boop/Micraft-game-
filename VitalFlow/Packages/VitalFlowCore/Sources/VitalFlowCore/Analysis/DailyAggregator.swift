import Foundation

/// Builds `DailyMetrics` from raw samples. Used for demo data, tests and for metrics the
/// app reads as raw samples (HRV, resting HR, respiratory rate …). Cumulative metrics in
/// production come from HealthKit statistics queries, which de-duplicate across sources.
public struct DailyAggregator: Sendable {
    public var calendar: Calendar
    public init(calendar: Calendar) { self.calendar = calendar }

    /// Splits a cumulative total across local days, proportionally to time (midnight-safe, DST-safe).
    public func cumulativeTotals(_ samples: [QuantitySample], days: [DayKey]) -> [DayKey: Double] {
        // Bucket samples by every local day they touch so each day only scans its own samples.
        var buckets: [DayKey: [QuantitySample]] = [:]
        for s in samples {
            var d = DayKey(s.start, calendar: calendar)
            let last = DayKey(s.end > s.start ? s.end.addingTimeInterval(-0.001) : s.start, calendar: calendar)
            buckets[d, default: []].append(s)
            while d < last {
                d = d.adding(days: 1, calendar: calendar)
                buckets[d, default: []].append(s)
            }
        }
        var out: [DayKey: Double] = [:]
        for d in days {
            let total = Deduplicator.mergedCumulativeTotal(buckets[d] ?? [], start: d.startDate(in: calendar), end: d.endDate(in: calendar))
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
        // De-duplicate discrete metrics once, then bucket by local start day.
        var discrete: [MetricKind: [DayKey: [QuantitySample]]] = [:]
        for kind in MetricKind.allCases where !kind.isCumulative {
            discrete[kind] = Dictionary(grouping: Deduplicator.dedupeDiscrete(byKind[kind] ?? []),
                                        by: { DayKey($0.start, calendar: calendar) })
        }
        func around(_ kind: MetricKind, _ day: DayKey) -> [QuantitySample] {
            (discrete[kind]?[day.adding(days: -1, calendar: calendar)] ?? []) + (discrete[kind]?[day] ?? [])
        }
        var lastVO2: Double?, lastMass: Double?
        return days.sorted().map { day in
            var m = DailyMetrics(day: day)
            let sleepWindow = analyzer.window(for: day)
            m.sleep = analyzer.night(for: day, samples: sleep.filter { $0.end > sleepWindow.start && $0.start < sleepWindow.end })
            m.restingHeartRate = dailyMean(discrete[.restingHeartRate]?[day] ?? [], kind: .restingHeartRate, day: day)
            m.hrv = nightlyHRV(around(.hrvSDNN, day), day: day, sleep: m.sleep)
            m.averageHeartRate = dailyMean(discrete[.heartRate]?[day] ?? [], kind: .heartRate, day: day)
            m.oxygenSaturation = dailyMean(discrete[.oxygenSaturation]?[day] ?? [], kind: .oxygenSaturation, day: day)
            m.respiratoryRate = duringSleep(around(.respiratoryRate, day), kind: .respiratoryRate, sleep: m.sleep)
                ?? dailyMean(discrete[.respiratoryRate]?[day] ?? [], kind: .respiratoryRate, day: day)
            m.wristTemperature = dailyMean(discrete[.wristTemperature]?[day] ?? [], kind: .wristTemperature, day: day)
            m.steps = cumulative[.stepCount]?[day]
            m.distance = cumulative[.distanceWalkingRunning]?[day]
            m.activeEnergy = cumulative[.activeEnergy]?[day]
            m.basalEnergy = cumulative[.basalEnergy]?[day]
            m.exerciseMinutes = cumulative[.exerciseMinutes]?[day]
            m.daylightMinutes = cumulative[.timeInDaylight]?[day]
            m.waterML = cumulative[.dietaryWater]?[day]
            // Sparse metrics carry forward the latest known value.
            if let v = dailyMean(discrete[.vo2Max]?[day] ?? [], kind: .vo2Max, day: day) { lastVO2 = v }
            if let v = dailyMean(discrete[.bodyMass]?[day] ?? [], kind: .bodyMass, day: day) { lastMass = v }
            m.vo2Max = lastVO2
            m.bodyMass = lastMass
            m.trainingLoad = TrainingLoad.dailyLoad(day: day, workouts: workouts, restingHR: m.restingHeartRate,
                                                    profile: profile, calendar: calendar)
            return m
        }
    }
}
