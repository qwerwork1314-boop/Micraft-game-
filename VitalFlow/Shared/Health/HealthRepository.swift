import Foundation
import VitalFlowCore

/// Data the UI needs: per-day metrics plus raw intraday data for today.
struct HealthDataBundle: Sendable {
    var history: [DailyMetrics]
    var intraday: IntradayData
    var workouts: [WorkoutRecord]
    var sleepSamples: [SleepSample]
    /// Heart-rate samples recorded during last night's main sleep.
    var lastNightHeartRate: [QuantitySample]
    var isDemo: Bool
    var fetchedAt: Date
}

/// Source of health data. Production uses HealthKit; demo mode is explicit and labelled.
protocol HealthDataProvider: Sendable {
    func load(days: Int, now: Date, calendar: Calendar, profile: ScoringProfile) async -> HealthDataBundle
}

struct HealthKitDataProvider: HealthDataProvider {
    let hk = HealthKitService.shared

    func load(days: Int, now: Date, calendar: Calendar, profile: ScoringProfile) async -> HealthDataBundle {
        let today = DayKey(now, calendar: calendar)
        let dayKeys = (0..<days).map { today.adding(days: -(days - 1) + $0, calendar: calendar) }
        let rangeStart = dayKeys[0].startDate(in: calendar).addingTimeInterval(-86_400) // previous evening for sleep
        let todayStart = today.startDate(in: calendar)

        // Cumulative metrics via statistics (HealthKit de-duplicates across sources).
        async let steps = hk.dailyStatistics(.stepCount, days: dayKeys, calendar: calendar)
        async let distance = hk.dailyStatistics(.distanceWalkingRunning, days: dayKeys, calendar: calendar)
        async let active = hk.dailyStatistics(.activeEnergy, days: dayKeys, calendar: calendar)
        async let basal = hk.dailyStatistics(.basalEnergy, days: dayKeys, calendar: calendar)
        async let exercise = hk.dailyStatistics(.exerciseMinutes, days: dayKeys, calendar: calendar)
        async let daylight = hk.dailyStatistics(.timeInDaylight, days: dayKeys, calendar: calendar)
        async let water = hk.dailyStatistics(.dietaryWater, days: dayKeys, calendar: calendar)
        async let avgHR = hk.dailyStatistics(.heartRate, days: dayKeys, calendar: calendar)
        // Discrete metrics with low sample counts are read raw and de-duplicated by VitalFlowCore.
        async let hrv = hk.quantitySamples(.hrvSDNN, start: rangeStart, end: now)
        async let rhr = hk.quantitySamples(.restingHeartRate, start: rangeStart, end: now)
        async let resp = hk.quantitySamples(.respiratoryRate, start: rangeStart, end: now)
        async let temp = hk.quantitySamples(.wristTemperature, start: rangeStart, end: now)
        async let spo2 = hk.quantitySamples(.oxygenSaturation, start: rangeStart, end: now)
        async let vo2 = hk.quantitySamples(.vo2Max, start: rangeStart, end: now)
        async let mass = hk.quantitySamples(.bodyMass, start: rangeStart, end: now)
        async let sleep = hk.sleepSamples(start: rangeStart, end: now)
        async let workouts = hk.workouts(start: rangeStart, end: now)
        // Today's intraday raw data.
        async let hrToday = hk.quantitySamples(.heartRate, start: todayStart, end: now)
        async let stepsToday = hk.quantitySamples(.stepCount, start: todayStart, end: now)
        async let energyToday = hk.quantitySamples(.activeEnergy, start: todayStart, end: now)

        let (stepsV, distanceV, activeV, basalV, exerciseV, daylightV, waterV, avgHRV) =
            await (steps, distance, active, basal, exercise, daylight, water, avgHR)
        let discrete = await (hrv + rhr + resp + temp + spo2 + vo2 + mass)
        let sleepV = await sleep
        let workoutsV = await workouts

        let aggregator = DailyAggregator(calendar: calendar)
        let analyzer = SleepAnalyzer(calendar: calendar)
        let byKind = Dictionary(grouping: discrete, by: \.kind)
        let history: [DailyMetrics] = dayKeys.map { day in
            var m = DailyMetrics(day: day)
            m.sleep = analyzer.night(for: day, samples: sleepV)
            m.steps = stepsV[day]; m.distance = distanceV[day]; m.activeEnergy = activeV[day]
            m.basalEnergy = basalV[day]; m.exerciseMinutes = exerciseV[day]; m.daylightMinutes = daylightV[day]
            m.waterML = waterV[day]; m.averageHeartRate = avgHRV[day]
            m.restingHeartRate = aggregator.dailyMean(byKind[.restingHeartRate] ?? [], kind: .restingHeartRate, day: day)
            m.hrv = aggregator.nightlyHRV(byKind[.hrvSDNN] ?? [], day: day, sleep: m.sleep)
            m.respiratoryRate = aggregator.duringSleep(byKind[.respiratoryRate] ?? [], kind: .respiratoryRate, sleep: m.sleep)
            m.wristTemperature = aggregator.dailyMean(byKind[.wristTemperature] ?? [], kind: .wristTemperature, day: day)
            m.oxygenSaturation = aggregator.dailyMean(byKind[.oxygenSaturation] ?? [], kind: .oxygenSaturation, day: day)
            m.vo2Max = aggregator.latest(byKind[.vo2Max] ?? [], kind: .vo2Max, onOrBefore: day)
            m.bodyMass = aggregator.latest(byKind[.bodyMass] ?? [], kind: .bodyMass, onOrBefore: day)
            m.trainingLoad = TrainingLoad.dailyLoad(day: day, workouts: workoutsV, restingHR: m.restingHeartRate,
                                                    profile: profile, calendar: calendar)
            return m
        }
        let intraday = IntradayData(heartRate: await hrToday,
                                    hrv: (byKind[.hrvSDNN] ?? []).filter { $0.start >= todayStart },
                                    steps: await stepsToday, activeEnergy: await energyToday,
                                    workouts: workoutsV.filter { $0.end > todayStart })
        var nightHR: [QuantitySample] = []
        if let n = history.last?.sleep {
            nightHR = Deduplicator.dedupeDiscrete(await hk.quantitySamples(.heartRate, start: n.start, end: n.end))
        }
        return HealthDataBundle(history: history, intraday: intraday, workouts: workoutsV, sleepSamples: sleepV,
                                lastNightHeartRate: nightHR, isDemo: false, fetchedAt: now)
    }
}

/// DEMONSTRATION MODE. Synthetic, deterministic data that is always labelled in the UI.
struct DemoDataProvider: HealthDataProvider {
    func load(days: Int, now: Date, calendar: Calendar, profile: ScoringProfile) async -> HealthDataBundle {
        let ds = DemoDataGenerator.generate(days: days + 1, endingAt: now, calendar: calendar)
        let today = DayKey(now, calendar: calendar)
        let dayKeys = (0..<days).map { today.adding(days: -(days - 1) + $0, calendar: calendar) }
        let history = DailyAggregator(calendar: calendar).aggregate(days: dayKeys, quantities: ds.quantities, sleep: ds.sleep,
                                                                    workouts: ds.workouts, profile: profile)
        let start = today.startDate(in: calendar)
        let intraday = IntradayData(heartRate: ds.quantities.filter { $0.kind == .heartRate && $0.start >= start },
                                    hrv: ds.quantities.filter { $0.kind == .hrvSDNN && $0.start >= start },
                                    steps: ds.quantities.filter { $0.kind == .stepCount && $0.start >= start },
                                    activeEnergy: ds.quantities.filter { $0.kind == .activeEnergy && $0.start >= start },
                                    workouts: ds.workouts.filter { $0.end > start })
        let night = history.last?.sleep
        let nightHR = night.map { n in ds.quantities.filter { $0.kind == .heartRate && $0.start >= n.start && $0.start <= n.end } } ?? []
        return HealthDataBundle(history: history, intraday: intraday, workouts: ds.workouts, sleepSamples: ds.sleep,
                                lastNightHeartRate: nightHR, isDemo: true, fetchedAt: now)
    }
}
